# frozen_string_literal: true

module Planify
  module Services
    # core/Services/CalDAV. Discovery finds the principal and the calendar
    # home, each VTODO calendar becomes a project, and each VTODO in it an
    # item. Nextcloud and generic CalDAV differ only in the properties asked
    # for during discovery.
    module CalDAV
      SyncStatus = Struct.new(:kind, :title, :message)

      PRINCIPAL_XML = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <propfind xmlns="DAV:">
          <prop><current-user-principal/></prop>
        </propfind>
      XML

      HOME_XML = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <propfind xmlns="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
          <prop><cal:calendar-home-set/></prop>
        </propfind>
      XML

      USERDATA_XML = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:s="http://sabredav.org/ns">
          <d:prop><d:displayname/><s:email-address/></d:prop>
        </d:propfind>
      XML

      CALENDARS_XML = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:ical="http://apple.com/ns/ical/"
                    xmlns:cal="urn:ietf:params:xml:ns:caldav">
          <d:prop>
            <d:resourcetype/>
            <d:displayname/>
            <d:sync-token/>
            <cal:supported-calendar-component-set/>
            <ical:calendar-color/>
          </d:prop>
        </d:propfind>
      XML

      TODOS_XML = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:prop><d:getetag/><c:calendar-data/></d:prop>
          <c:filter>
            <c:comp-filter name="VCALENDAR">
              <c:comp-filter name="VTODO"/>
            </c:comp-filter>
          </c:filter>
        </c:calendar-query>
      XML

      module_function

      def store = Store.instance

      # --- discovery -------------------------------------------------------

      # Runs the whole chain and answers once, because every step depends on
      # the one before it and the caller only cares whether the account works.
      def discover(source, &done)
        WebDAV.propfind(
          source,
          "",
          PRINCIPAL_XML,
          "0",
        ) do |response, resources|
          if !response.ok?
            done.call(false, failure_for(response))
          else
            principal_href(resources).then do |principal|
              if principal.empty?
                done.call(false, _("The server did not identify this user."))
              else
                discover_home(source, principal, &done)
              end
            end
          end
        end
      end

      def principal_href(resources)
        resources.filter_map { |resource| resource.prop("current-user-principal") }
                 .filter_map { |element| WebDAV.href_in(element) }.first.to_s
      end

      def discover_home(source, principal, &done)
        WebDAV.propfind(
          source,
          principal,
          HOME_XML,
          "0",
        ) do |response, resources|
          resources.filter_map { |resource| resource.prop("calendar-home-set") }
                   .filter_map { |element| WebDAV.href_in(element) }.first.to_s.then do |home|
            if !response.ok? || home.empty?
              done.call(false, _("The server did not report a calendar home."))
            else
              source["calendar_home_url"] = WebDAV.absolute(source, home)
              fetch_userdata(source, principal, &done)
            end
          end
        end
      end

      def fetch_userdata(source, principal, &done)
        WebDAV.propfind(
          source,
          principal,
          USERDATA_XML,
          "0",
        ) do |_, resources|
          resources.each do |resource|
            resource.prop("displayname")&.text.then do |name|
              unless name.nil?
                source["user_displayname"] = name.to_s.strip
              end
            end
            resource.prop("email-address")&.text.then do |email|
              unless email.nil?
                source["user_email"] = email.to_s.strip
              end
            end
          end

          source.display_name = display_name_for(source)
          done.call(true, nil)
        end
      end

      def display_name_for(source)
        [source["user_displayname"], source["username"]].map(&:to_s).find { |v| !v.empty? }.to_s
      end

      # --- sync ------------------------------------------------------------

      def sync(source, &done)
        store.emit(:sync_started, source)
        LogService.info("CalDAV", "sync started for #{source.display_name}")

        fetch_calendars(source) do |ok, error|
          if !ok
            fail_sync(source, error, &done)
          else
            sync_projects(source, store.projects_by_source(source.id), &done)
          end
        end
      end

      def fail_sync(source, error, &done)
        classify(error).then do |status|
          LogService.error("CalDAV", "sync failed: #{status.message}")
          store.emit(:sync_failed, source, status.message)
          done&.call(false, status.message)
        end
      end

      def failure_for(response)
        if response.status == 401
          _("Authentication failed. Remove and re-add this account in Preferences.")
        elsif response.status == 429
          _("The server is rate limiting requests. Wait a few minutes and try again.")
        elsif response.error
          response.error
        else
          _("The server replied with HTTP %d.") % response.status
        end
      end

      def classify(message)
        if message.to_s.include?("401") || message.to_s.include?("Authentication")
          SyncStatus.new(:auth_expired, _("Authentication Expired"), message.to_s)
        elsif message.to_s.include?("429")
          SyncStatus.new(:server_error, _("Too Many Requests"), message.to_s)
        else
          SyncStatus.new(:error, _("Sync Failed"), message.to_s)
        end
      end

      # Only calendars that accept VTODO are task lists; a server's contacts
      # and events collections come back in the same listing.
      def fetch_calendars(source, &done)
        WebDAV.propfind(
          source,
          source.calendar_home_url,
          CALENDARS_XML,
          "1",
        ) do |response, resources|
          if !response.ok?
            done.call(false, failure_for(response))
          else
            resources.select { |resource| task_list?(resource) }
                     .each { |resource| upsert_project(source, resource) }
            done.call(true, nil)
          end
        end
      end

      def task_list?(resource)
        resource.ok? && !resource.prop("supported-calendar-component-set").nil? &&
          WebDAV.descend(resource.prop("supported-calendar-component-set"), "comp")
                .any? { |comp| comp.attributes["name"].to_s.casecmp?("VTODO") }
      end

      def upsert_project(source, resource)
        calendar_id(resource).then do |id|
          store.project(id).then do |project|
            if project.nil?
              store.insert_project(project_from(source, resource, id), queue: false)
            else
              store.update_project(assign_project(project, resource), queue: false)
            end
          end
        end
      end

      # The collection URL is the identity: it is stable, and it is what every
      # later request needs.
      def calendar_id(resource) = Digest::SHA256.hexdigest(resource.href.to_s)[0, 32]

      def project_from(source, resource, id)
        Project.new(
          id:           id,
          source_id:    source.id,
          backend_type: "caldav",
        ).tap { |project| assign_project(project, resource) }
      end

      def assign_project(project, resource)
        project.tap do |record|
          record.name = resource.prop("displayname")&.text.to_s.strip
          record.calendar_url = resource.href.to_s
          record.sync_id = resource.prop("sync-token")&.text.to_s.strip
          record.color = calendar_color(resource, record.color)
        end
      end

      # Apple's calendar-color is #rrggbbaa; the alpha is dropped.
      def calendar_color(resource, fallback)
        resource.prop("calendar-color")&.text.to_s.strip.then do |value|
          value.empty? ? fallback : value[0, 7]
        end
      end

      def sync_projects(source, projects, &done)
        if projects.empty?
          finish_sync(source, &done)
        else
          remaining = projects.dup
          step = nil
          step = lambda do
            if remaining.empty?
              flush_queue(source) { finish_sync(source, &done) }
            else
              sync_tasklist(source, remaining.shift) { step.call }
            end
          end
          step.call
        end
      end

      # Deck rides on the same account, so it syncs after the calendars when
      # the account has it switched on.
      def finish_sync(source, &done)
        if deck_enabled?(source)
          Deck.sync(source) { complete_sync(source, &done) }
        else
          complete_sync(source, &done)
        end
      end

      def deck_enabled?(source)
        source["caldav_type"] == "nextcloud" && source["use_deck"] == true
      end

      def complete_sync(source, &done)
        source.last_sync = Time.now.iso8601
        store.update_source(source)
        store.emit(:sync_finished, source)
        LogService.info("CalDAV", "sync finished for #{source.display_name}")
        done&.call(true, nil)
      end

      # A calendar-query returns every VTODO with its etag. Anything the
      # server no longer lists has been deleted there, so it goes locally too.
      def sync_tasklist(source, project, &done)
        WebDAV.report(
          source,
          project.calendar_url,
          TODOS_XML,
          "1",
        ) do |response, resources|
          if !response.ok?
            LogService.warn("CalDAV", "#{project.name}: #{failure_for(response)}")
          else
            apply_tasklist(source, project, resources)
          end

          done&.call
        end
      end

      def apply_tasklist(_source, project, resources)
        resources.select(&:ok?).filter_map { |resource| apply_todo(project, resource) }
                 .then { |seen| prune(project, seen) }
      end

      def apply_todo(project, resource)
        resource.prop("calendar-data")&.text.then do |data|
          if data.to_s.strip.empty?
            nil
          else
            upsert_item(project, data, resource).id
          end
        end
      end

      def upsert_item(project, data, resource)
        Ical.to_item(data, project.id).then do |parsed|
          store.item(parsed.id).then do |existing|
            if existing.nil?
              store.insert_item(parsed, queue: false).tap { |item| remember_url(item, resource) }
            else
              merge_item(existing, data, resource)
            end
          end
        end
      end

      def merge_item(item, data, resource)
        item.tap do |record|
          Ical.assign(record, Ical.parse_todo(data))
          remember_url(record, resource)
          store.update_item(record, queue: false)
        end
      end

      # The href and etag are what a later PUT needs: the href to address the
      # object, the etag to avoid overwriting a change made elsewhere.
      def remember_url(item, resource)
        item.extra_data = JSON.generate(
          "ical_url" => resource.href.to_s,
          "etag"     => resource.prop("getetag")&.text.to_s.strip,
        )
      end

      def extra(item)
        begin
          JSON.parse(item.extra_data.to_s)
        rescue JSON::ParserError
          {}
        end.then { |parsed| parsed.is_a?(Hash) ? parsed : {} }
      end

      def prune(project, seen)
        store.items_by_project(project.id).reject { |item| seen.include?(item.id) }
             .each { |item| store.delete_item(item, queue: false) }
      end

      # --- pushing ---------------------------------------------------------

      # CalDAV has no batch command, so the queue is replayed one entry at a
      # time; an entry that fails stays for the next sync.
      def flush_queue(source, &done)
        SyncQueue.all(source.id).then do |entries|
          if entries.empty?
            done&.call
          else
            remaining = entries.dup
            step = nil
            step = lambda do
              if remaining.empty?
                done&.call
              else
                push(source, remaining.shift) { step.call }
              end
            end
            step.call
          end
        end
      end

      HANDLERS = {
        "item_add"        => :push_item,
        "item_update"     => :push_item,
        "item_complete"   => :push_item,
        "item_uncomplete" => :push_item,
        "item_delete"     => :delete_item,
        "project_add"     => :push_project,
        "project_update"  => :push_project,
        "project_delete"  => :delete_project,
      }.freeze

      def push(source, entry, &done)
        HANDLERS.fetch(entry.query, nil).then do |handler|
          if handler.nil?
            # Sections and labels have no CalDAV representation; the entry is
            # dropped rather than retried forever.
            SyncQueue.remove(entry)
            done.call
          else
            public_send(
              handler,
              source,
              entry,
              &done
            )
          end
        end
      end

      def push_item(source, entry, &done)
        store.item(entry.target_id).then do |item|
          if item.nil?
            SyncQueue.remove(entry)
            done.call
          elsif deck?(item)
            push_deck_card(
              source,
              item,
              entry,
              &done
            )
          else
            put_item(
              source,
              item,
              entry,
              &done
            )
          end
        end
      end

      # A Deck card lives behind the Deck REST API, not as an .ics resource,
      # so it cannot be PUT to a calendar collection.
      def deck?(record)
        store.project(record.project_id)&.backend_type == "deck"
      end

      def push_deck_card(source, item, entry, &done)
        Deck.push_card(source, item) do |ok|
          if ok
            SyncQueue.remove(entry)
          end
          done.call
        end
      end

      def put_item(source, item, entry, &done)
        item_url(source, item).then do |url|
          WebDAV.request(
            source,
            "PUT",
            url,
            body:    Ical.from_item(item),
            headers: { "Content-Type" => "text/calendar; charset=utf-8" },
          ) do |response|
            settle(
              entry,
              response,
              item,
              &done
            )
          end
        end
      end

      def item_url(source, item)
        extra(item)["ical_url"].to_s.then do |known|
          if known.empty?
            project_url_for(source, item).then { |base| File.join(base, "#{item.id}.ics") }
          else
            known
          end
        end
      end

      def project_url_for(_source, item)
        store.project(item.project_id).then { |project| project&.calendar_url.to_s }
      end

      def settle(entry, response, item, &done)
        if response.ok?
          record_etag(item, response)
          SyncQueue.remove(entry)
        else
          LogService.warn("CalDAV", "#{entry.query} failed: #{failure_for(response)}")
        end

        done.call
      end

      def record_etag(item, response)
        response.headers.fetch("etag", []).first.then do |etag|
          unless etag.nil?
            item.extra_data = JSON.generate(extra(item).merge("etag" => etag.to_s))
            store.database.update(item)
          end
        end
      end

      def delete_item(source, entry, &done)
        if entry.arguments["backend"].to_s == "deck"
          delete_deck_card(source, entry, &done)
        else
          delete_ical(source, entry, &done)
        end
      end

      # The card is already gone locally, so the ids it needs come from the
      # queued entry rather than from the store.
      def delete_deck_card(source, entry, &done)
        Item.new(
          id:         entry.target_id,
          project_id: entry.arguments["project_id"].to_s,
          section_id: entry.arguments["section_id"].to_s,
        ).then do |stub|
          Deck.delete_card(source, stub) do |ok|
            if ok
              SyncQueue.remove(entry)
            end
            done.call
          end
        end
      end

      def delete_ical(source, entry, &done)
        entry.arguments["ical_url"].to_s.then do |url|
          if url.empty?
            SyncQueue.remove(entry)
            done.call
          else
            WebDAV.request(source, "DELETE", url) do |response|
              if response.ok? || response.status == 404
                SyncQueue.remove(entry)
              end
              done.call
            end
          end
        end
      end

      def push_project(source, entry, &done)
        store.project(entry.target_id).then do |project|
          if project.nil? || !project.calendar_url.to_s.empty?
            SyncQueue.remove(entry)
            done.call
          else
            create_calendar(
              source,
              project,
              entry,
              &done
            )
          end
        end
      end

      # A new project becomes a calendar collection that accepts VTODO.
      def create_calendar(source, project, entry, &done)
        File.join(source.calendar_home_url, "#{project.id}/").then do |url|
          WebDAV.request(
            source,
            "MKCALENDAR",
            url,
            body: mkcalendar_xml(project),
          ) do |response|
            if response.ok?
              project.calendar_url = url
              store.database.update(project)
              SyncQueue.remove(entry)
            else
              LogService.warn("CalDAV", "MKCALENDAR failed: #{failure_for(response)}")
            end

            done.call
          end
        end
      end

      def mkcalendar_xml(project)
        <<~XML
          <?xml version="1.0" encoding="utf-8"?>
          <c:mkcalendar xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"
                        xmlns:ical="http://apple.com/ns/ical/">
            <d:set><d:prop>
              <d:displayname>#{escape_xml(project.name)}</d:displayname>
              <ical:calendar-color>#{Palette.hex(project.color)}</ical:calendar-color>
              <c:supported-calendar-component-set><c:comp name="VTODO"/></c:supported-calendar-component-set>
            </d:prop></d:set>
          </c:mkcalendar>
        XML
      end

      def delete_project(source, entry, &done)
        entry.arguments["calendar_url"].to_s.then do |url|
          if url.empty?
            SyncQueue.remove(entry)
            done.call
          else
            WebDAV.request(source, "DELETE", url) do |response|
              if response.ok? || response.status == 404
                SyncQueue.remove(entry)
              end
              done.call
            end
          end
        end
      end

      def escape_xml(text)
        text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
            .gsub('"', "&quot;").gsub("'", "&apos;")
      end

      # --- account setup ---------------------------------------------------

      def build_source(server_url, username, password, kind, ignore_ssl)
        Source.new(source_type: "caldav", sync_server: 1).tap do |source|
          source.merge_payload(
            "server_url"  => server_url,
            "username"    => username,
            "password"    => password,
            "caldav_type" => kind,
            "ignore_ssl"  => ignore_ssl,
          )
        end
      end

      # The account is only stored once discovery and the first calendar
      # listing have both worked, so a bad URL or password leaves nothing
      # behind in the sidebar.
      def add_account(source, &done)
        discover(source) do |ok, error|
          if !ok
            done.call(false, error)
          else
            store.insert_source(source)
            fetch_calendars(source) do |listed, list_error|
              if listed
                sync_projects_for(source) { done.call(true, nil) }
              else
                store.delete_source(source)
                done.call(false, list_error)
              end
            end
          end
        end
      end

      def sync_projects_for(source, &done)
        sync_projects(source, store.projects_by_source(source.id), &done)
      end
    end
  end
end
