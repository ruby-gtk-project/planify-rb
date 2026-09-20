# frozen_string_literal: true

module Planify
  module Services
    # core/Services/Todoist. The v1 sync API: one POST returns everything that
    # changed since the stored sync token, and the same endpoint takes a batch
    # of queued commands back.
    module Todoist
      SYNC_URL = "https://api.todoist.com/api/v1/sync"
      TOKEN_URL = "https://todoist.com/oauth/access_token"
      AUTHORIZE_URL = "https://todoist.com/oauth/authorize"

      CLIENT_ID = "b0dd7d3714314b1dbbdab9ee03b6b432"
      CLIENT_SECRET = "a86dfeb12139459da3e5e2a8c197c678"
      SCOPE = "data:read_write,data:delete,project:delete"
      REDIRECT_URI = "planify://auth"

      RESOURCE_TYPES = %w[user projects sections items labels reminders].freeze

      module_function

      def store = Store.instance

      # --- auth -----------------------------------------------------------

      def authorize_url(state)
        "#{AUTHORIZE_URL}?client_id=#{CLIENT_ID}&scope=#{CGI.escape(SCOPE)}&state=#{state}"
      end

      # The redirect lands on planify://auth?code=...&state=...; the code is
      # exchanged for a token, and a mismatched state is a rejected callback.
      def exchange_code(url, expected_state, &callback)
        parse_callback(url).then do |params|
          if params["state"] != expected_state
            callback.call(
              Http::Response.new(
                0,
                nil,
                {},
                _("The authentication reply did not match this request."),
              ),
            )
          elsif params["code"].to_s.empty?
            callback.call(
              Http::Response.new(
                0,
                nil,
                {},
                _("Todoist did not return an authorization code."),
              ),
            )
          else
            request_token(params["code"], &callback)
          end
        end
      end

      def parse_callback(url)
        begin
          URI.parse(url).query.to_s.then { |query| CGI.parse(query).transform_values(&:first) }
        rescue URI::Error
          {}
        end
      end

      def request_token(code, &callback)
        Http.async(
          "POST",
          "#{TOKEN_URL}?client_id=#{CLIENT_ID}&client_secret=#{CLIENT_SECRET}&code=#{code}",
          headers: { "Content-Type" => "application/x-www-form-urlencoded" },
          &callback
        )
      end

      # Personal API tokens skip OAuth entirely.
      def login_with_token(token, &callback)
        Http.async(
          "POST",
          SYNC_URL,
          headers: {
            "Authorization" => "Bearer #{token}",
            "Content-Type"  => "application/x-www-form-urlencoded",
          },
          body:    URI.encode_www_form(
            "sync_token"     => "*",
            "resource_types" => JSON.generate(["user"]),
          ),
          &callback
        )
      end

      # A fresh source starts with sync_token "*", which asks for everything.
      def create_source(token, user)
        Source.new(
          source_type:  "todoist",
          display_name: user["full_name"].to_s,
          sync_server:  1,
        ).tap do |source|
          source.merge_payload(
            "access_token"    => token,
            "sync_token"      => "*",
            "user_id"         => user["id"].to_s,
            "user_email"      => user["email"].to_s,
            "user_name"       => user["full_name"].to_s,
            "user_image_id"   => user["image_id"].to_s,
            "user_avatar"     => user["avatar_medium"].to_s,
            "user_is_premium" => user["is_premium"] == true,
            "api_version"     => "v1",
          )
          store.insert_source(source)
        end
      end

      # --- sync -----------------------------------------------------------

      def sync(source, &done)
        if source["access_token"].to_s.empty?
          done&.call(false, _("This account is not signed in."))
        elsif source.needs_migration?
          store.emit(:sync_failed, source, _("This account must be reconnected: Todoist has retired the API version it was set up with."))
          done&.call(false, _("Reconnect this account to continue syncing."))
        else
          start_sync(source, &done)
        end
      end

      def start_sync(source, &done)
        store.emit(:sync_started, source)
        LogService.info("Todoist", "sync started for #{source.display_name}")

        Http.async(
          "POST",
          SYNC_URL,
          headers: {
            "Authorization" => "Bearer #{source['access_token']}",
            "Content-Type"  => "application/x-www-form-urlencoded",
          },
          body:    URI.encode_www_form(
            "sync_token"     => source["sync_token"],
            "resource_types" => JSON.generate(RESOURCE_TYPES),
          ),
        ) do |response|
          handle_sync(source, response, &done)
        end
      end

      def handle_sync(source, response, &done)
        if !response.ok?
          fail_sync(source, response.message, &done)
        elsif response.json.key?("error")
          fail_sync(source, response.json["error"].to_s, &done)
        else
          apply(source, response.json)
          flush_queue(source) { finish_sync(source, &done) }
        end
      end

      def fail_sync(source, message, &done)
        LogService.error("Todoist", "sync failed: #{message}")
        store.emit(:sync_failed, source, message)
        done&.call(false, message)
      end

      def finish_sync(source, &done)
        source.last_sync = Time.now.iso8601
        store.update_source(source)
        store.emit(:sync_finished, source)
        LogService.info("Todoist", "sync finished for #{source.display_name}")
        done&.call(true, nil)
      end

      # Order matters: labels and projects first, because sections and items
      # reference them.
      def apply(source, payload)
        source["sync_token"] = payload["sync_token"].to_s
        apply_user(source, payload["user"])
        payload.fetch("labels", []).each { |node| apply_label(source, node) }
        payload.fetch("projects", []).each { |node| apply_project(source, node) }
        payload.fetch("sections", []).each { |node| apply_section(source, node) }
        payload.fetch("items", []).each { |node| apply_item(source, node) }
        payload.fetch("reminders", []).each { |node| apply_reminder(source, node) }
        store.update_source(source)
      end

      def apply_user(source, user)
        unless user.nil?
          source.merge_payload(
            "user_id"         => user["id"].to_s,
            "user_email"      => user["email"].to_s,
            "user_name"       => user["full_name"].to_s,
            "user_image_id"   => user["image_id"].to_s,
            "user_is_premium" => user["is_premium"] == true,
          )
          source.display_name = user["full_name"].to_s
        end
      end

      def apply_label(source, node)
        store.label(node["id"].to_s).then do |label|
          if label.nil?
            unless node["is_deleted"]
              store.insert_label(label_from(node, source))
            end
          elsif node["is_deleted"]
            store.delete_label(label)
          else
            store.update_label(assign_label(label, node))
          end
        end
      end

      def label_from(node, source)
        assign_label(Label.new(id: node["id"].to_s, source_id: source.id), node).tap do |label|
          label.backend_type = "todoist"
        end
      end

      def assign_label(label, node)
        label.tap do |record|
          record.name = node["name"].to_s
          record.color = node["color"].to_s
          record.item_order = node["item_order"].to_i
          record.is_favorite = Record.flag(node["is_favorite"])
        end
      end

      def apply_project(source, node)
        store.project(node["id"].to_s).then do |project|
          if project.nil?
            unless node["is_deleted"]
              store.insert_project(project_from(node, source))
            end
          elsif node["is_deleted"]
            store.delete_project(project)
          else
            store.update_project(assign_project(project, node))
          end
        end
      end

      def project_from(node, source)
        assign_project(Project.new(id: node["id"].to_s, source_id: source.id), node).tap do |project|
          project.backend_type = "todoist"
        end
      end

      def assign_project(project, node)
        project.tap do |record|
          record.name = node["name"].to_s
          record.color = node["color"].to_s
          record.is_favorite = Record.flag(node["is_favorite"])
          record.is_archived = Record.flag(node["is_archived"])
          record.inbox_project = Record.flag(node["inbox_project"])
          record.child_order = node["child_order"].to_i
          record.parent_id = node["parent_id"].to_s
          record.shared = Record.flag(node["shared"])
          record.view_style = node["view_style"].to_s.then { |v| v.empty? ? "list" : v }
          record.description = node["description"].to_s
        end
      end

      def apply_section(source, node)
        store.section(node["id"].to_s).then do |section|
          if section.nil?
            unless node["is_deleted"]
              store.insert_section(section_from(node))
            end
          elsif node["is_deleted"]
            store.delete_section(section)
          else
            store.update_section(assign_section(section, node))
          end
        end
      end

      def section_from(node) = assign_section(Section.new(id: node["id"].to_s), node)

      def assign_section(section, node)
        section.tap do |record|
          record.name = node["name"].to_s
          record.project_id = node["project_id"].to_s
          record.section_order = node["section_order"].to_i
          record.collapsed = Record.flag(node["collapsed"])
          record.is_archived = Record.flag(node["is_archived"])
          record.archived_at = node["archived_at"].to_s
          record.added_at = node["added_at"].to_s
        end
      end

      # A task still being written locally is skipped, so an in-flight edit is
      # not overwritten by the state the server had before it.
      def apply_item(_source, node)
        store.item(node["id"].to_s).then do |item|
          if item.nil?
            unless node["is_deleted"]
              store.insert_item(item_from(node))
            end
          elsif node["is_deleted"]
            store.delete_item(item)
          elsif !store.pending_write?(item.id)
            store.update_item(assign_item(item, node))
          end
        end
      end

      def item_from(node) = assign_item(Item.new(id: node["id"].to_s), node)

      def assign_item(item, node)
        item.tap do |record|
          record.content = node["content"].to_s
          record.description = node["description"].to_s
          record.project_id = node["project_id"].to_s
          record.section_id = node["section_id"].to_s
          record.parent_id = node["parent_id"].to_s
          record.priority = priority_from(node["priority"])
          record.child_order = node["child_order"].to_i
          record.checked = Record.flag(node["checked"])
          record.completed_at = node["completed_at"].to_s
          record.added_at = node["added_at"].to_s
          record.due = due_from(node["due"])
          record.deadline_date = deadline_from(node["deadline"])
          record.label_ids = label_ids_from(node["labels"])
        end
      end

      # Todoist treats 0 and 1 alike as "no priority"; locally that is P4.
      def priority_from(value)
        value.to_i.then { |priority| priority.zero? ? Item::PRIORITY_4 : priority }
      end

      # Todoist sends labels by name; locally they are referenced by id, and a
      # name that has not been seen becomes a label.
      def label_ids_from(names)
        Array(names).map do |name|
          store.label_by_name(name.to_s).then do |label|
            if label.nil?
              store.insert_label(Label.new(name: name.to_s, color: Palette.random)).id
            else
              label.id
            end
          end
        end
      end

      def due_from(due)
        if due.nil?
          ""
        else
          JSON.generate(
            "date"                => due["date"].to_s,
            "recurrence_string"   => due["string"].to_s,
            "time_zone"           => due["timezone"].to_s,
            "is_recurring"        => due["is_recurring"] == true,
            "recurrency_type"     => Recurrency.parse_todoist(due),
            "recurrency_interval" => Recurrency.interval_todoist(due),
          )
        end
      end

      def deadline_from(deadline)
        if deadline.nil?
          ""
        else
          deadline["date"].to_s
        end
      end

      def apply_reminder(_source, node)
        store.reminder(node["id"].to_s).then do |reminder|
          if reminder.nil?
            unless node["is_deleted"]
              store.insert_reminder(reminder_from(node))
            end
          elsif node["is_deleted"]
            store.delete_reminder(reminder)
          end
        end
      end

      def reminder_from(node)
        Reminder.new(
          id:        node["id"].to_s,
          item_id:   node["item_id"].to_s,
          service:   "todoist",
          type:      node["type"].to_s.empty? ? "absolute" : node["type"].to_s,
          due:       node["due"].nil? ? "" : JSON.generate("date" => node["due"]["date"].to_s),
          mm_offset: node["minute_offset"].to_i,
        )
      end

      # --- queue ----------------------------------------------------------

      # One POST carries every queued command; the response reports per uuid,
      # so a command that failed stays queued and is retried next sync.
      def flush_queue(source, &done)
        SyncQueue.all(source.id).then do |entries|
          if entries.empty?
            done&.call
          else
            post_commands(source, entries, &done)
          end
        end
      end

      def post_commands(source, entries, &done)
        LogService.info("Todoist", "flushing #{entries.size} queued commands")

        Http.async(
          "POST",
          SYNC_URL,
          headers: {
            "Authorization" => "Bearer #{source['access_token']}",
            "Content-Type"  => "application/json",
          },
          body:    JSON.generate(
            "sync_token" => source["sync_token"],
            "commands"   => entries.map { |entry| command_for(entry) },
          ),
        ) do |response|
          settle_queue(source, entries, response)
          done&.call
        end
      end

      def command_for(entry)
        {
          "type" => entry.query,
          "uuid" => entry.uuid,
          "args" => entry.arguments,
        }.tap do |command|
          unless entry.temp_id.to_s.empty?
            command["temp_id"] = entry.temp_id
          end
        end
      end

      def settle_queue(source, entries, response)
        if response.ok?
          response.json.then do |payload|
            source["sync_token"] = payload["sync_token"].to_s
            store.update_source(source)
            entries.each { |entry| settle_entry(entry, payload) }
          end
        else
          LogService.warn("Todoist", "queue flush failed: #{response.message}")
        end
      end

      # "ok" for a command means it landed; anything else is an error object
      # and the entry is kept for the next attempt.
      def settle_entry(entry, payload)
        payload.dig("sync_status", entry.uuid).then do |status|
          if status == "ok"
            adopt_server_id(entry, payload)
            SyncQueue.remove(entry)
          else
            LogService.warn("Todoist", "#{entry.query} failed: #{status.inspect}")
          end
        end
      end

      ADOPTERS = {
        "project_add" => :update_project_id,
        "section_add" => :update_section_id,
        "item_add"    => :update_item_id,
      }.freeze

      # A locally created object carries a temporary id until the server
      # answers with the real one; every row that references it moves too.
      def adopt_server_id(entry, payload)
        ADOPTERS.fetch(entry.query, nil).then do |method|
          unless method.nil?
            payload.dig("temp_id_mapping", entry.temp_id).then do |server_id|
              unless server_id.nil?
                store.public_send(method, entry.target_id, server_id.to_s)
                SyncQueue.remove_temp_id(entry.target_id)
              end
            end
          end
        end
      end

      # --- outgoing commands ----------------------------------------------

      def item_args(item)
        {
          "content"     => item.content.to_s,
          "description" => item.description.to_s,
          "child_order" => item.child_order.to_i,
          "priority"    => item.priority.to_i.zero? ? Item::PRIORITY_4 : item.priority.to_i,
          "due"         => item.has_due? ? due_args(item) : nil,
          "deadline"    => item.deadline.nil? ? nil : { "date" => item.deadline_date.to_s },
          "labels"      => item.label_objects.map(&:name),
        }
      end

      def due_args(item)
        {
          "date"   => item.due_hash["date"].to_s,
          "string" => Recurrency.to_todoist_string(item),
        }
      end

      def project_args(project)
        {
          "name"        => project.name.to_s,
          "color"       => project.color.to_s,
          "is_favorite" => project.favorite?,
          "view_style"  => project.view_style.to_s,
        }.tap do |args|
          unless project.parent_id.to_s.empty?
            args["parent_id"] = project.parent_id.to_s
          end
        end
      end

      def section_args(section)
        {
          "name"       => section.name.to_s,
          "project_id" => section.project_id.to_s,
        }
      end

      def label_args(label)
        {
          "name"        => label.name.to_s,
          "color"       => label.color.to_s,
          "is_favorite" => label.favorite?,
        }
      end
    end
  end
end
