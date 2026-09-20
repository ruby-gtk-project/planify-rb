# frozen_string_literal: true

module Planify
  module Dialogs
    # src/Dialogs/Preferences: General, Appearance, Backups. The Accounts page
    # is not ported — see the Sync note in README.
    class Preferences
      def present(parent)
        dialog.tap do |d|
          d.add(general_page)
          d.add(appearance_page)
          d.add(backups_page)

          general_page.tap do |page|
            page.add(home_group)
            page.add(tasks_group)

            home_group.add(home_view_row)
            home_group.add(task_count_row)

            tasks_group.tap do |group|
              group.add(new_task_position_row)
              group.add(default_priority_row)
              group.add(description_preview_row)
              group.add(underline_completed_row)
              group.add(smart_dates_row)
              group.add(open_sidebar_row)
            end
          end

          appearance_page.tap do |page|
            page.add(theme_group)
            theme_group.add(system_appearance_row)
            theme_group.add(dark_mode_row)
            theme_group.add(details_sidebar_row)
          end

          backups_page.tap do |page|
            page.add(backup_group)
            backup_group.add(export_row)
            backup_group.add(import_row)
            backup_group.add(tutorial_row)
          end

          bind
          d.present(parent)
        end
      end

      def store = Store.instance

      HOME_VIEWS = %w[inbox today scheduled labels pinboard].freeze

      def bind
        home_view_row.tap do |row|
          row.model = Gtk::StringList.new(
            [_("Inbox"), _("Today"), _("Scheduled"), _("Labels"), _("Pinboard")],
          )
          row.selected = HOME_VIEWS.index(Settings.home_view) || 0
          row.signal_connect("notify::selected") do
            Settings.home_view = HOME_VIEWS[row.selected]
          end
        end

        new_task_position_row.tap do |row|
          row.model = Gtk::StringList.new([_("Top of the list"), _("Bottom of the list")])
          row.selected = Settings.get_enum("new-tasks-position")
          row.signal_connect("notify::selected") do
            Settings.set_enum("new-tasks-position", row.selected)
          end
        end

        default_priority_row.tap do |row|
          row.model = Gtk::StringList.new(
            [_("Priority 1"), _("Priority 2"), _("Priority 3"), _("None")],
          )
          row.selected = Settings.get_enum("default-priority")
          row.signal_connect("notify::selected") do
            Settings.set_enum("default-priority", row.selected)
          end
        end

        BOOLEAN_ROWS.each do |key, method|
          public_send(method).tap do |row|
            row.active = Settings.get_boolean(key)
            row.signal_connect("notify::active") do
              Settings.set_boolean(key, row.active?)
              Theme.update
            end
          end
        end

        export_row.signal_connect("activated") { export_backup }
        import_row.signal_connect("activated") { import_backup }
        tutorial_row.signal_connect("activated") { recreate_tutorial }
      end

      BOOLEAN_ROWS = {
        "show-tasks-count"            => :task_count_row,
        "description-preview"         => :description_preview_row,
        "underline-completed-tasks"   => :underline_completed_row,
        "smart-date-recognition"      => :smart_dates_row,
        "open-task-sidebar"           => :open_sidebar_row,
        "system-appearance"           => :system_appearance_row,
        "dark-mode"                   => :dark_mode_row,
        "always-show-details-sidebar" => :details_sidebar_row,
      }.freeze

      # --- backups ---------------------------------------------------------

      # The Vala build writes a JSON backup of every object; same shape here,
      # so a backup taken by either build restores in the other.
      def export_backup
        FileUtils.mkdir_p(Paths.backups)
        File.join(Paths.backups, "planify-#{Time.now.strftime('%Y-%m-%d-%H%M%S')}.json")
            .tap do |path|
          File.write(path, JSON.pretty_generate(backup_payload))
          dialog.add_toast(Adwaita::Toast.new(_("Backup saved to %s") % path))
        end
      end

      def backup_payload
        {
          "version"     => VERSION,
          "date"        => Time.now.iso8601,
          "projects"    => store.projects.map(&:to_row),
          "sections"    => store.sections.map(&:to_row),
          "items"       => store.items.map(&:to_row),
          "labels"      => store.labels.map(&:to_row),
          "reminders"   => store.reminders.map(&:to_row),
          "attachments" => store.attachments.map(&:to_row),
        }
      end

      def import_backup
        Gtk::FileDialog.new.tap do |chooser|
          chooser.title = _("Import Backup")
          chooser.open(nil, nil) do |_, result|
            begin
              restore(chooser.open_finish(result).path)
            rescue StandardError => error
              dialog.add_toast(Adwaita::Toast.new(_("Import failed: %s") % error.message))
            end
          end
        end
      end

      RESTORE_ORDER = {
        "labels"      => Label,
        "projects"    => Project,
        "sections"    => Section,
        "items"       => Item,
        "reminders"   => Reminder,
        "attachments" => Attachment,
      }.freeze

      def restore(path)
        JSON.parse(File.read(path)).then do |payload|
          RESTORE_ORDER.each do |key, model|
            payload.fetch(key, []).each do |row|
              store.database.insert(model.from_row(row))
            end
          end

          store.load
          dialog.add_toast(Adwaita::Toast.new(_("Backup imported. Restart Planify to see it.")))
        end
      end

      def recreate_tutorial
        Seed.create_tutorial(store)
        dialog.add_toast(Adwaita::Toast.new(_("“Meet Planify” recreated")))
      end

      # --- widgets ---------------------------------------------------------

      def dialog
        @dialog ||= Adwaita::PreferencesDialog.new.tap do |d|
          d.title = _("Preferences")
        end
      end

      def general_page
        @general_page ||= Adwaita::PreferencesPage.new.tap do |page|
          page.title = _("General")
          page.icon_name = "settings-symbolic"
        end
      end

      def home_group
        @home_group ||= Adwaita::PreferencesGroup.new.tap do |group|
          group.title = _("Home")
        end
      end

      def home_view_row
        @home_view_row ||= Adwaita::ComboRow.new.tap do |row|
          row.title = _("Home Page")
          row.subtitle = _("The view Planify opens on")
        end
      end

      def task_count_row
        @task_count_row ||= Adwaita::SwitchRow.new.tap do |row|
          row.title = _("Show Task Count")
        end
      end

      def tasks_group
        @tasks_group ||= Adwaita::PreferencesGroup.new.tap do |group|
          group.title = _("Tasks")
        end
      end

      def new_task_position_row
        @new_task_position_row ||= Adwaita::ComboRow.new.tap do |row|
          row.title = _("New Tasks")
        end
      end

      def default_priority_row
        @default_priority_row ||= Adwaita::ComboRow.new.tap do |row|
          row.title = _("Default Priority")
        end
      end

      def description_preview_row
        @description_preview_row ||= Adwaita::SwitchRow.new.tap do |row|
          row.title = _("Description Preview")
          row.subtitle = _("Show the first line of a task's description in the list")
        end
      end

      def underline_completed_row
        @underline_completed_row ||= Adwaita::SwitchRow.new.tap do |row|
          row.title = _("Strike Through Completed Tasks")
        end
      end

      def smart_dates_row
        @smart_dates_row ||= Adwaita::SwitchRow.new.tap do |row|
          row.title = _("Smart Date Recognition")
          row.subtitle = _("Read dates, priorities and labels out of what you type")
        end
      end

      def open_sidebar_row
        @open_sidebar_row ||= Adwaita::SwitchRow.new.tap do |row|
          row.title = _("Open Task Details on Click")
        end
      end

      def appearance_page
        @appearance_page ||= Adwaita::PreferencesPage.new.tap do |page|
          page.title = _("Appearance")
          page.icon_name = "color-symbolic"
        end
      end

      def theme_group
        @theme_group ||= Adwaita::PreferencesGroup.new.tap do |group|
          group.title = _("Theme")
        end
      end

      def system_appearance_row
        @system_appearance_row ||= Adwaita::SwitchRow.new.tap do |row|
          row.title = _("Follow System Appearance")
        end
      end

      def dark_mode_row
        @dark_mode_row ||= Adwaita::SwitchRow.new.tap do |row|
          row.title = _("Dark Mode")
        end
      end

      def details_sidebar_row
        @details_sidebar_row ||= Adwaita::SwitchRow.new.tap do |row|
          row.title = _("Always Show Task Details")
        end
      end

      def backups_page
        @backups_page ||= Adwaita::PreferencesPage.new.tap do |page|
          page.title = _("Backups")
          page.icon_name = "folder-download-symbolic"
        end
      end

      def backup_group
        @backup_group ||= Adwaita::PreferencesGroup.new.tap do |group|
          group.title = _("Backups")
          group.description = _(
            "Backups are plain JSON and interchangeable with the " \
                                            "upstream Planify build.",
          )
        end
      end

      def export_row
        @export_row ||= Adwaita::ActionRow.new.tap do |row|
          row.title = _("Create Backup")
          row.activatable = true
          row.add_suffix(Gtk::Image.new(icon_name: "go-next-symbolic"))
        end
      end

      def import_row
        @import_row ||= Adwaita::ActionRow.new.tap do |row|
          row.title = _("Import Backup")
          row.activatable = true
          row.add_suffix(Gtk::Image.new(icon_name: "go-next-symbolic"))
        end
      end

      def tutorial_row
        @tutorial_row ||= Adwaita::ActionRow.new.tap do |row|
          row.title = _("Recreate “Meet Planify”")
          row.subtitle = _("Add the tutorial project back")
          row.activatable = true
          row.add_suffix(Gtk::Image.new(icon_name: "go-next-symbolic"))
        end
      end
    end
  end
end
