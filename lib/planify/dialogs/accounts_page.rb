# frozen_string_literal: true

module Planify
  module Dialogs
    module Pages
      # src/Dialogs/Preferences/Pages/Accounts. The accounts already set up,
      # and the flows that add a new one: Todoist by OAuth or by a personal
      # token, and CalDAV either as Nextcloud or as a generic server.
      class Accounts
        include Bindings

        def initialize(dialog)
          @dialog = dialog
        end

        attr_reader :dialog

        def store = Store.instance

        def page
          @page ||= Adwaita::PreferencesPage.new.tap do |p|
            p.title = _("Accounts")
            p.icon_name = "cloud-outline-thick-symbolic"
            p.add(sources_group)
            p.add(add_group)

            add_group.add(todoist_row)
            add_group.add(nextcloud_row)
            add_group.add(caldav_row)

            reload
            store.on(:source_added, owner: self) { reload }
            store.on(:source_updated, owner: self) { reload }
            store.on(:source_deleted, owner: self) { reload }
          end
        end

        def sources_group
          @sources_group ||= Adwaita::PreferencesGroup.new.tap do |g|
            g.title = _("Your Accounts")
            g.description = _(
              "Tasks in these accounts sync with their servers. " \
                                            "Everything else stays on this computer.",
            )
          end
        end

        def reload
          @rows ||= []
          @rows.each { |row| sources_group.remove(row) }

          @rows = store.synced_sources.map { |source| source_row(source) }
          @rows.each { |row| sources_group.add(row) }
          sources_group.visible = !@rows.empty?
        end

        def source_row(source)
          Adwaita::ExpanderRow.new.tap do |row|
            row.title = source.display_name.to_s
            row.subtitle = subtitle_for(source)
            row.add_prefix(Gtk::Image.new(icon_name: source.icon_name))
            row.add_row(sync_toggle(source))
            row.add_row(visible_toggle(source))
            if deck_candidate?(source)
              row.add_row(deck_toggle(source))
            end
            row.add_row(sync_now_row(source))
            row.add_row(remove_row(source))
            if source.needs_migration?
              row.add_row(migration_row(source))
            end
          end
        end

        def subtitle_for(source)
          [
            source.subheader_text,
            source.user_email,
            last_sync_text(source),
          ].reject { |value| value.to_s.empty? }.join(" · ")
        end

        def last_sync_text(source)
          Datetime.parse(source.last_sync).then do |time|
            time.nil? ? _("Never synced") : _("Synced %s") % Datetime.relative(time)
          end
        end

        def sync_toggle(source)
          Adwaita::SwitchRow.new.tap do |row|
            row.title = _("Sync Automatically")
            row.subtitle = _("Every fifteen minutes, and at startup")
            row.active = source.sync_server?
            row.signal_connect("notify::active") do
              source.sync_server = Record.flag(row.active?)
              store.update_source(source)
            end
          end
        end

        def visible_toggle(source)
          Adwaita::SwitchRow.new.tap do |row|
            row.title = _("Show in the Sidebar")
            row.active = source.visible?
            row.signal_connect("notify::active") do
              source.is_visible = Record.flag(row.active?)
              store.update_source(source)
            end
          end
        end

        # Deck only appears for a Nextcloud account whose server actually has
        # it installed, which is a question only the server can answer.
        def deck_candidate?(source)
          source.caldav? && source["caldav_type"] == "nextcloud"
        end

        def deck_toggle(source)
          Adwaita::SwitchRow.new.tap do |row|
            row.title = _("Sync Nextcloud Deck")
            row.subtitle = _("Boards become projects and cards become tasks")
            row.active = source["use_deck"] == true
            row.sensitive = false

            Services::Deck.probe(source) do |available|
              row.sensitive = available
              unless available
                row.subtitle = _("Deck is not installed on this server")
              end
            end

            row.signal_connect("notify::active") do
              source["use_deck"] = row.active?
              store.update_source(source)
            end
          end
        end

        def sync_now_row(source)
          action_row(_("Sync Now")) do
            store.sync_source(source) do |ok, message|
              unless ok
                dialog.add_toast(Adwaita::Toast.new(message.to_s))
              end
            end
          end
        end

        def remove_row(source)
          Adwaita::ActionRow.new.tap do |row|
            row.title = _("Remove Account")
            row.activatable = true
            row.add_css_class("error")
            row.add_suffix(Gtk::Image.new(icon_name: "user-trash-symbolic"))
            row.signal_connect("activated") { confirm_remove(source) }
          end
        end

        # Todoist retired the API version some accounts were set up against;
        # such an account cannot sync until it is signed in again.
        def migration_row(source)
          Adwaita::ActionRow.new.tap do |row|
            row.title = _("Reconnect Required")
            row.subtitle = _(
              "Todoist has retired the API version this account was " \
                                           "set up with. Sign in again to keep syncing.",
            )
            row.activatable = true
            row.add_suffix(Gtk::Image.new(icon_name: "dialog-warning-symbolic"))
            row.signal_connect("activated") { TodoistSetup.new(dialog, source).present }
          end
        end

        def confirm_remove(source)
          Adwaita::AlertDialog.new(
            _("Remove Account?"),
            _(
              "“%s” and everything synced from it will be removed from this computer. " \
                            "Nothing is deleted on the server.",
            ) % source.display_name,
          ).tap do |alert|
            alert.add_response("cancel", _("Cancel"))
            alert.add_response("remove", _("Remove"))
            alert.set_response_appearance("remove", Adwaita::ResponseAppearance::DESTRUCTIVE)
            alert.signal_connect("response") do |_, response|
              if response == "remove"
                store.delete_source(source)
              end
            end
            alert.present(dialog)
          end
        end

        def add_group
          @add_group ||= Adwaita::PreferencesGroup.new.tap { |g| g.title = _("Add an Account") }
        end

        def todoist_row
          @todoist_row ||= account_row(_("Todoist"), "todoist") do
            TodoistSetup.new(dialog).present
          end
        end

        def nextcloud_row
          @nextcloud_row ||= account_row(_("Nextcloud"), "nextcloud") do
            CalDAVSetup.new(dialog, "nextcloud").present
          end
        end

        def caldav_row
          @caldav_row ||= account_row(_("CalDAV"), "cloud-outline-thick-symbolic") do
            CalDAVSetup.new(dialog, "generic").present
          end
        end

        def account_row(title, icon, &on_activate)
          Adwaita::ActionRow.new.tap do |row|
            row.title = title
            row.activatable = true
            row.add_prefix(Gtk::Image.new(icon_name: icon))
            row.add_suffix(Gtk::Image.new(icon_name: "go-next-symbolic"))
            row.signal_connect("activated") { on_activate.call }
          end
        end
      end

      # src/Dialogs/Preferences/Pages/Accounts/TodoistSetup.vala.
      class TodoistSetup
        def initialize(parent, migrating = nil)
          @parent = parent
          @migrating = migrating
          @state = SecureRandom.hex(8)
        end

        attr_reader :parent, :migrating

        def store = Store.instance

        def present
          dialog.tap do |d|
            d.child = toolbar

            toolbar.tap do |view|
              view.add_top_bar(header)
              view.content = page

              header.title_widget = Adwaita::WindowTitle.new(_("Todoist"), "")

              page.add(oauth_group)
              page.add(token_group)

              oauth_group.add(open_row)
              oauth_group.add(callback_row)
              token_group.add(token_row)
              token_group.add(sign_in_row)

              open_row.signal_connect("activated") { open_browser }
              callback_row.signal_connect("apply") { finish_oauth }
              sign_in_row.signal_connect("activated") { sign_in_with_token }
            end

            d.present(parent)
          end
        end

        def open_browser
          Gtk::UriLauncher.new(Services::Todoist.authorize_url(@state)).launch(parent, nil)
        rescue StandardError => error
          toast(_("Could not open the browser: %s") % error.message)
        end

        # The redirect is planify://auth?..., which a desktop without the URI
        # handler registered cannot deliver; pasting it back is the fallback
        # upstream offers too.
        def finish_oauth
          callback_row.text.strip.then do |url|
            if url.empty?
              toast(_("Paste the address the browser was redirected to."))
            else
              spinner(true)
              Services::Todoist.exchange_code(url, @state) { |response| handle_token(response) }
            end
          end
        end

        def handle_token(response)
          if !response.ok?
            spinner(false)
            toast(response.message.to_s)
          else
            response.json["access_token"].to_s.then do |token|
              if token.empty?
                spinner(false)
                toast(_("Todoist did not return an access token."))
              else
                verify(token)
              end
            end
          end
        end

        def sign_in_with_token
          token_row.text.strip.then do |token|
            if token.empty?
              toast(_("Enter your personal API token."))
            else
              spinner(true)
              verify(token)
            end
          end
        end

        # The token is only stored once it has actually fetched the account,
        # so a mistyped one leaves nothing behind.
        def verify(token)
          Services::Todoist.login_with_token(token) do |response|
            spinner(false)

            if !response.ok? || response.json.key?("error")
              toast(error_text(response))
            else
              adopt(token, response.json["user"] || {})
            end
          end
        end

        def error_text(response)
          if response.json["error"]
            response.json["error"].to_s
          else
            response.message.to_s
          end
        end

        def adopt(token, user)
          if migrating.nil?
            Services::Todoist.create_source(token, user).then { |source| start_sync(source) }
          else
            migrating.merge_payload(
              "access_token" => token,
              "api_version"  => "v1",
              "sync_token"   => "*",
            )
            store.update_source(migrating)
            start_sync(migrating)
          end
        end

        def start_sync(source)
          dialog.close
          store.sync_source(source) { |_, _| nil }
        end

        def spinner(active)
          sign_in_row.sensitive = !active
          open_row.sensitive = !active
        end

        def toast(message)
          parent.add_toast(Adwaita::Toast.new(message.to_s))
        rescue StandardError
          Services::LogService.warn("Todoist", message.to_s)
        end

        def dialog
          @dialog ||= Adwaita::Dialog.new.tap do |d|
            d.title = _("Todoist")
            d.content_width = 480
          end
        end

        def toolbar = @toolbar ||= Adwaita::ToolbarView.new

        def header = @header ||= Adwaita::HeaderBar.new

        def page = @page ||= Adwaita::PreferencesPage.new

        def oauth_group
          @oauth_group ||= Adwaita::PreferencesGroup.new.tap do |g|
            g.title = _("Sign In")
            g.description = _(
              "Planify opens Todoist in your browser. When it " \
                                            "redirects back, paste the address here.",
            )
          end
        end

        def open_row
          @open_row ||= Adwaita::ActionRow.new.tap do |row|
            row.title = _("Open Todoist")
            row.activatable = true
            row.add_suffix(Gtk::Image.new(icon_name: "external-link-symbolic"))
          end
        end

        def callback_row
          @callback_row ||= Adwaita::EntryRow.new.tap do |row|
            row.title = _("Redirect Address")
            row.show_apply_button = true
          end
        end

        def token_group
          @token_group ||= Adwaita::PreferencesGroup.new.tap do |g|
            g.title = _("Or Use a Personal Token")
            g.description = _("Todoist → Settings → Integrations → Developer.")
          end
        end

        def token_row
          @token_row ||= Adwaita::PasswordEntryRow.new.tap do |row|
            row.title = _("API Token")
          end
        end

        def sign_in_row
          @sign_in_row ||= Adwaita::ActionRow.new.tap do |row|
            row.title = _("Sign In With Token")
            row.activatable = true
            row.add_suffix(Gtk::Image.new(icon_name: "go-next-symbolic"))
          end
        end
      end

      # src/Dialogs/Preferences/Pages/Accounts/CalDAVSetup.vala and
      # NextcloudSetup.vala — the same form, differing only in its wording and
      # in the URL it suggests.
      class CalDAVSetup
        def initialize(parent, kind)
          @parent = parent
          @kind = kind
        end

        attr_reader :parent, :kind

        def store = Store.instance

        def nextcloud? = kind == "nextcloud"

        def present
          dialog.tap do |d|
            d.child = toolbar

            toolbar.tap do |view|
              view.add_top_bar(header)
              view.content = page

              header.title_widget = Adwaita::WindowTitle.new(title, "")

              page.add(server_group)
              page.add(options_group)
              page.add(action_group)

              server_group.add(url_row)
              server_group.add(username_row)
              server_group.add(password_row)

              options_group.add(ignore_ssl_row)

              action_group.add(connect_row)

              connect_row.signal_connect("activated") { connect }
            end

            d.present(parent)
          end
        end

        def title
          nextcloud? ? _("Nextcloud") : _("CalDAV")
        end

        def connect
          if url_row.text.strip.empty? || username_row.text.strip.empty?
            show_error(_("Enter the server address and your username."))
          else
            connecting(true)
            Services::CalDAV.add_account(build_source) { |ok, error| settle(ok, error) }
          end
        end

        def build_source
          Services::CalDAV.build_source(
            normalize(url_row.text.strip),
            username_row.text.strip,
            password_row.text,
            kind,
            ignore_ssl_row.active?,
          )
        end

        # A bare host is the commonest thing typed; https is assumed because
        # sending a password over http is not something to do silently.
        def normalize(url)
          if url.start_with?("http://", "https://")
            url
          else
            "https://#{url}"
          end
        end

        def settle(ok, error)
          connecting(false)

          if ok
            dialog.close
          else
            show_error(error.to_s)
          end
        end

        def connecting(active)
          connect_row.sensitive = !active
          spinner.visible = active
          active ? spinner.start : spinner.stop
        end

        def show_error(message)
          error_label.label = message
          error_label.visible = true
        end

        def dialog
          @dialog ||= Adwaita::Dialog.new.tap do |d|
            d.title = title
            d.content_width = 480
          end
        end

        def toolbar = @toolbar ||= Adwaita::ToolbarView.new

        def header = @header ||= Adwaita::HeaderBar.new

        def page = @page ||= Adwaita::PreferencesPage.new

        def server_group
          @server_group ||= Adwaita::PreferencesGroup.new.tap do |g|
            g.title = _("Server")
            g.description = server_description
          end
        end

        def server_description
          if nextcloud?
            _(
              "Your Nextcloud address, and an app password rather than your account " \
                            "password if you use two-factor authentication.",
            )
          else
            _("The address of your CalDAV server.")
          end
        end

        def url_row
          @url_row ||= Adwaita::EntryRow.new.tap do |row|
            row.title = _("Server Address")
            if nextcloud?
              row.text = "https://"
            else
              row.text = ""
            end
          end
        end

        def username_row
          @username_row ||= Adwaita::EntryRow.new.tap { |row| row.title = _("Username") }
        end

        def password_row
          @password_row ||= Adwaita::PasswordEntryRow.new.tap do |row|
            row.title = _("Password")
          end
        end

        def options_group
          @options_group ||= Adwaita::PreferencesGroup.new
        end

        # A self-signed certificate is common on a home server, and refusing
        # one with no way through would simply block those users.
        def ignore_ssl_row
          @ignore_ssl_row ||= Adwaita::SwitchRow.new.tap do |row|
            row.title = _("Accept Untrusted Certificates")
            row.subtitle = _("Only for a server whose certificate you trust yourself")
          end
        end

        def action_group
          @action_group ||= Adwaita::PreferencesGroup.new.tap do |g|
            g.add(error_label)
          end
        end

        def connect_row
          @connect_row ||= Adwaita::ActionRow.new.tap do |row|
            row.title = _("Connect")
            row.activatable = true
            row.add_suffix(spinner)
            row.add_suffix(Gtk::Image.new(icon_name: "go-next-symbolic"))
          end
        end

        def spinner
          @spinner ||= Gtk::Spinner.new.tap do |s|
            s.visible = false
            s.valign = :center
          end
        end

        def error_label
          @error_label ||= Gtk::Label.new("").tap do |label|
            label.add_css_class("error")
            label.wrap = true
            label.visible = false
            label.margin_top = 6
          end
        end
      end
    end
  end
end
