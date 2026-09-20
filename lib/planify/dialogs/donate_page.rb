# frozen_string_literal: true

module Planify
  module Dialogs
    module Pages
      # src/Dialogs/Preferences/Pages/Donate.vala, plus the diagnostics that
      # make a bug report useful: the log tail and the translation status.
      class Donate
        include Bindings

        LINKS = [
          {
            title: -> { _("Support Planify") },
            icon:  "heart-filled-symbolic",
            url:   "https://github.com/sponsors/alainm23",
          },
          {
            title: -> { _("Report an Issue") },
            icon:  "chat-bubble-text-symbolic",
            url:   Planify::ISSUES,
          },
          {
            title: -> { _("Translate Planify") },
            icon:  "language-symbolic",
            url:   "https://hosted.weblate.org/projects/planify/",
          },
          {
            title: -> { _("Source Code") },
            icon:  "code-symbolic",
            url:   Planify::WEBSITE,
          },
        ].freeze

        def initialize(dialog)
          @dialog = dialog
        end

        attr_reader :dialog

        def page
          @page ||= Adwaita::PreferencesPage.new.tap do |p|
            p.title = _("About")
            p.icon_name = "heart-filled-symbolic"
            p.add(links_group)
            p.add(diagnostics_group)

            LINKS.each { |link| links_group.add(link_row(link)) }

            diagnostics_group.add(version_row)
            diagnostics_group.add(database_row)
            diagnostics_group.add(log_row)
          end
        end

        def links_group
          @links_group ||= Adwaita::PreferencesGroup.new.tap do |g|
            g.title = _("Planify")
            g.description = _("Planify is free software, made by volunteers.")
          end
        end

        def link_row(link)
          Adwaita::ActionRow.new.tap do |row|
            row.title = link[:title].call
            row.activatable = true
            row.add_prefix(Gtk::Image.new(icon_name: link[:icon]))
            row.add_suffix(Gtk::Image.new(icon_name: "external-link-symbolic"))
            row.signal_connect("activated") { open(link[:url]) }
          end
        end

        def open(url)
          Gtk::UriLauncher.new(url).launch(nil, nil)
        rescue StandardError => error
          Services::LogService.warn("Donate", "could not open #{url}: #{error.message}")
        end

        def diagnostics_group
          @diagnostics_group ||= Adwaita::PreferencesGroup.new.tap do |g|
            g.title = _("Diagnostics")
          end
        end

        def version_row
          @version_row ||= Adwaita::ActionRow.new.tap do |row|
            row.title = _("Version")
            row.subtitle = Planify::VERSION
          end
        end

        def database_row
          @database_row ||= Adwaita::ActionRow.new.tap do |row|
            row.title = _("Database")
            row.subtitle = Store.instance.database.path.to_s
            row.activatable = true
            row.add_suffix(Gtk::Image.new(icon_name: "clipboard-symbolic"))
            row.signal_connect("activated") { copy(Store.instance.database.path.to_s) }
          end
        end

        # A log tail on the clipboard is what makes an issue report actionable.
        def log_row
          @log_row ||= action_row(
            _("Copy Recent Log"),
            _("The last hundred lines, for a bug report"),
          ) { copy(Services::LogService.tail(100)) }
        end

        def copy(text)
          Gdk::Display.default.clipboard.set(text.to_s)
          dialog.add_toast(Adwaita::Toast.new(_("Copied")))
        end
      end
    end
  end
end
