# frozen_string_literal: true

module Planify
  module Dialogs
    # src/Dialogs/Preferences/Pages. Each page is a class with a `page` that
    # returns an Adwaita::PreferencesPage, so PreferencesDialog only has to
    # assemble them.
    module Pages
      # The switch and combo rows every page builds, bound to GSettings so a
      # change made anywhere is seen everywhere.
      module Bindings
        def bind_switch(row, key)
          row.tap do |r|
            r.active = Settings.get_boolean(key)
            r.signal_connect("notify::active") { Settings.set_boolean(key, r.active?) }
          end
        end

        def bind_enum(row, key, titles)
          row.tap do |r|
            r.model = Gtk::StringList.new(titles)
            r.selected = Settings.get_enum(key)
            r.signal_connect("notify::selected") { Settings.set_enum(key, r.selected) }
          end
        end

        def bind_string_choice(row, key, values, titles)
          row.tap do |r|
            r.model = Gtk::StringList.new(titles)
            r.selected = values.index(Settings.get_string(key)) || 0
            r.signal_connect("notify::selected") { Settings.set_string(key, values[r.selected]) }
          end
        end

        def bind_spin(row, key)
          row.tap do |r|
            r.value = Settings.get_int(key)
            r.signal_connect("notify::value") { Settings.set_int(key, r.value.to_i) }
          end
        end

        def spin_row(title, subtitle, upper)
          Adwaita::SpinRow.new(
            Gtk::Adjustment.new(
              0,
              0,
              upper,
              1,
              5,
              0,
            ),
            1,
            0,
          ).tap do |row|
            row.title = title
            row.subtitle = subtitle
          end
        end

        def switch_row(title, subtitle = nil)
          Adwaita::SwitchRow.new.tap do |row|
            row.title = title
            row.subtitle = subtitle.to_s
          end
        end

        def combo_row(title, subtitle = nil)
          Adwaita::ComboRow.new.tap do |row|
            row.title = title
            row.subtitle = subtitle.to_s
          end
        end

        def action_row(title, subtitle = nil, &on_activate)
          Adwaita::ActionRow.new.tap do |row|
            row.title = title
            row.subtitle = subtitle.to_s
            row.activatable = true
            row.add_suffix(Gtk::Image.new(icon_name: "go-next-symbolic"))
            row.signal_connect("activated") { on_activate&.call }
          end
        end
      end

      # src/Dialogs/Preferences/Pages/General.vala plus HomeView and
      # TaskSetting, which are one page's worth of rows between them.
      class General
        include Bindings

        HOME_VIEWS = %w[inbox today scheduled labels pinboard].freeze

        def initialize(dialog)
          @dialog = dialog
        end

        attr_reader :dialog

        def page
          @page ||= Adwaita::PreferencesPage.new.tap do |p|
            p.title = _("General")
            p.icon_name = "settings-symbolic"
            p.add(home_group)
            p.add(task_group)
            p.add(datetime_group)
            p.add(quick_add_group)

            home_group.add(home_view_row)
            home_group.add(task_count_row)
            home_group.add(filters_list_row)

            task_group.add(new_task_row)
            task_group.add(default_priority_row)
            task_group.add(complete_task_row)
            task_group.add(description_preview_row)
            task_group.add(underline_row)
            task_group.add(open_sidebar_row)
            task_group.add(details_sidebar_row)
            task_group.add(markdown_row)
            task_group.add(subtasks_row)
            task_group.add(tone_row)

            datetime_group.add(clock_format_row)
            datetime_group.add(start_week_row)
            datetime_group.add(smart_dates_row)

            quick_add_group.add(save_project_row)
            quick_add_group.add(create_more_row)
            quick_add_group.add(keep_properties_row)
            quick_add_group.add(close_focus_row)
          end
        end

        def home_group
          @home_group ||= Adwaita::PreferencesGroup.new.tap { |g| g.title = _("Home") }
        end

        def home_view_row
          @home_view_row ||= bind_string_choice(
            combo_row(_("Home Page"), _("The view Planify opens on")),
            "home-view",
            HOME_VIEWS,
            [_("Inbox"), _("Today"), _("Scheduled"), _("Labels"), _("Pinboard")],
          )
        end

        def task_count_row
          @task_count_row ||= bind_switch(switch_row(_("Show Task Count")), "show-tasks-count")
        end

        def filters_list_row
          @filters_list_row ||= bind_switch(
            switch_row(_("Filters as a List"), _("Show the filters as rows instead of tiles")),
            "filters-list-view",
          )
        end

        def task_group
          @task_group ||= Adwaita::PreferencesGroup.new.tap { |g| g.title = _("Tasks") }
        end

        def new_task_row
          @new_task_row ||= bind_enum(
            combo_row(_("New Tasks")),
            "new-tasks-position",
            [_("Top of the list"), _("Bottom of the list")],
          )
        end

        def default_priority_row
          @default_priority_row ||= bind_enum(
            combo_row(_("Default Priority")),
            "default-priority",
            [_("Priority 1"), _("Priority 2"), _("Priority 3"), _("None")],
          )
        end

        def complete_task_row
          @complete_task_row ||= bind_enum(
            combo_row(_("Complete Task"), _("What happens when a task is completed")),
            "complete-task",
            [_("Instantly"), _("Wait 2500 milliseconds")],
          )
        end

        def description_preview_row
          @description_preview_row ||= bind_switch(
            switch_row(
              _("Description Preview"),
              _("Show the first line of a task's description in the list"),
            ),
            "description-preview",
          )
        end

        def underline_row
          @underline_row ||= bind_switch(
            switch_row(_("Strike Through Completed Tasks")),
            "underline-completed-tasks",
          )
        end

        def open_sidebar_row
          @open_sidebar_row ||= bind_switch(
            switch_row(_("Open Task Details on Click")),
            "open-task-sidebar",
          )
        end

        def details_sidebar_row
          @details_sidebar_row ||= bind_switch(
            switch_row(_("Always Show Task Details")),
            "always-show-details-sidebar",
          )
        end

        def markdown_row
          @markdown_row ||= bind_switch(
            switch_row(
              _("Markdown Formatting"),
              _("Style descriptions as you type them"),
            ),
            "enable-markdown-formatting",
          )
        end

        def subtasks_row
          @subtasks_row ||= bind_switch(
            switch_row(_("Always Show Completed Sub-tasks")),
            "always-show-completed-subtasks",
          )
        end

        def tone_row
          @tone_row ||= bind_switch(
            switch_row(_("Play a Sound on Completion")),
            "task-complete-tone",
          )
        end

        def datetime_group
          @datetime_group ||= Adwaita::PreferencesGroup.new.tap do |g|
            g.title = _("Date and Time")
          end
        end

        def clock_format_row
          @clock_format_row ||= bind_enum(
            combo_row(_("Clock Format")),
            "clock-format",
            [_("System Default"), _("12h"), _("24h")],
          )
        end

        def start_week_row
          @start_week_row ||= bind_enum(
            combo_row(_("Start of the Week")),
            "start-week",
            [_("Sunday"), _("Monday"), _("Tuesday"), _("Wednesday"), _("Thursday"),
             _("Friday"), _("Saturday")
],
          )
        end

        def smart_dates_row
          @smart_dates_row ||= bind_switch(
            switch_row(
              _("Smart Date Recognition"),
              _("Read dates, priorities and labels out of what you type"),
            ),
            "smart-date-recognition",
          )
        end

        def quick_add_group
          @quick_add_group ||= Adwaita::PreferencesGroup.new.tap { |g| g.title = _("Quick Add") }
        end

        def save_project_row
          @save_project_row ||= bind_switch(
            switch_row(_("Remember the Last Project")),
            "quick-add-save-last-project",
          )
        end

        def create_more_row
          @create_more_row ||= bind_switch(
            switch_row(_("Create More"), _("Keep the dialog open after adding a task")),
            "quick-add-create-more",
          )
        end

        def keep_properties_row
          @keep_properties_row ||= bind_switch(
            switch_row(
              _("Keep Properties"),
              _("Keep the date, labels and priority for the next task"),
            ),
            "quick-add-keep-properties",
          )
        end

        def close_focus_row
          @close_focus_row ||= bind_switch(
            switch_row(_("Close When Focus Is Lost")),
            "quick-add-close-loses-focus",
          )
        end
      end

      # src/Dialogs/Preferences/Pages/Appearance.vala.
      class Appearance
        include Bindings

        def page
          @page ||= Adwaita::PreferencesPage.new.tap do |p|
            p.title = _("Appearance")
            p.icon_name = "color-symbolic"
            p.add(theme_group)
            p.add(text_group)

            theme_group.add(system_row)
            theme_group.add(dark_row)
            theme_group.add(variant_row)
            theme_group.add(accent_row)

            text_group.add(font_scale_row)
          end
        end

        def theme_group
          @theme_group ||= Adwaita::PreferencesGroup.new.tap { |g| g.title = _("Theme") }
        end

        # Every one of these repaints, because the stylesheet's colours are
        # overridden at runtime rather than being in the file.
        def repaint(row, key)
          row.tap do |r|
            r.active = Settings.get_boolean(key)
            r.signal_connect("notify::active") do
              Settings.set_boolean(key, r.active?)
              Theme.update
              refresh_sensitivity
            end
          end
        end

        def refresh_sensitivity
          dark_row.sensitive = !Settings.get_boolean("system-appearance")
          variant_row.sensitive = Theme.dark?
        end

        def system_row
          @system_row ||= repaint(
            switch_row(_("Follow System Appearance")),
            "system-appearance",
          )
        end

        def dark_row
          @dark_row ||= repaint(switch_row(_("Dark Mode")), "dark-mode")
        end

        def variant_row
          @variant_row ||= combo_row(_("Dark Style")).tap do |row|
            row.model = Gtk::StringList.new([_("Light"), _("Dark"), _("Dark Blue")])
            row.selected = Settings.get_enum("appearance")
            row.signal_connect("notify::selected") do
              Settings.set_enum("appearance", row.selected)
              Theme.update
            end
          end
        end

        def accent_row
          @accent_row ||= repaint(
            switch_row(_("Use the System Accent Colour")),
            "use-system-accent",
          )
        end

        def text_group
          @text_group ||= Adwaita::PreferencesGroup.new.tap { |g| g.title = _("Text") }
        end

        # font-scale is a double, so it does not go through bind_spin.
        def font_scale_row
          @font_scale_row ||= Adwaita::SpinRow.new(
            Gtk::Adjustment.new(
              1.0,
              0.7,
              2.0,
              0.05,
              0.1,
              0,
            ),
            0.05,
            2,
          ).tap do |row|
            row.title = _("Font Size")
            row.value = Settings.settings.get_double("font-scale")
            row.signal_connect("notify::value") do
              Settings.settings.set_double("font-scale", row.value)
              Theme.update
            end
          end
        end
      end

      # src/Dialogs/Preferences/Pages/CalendarEvents.vala.
      class CalendarEvents
        include Bindings

        def page
          @page ||= Adwaita::PreferencesPage.new.tap do |p|
            p.title = _("Calendar")
            p.icon_name = "month-symbolic"
            p.add(enable_group)
            p.add(sources_group)

            enable_group.add(enable_row)
            reload_sources
          end
        end

        def enable_group
          @enable_group ||= Adwaita::PreferencesGroup.new.tap do |g|
            g.title = _("Calendar Events")
            g.description = availability_note
          end
        end

        # Being honest about why the switch is off is more useful than a
        # switch that silently does nothing.
        def availability_note
          if Services::CalendarEvents.available?
            _("Show your system's calendar events alongside your tasks.")
          else
            _(
              "Evolution Data Server is not available on this system, so calendar " \
                            "events cannot be read.",
            )
          end
        end

        def enable_row
          @enable_row ||= bind_switch(
            switch_row(_("Show Calendar Events")),
            "calendar-enabled",
          ).tap do |row|
            row.sensitive = Services::CalendarEvents.available?
            row.signal_connect("notify::active") { reload_sources }
          end
        end

        def sources_group
          @sources_group ||= Adwaita::PreferencesGroup.new.tap do |g|
            g.title = _("Calendars")
          end
        end

        def reload_sources
          @rows ||= []
          @rows.each { |row| sources_group.remove(row) }

          @rows = Services::CalendarEvents.all_sources.map { |source| source_row(source) }
          @rows.each { |row| sources_group.add(row) }
          sources_group.visible = !@rows.empty?
        end

        def source_row(source)
          Adwaita::SwitchRow.new.tap do |row|
            row.title = source.display_name.to_s
            row.active = Services::CalendarEvents.selected?(source)
            row.signal_connect("notify::active") do
              Services::CalendarEvents.enable_source(source.uid, row.active?)
            end
          end
        end
      end

      # src/Dialogs/Preferences/Pages/Backup.vala.
      class Backups
        include Bindings

        def initialize(dialog)
          @dialog = dialog
        end

        attr_reader :dialog

        def page
          @page ||= Adwaita::PreferencesPage.new.tap do |p|
            p.title = _("Backups")
            p.icon_name = "folder-download-symbolic"
            p.add(actions_group)
            p.add(automatic_group)
            p.add(history_group)

            actions_group.add(create_row)
            actions_group.add(import_row)
            actions_group.add(tutorial_row)

            automatic_group.add(automatic_row)

            reload_history
          end
        end

        def actions_group
          @actions_group ||= Adwaita::PreferencesGroup.new.tap do |g|
            g.title = _("Backups")
            g.description = _(
              "Backups are plain JSON and interchangeable with the " \
                                            "upstream Planify build.",
            )
          end
        end

        def create_row
          @create_row ||= action_row(_("Create Backup")) { create }
        end

        def import_row
          @import_row ||= action_row(_("Import Backup")) { import }
        end

        def tutorial_row
          @tutorial_row ||= action_row(
            _("Recreate “Meet Planify”"),
            _("Add the tutorial project back"),
          ) { recreate_tutorial }
        end

        def automatic_group
          @automatic_group ||= Adwaita::PreferencesGroup.new.tap do |g|
            g.title = _("Automatic Backups")
          end
        end

        def automatic_row
          @automatic_row ||= bind_switch(
            switch_row(_("Back Up Daily"), _("Keep the ten most recent")),
            "backup-automatic",
          )
        end

        def history_group
          @history_group ||= Adwaita::PreferencesGroup.new.tap do |g|
            g.title = _("Available Backups")
          end
        end

        def reload_history
          @rows ||= []
          @rows.each { |row| history_group.remove(row) }

          @rows = Services::BackupManager.list.map { |path| backup_row(path) }
          @rows.each { |row| history_group.add(row) }
          history_group.visible = !@rows.empty?
        end

        def backup_row(path)
          Services::BackupManager.describe(path).then do |details|
            Adwaita::ActionRow.new.tap do |row|
              row.title = File.basename(path)
              row.subtitle = describe(details)
              row.add_suffix(restore_button(path))
              row.add_suffix(delete_button(path))
            end
          end
        end

        def describe(details)
          if details.nil?
            _("Unreadable")
          else
            [
              Datetime.relative(details[:date]),
              n_("%d project", "%d projects", details[:projects]) % details[:projects],
              n_("%d task", "%d tasks", details[:items]) % details[:items],
            ].join(" · ")
          end
        end

        def restore_button(path)
          Gtk::Button.new(label: _("Restore")).tap do |button|
            button.add_css_class("flat")
            button.valign = :center
            button.signal_connect("clicked") { confirm_restore(path) }
          end
        end

        def delete_button(path)
          Gtk::Button.new(icon_name: "user-trash-symbolic").tap do |button|
            button.add_css_class("flat")
            button.valign = :center
            button.signal_connect("clicked") do
              File.delete(path)
              reload_history
            end
          end
        end

        def create
          Services::BackupManager.create.then do |path|
            dialog.add_toast(Adwaita::Toast.new(_("Backup saved to %s") % path))
            reload_history
          end
        end

        # Restoring replaces everything, so it asks first and says what it
        # will do rather than describing it as an import.
        def confirm_restore(path)
          Adwaita::AlertDialog.new(
            _("Restore This Backup?"),
            _(
              "Every project, task and label on this computer will be replaced by the " \
                            "contents of this backup. This cannot be undone.",
            ),
          ).tap do |alert|
            alert.add_response("cancel", _("Cancel"))
            alert.add_response("restore", _("Restore"))
            alert.set_response_appearance("restore", Adwaita::ResponseAppearance::DESTRUCTIVE)
            alert.signal_connect("response") do |_, response|
              if response == "restore"
                restore(path)
              end
            end
            alert.present(dialog)
          end
        end

        def restore(path)
          Services::BackupManager.restore(path)
          dialog.add_toast(Adwaita::Toast.new(_("Backup restored")))
        rescue StandardError => error
          dialog.add_toast(Adwaita::Toast.new(_("Restore failed: %s") % error.message))
        end

        # Gtk::FileDialog is async and raises on cancel, so the rescue here is
        # the cancel path.
        def import
          Gtk::FileDialog.new.tap do |chooser|
            chooser.title = _("Import Backup")
            chooser.open(nil, nil) do |_, result|
              begin
                confirm_restore(chooser.open_finish(result).path)
              rescue StandardError
                nil
              end
            end
          end
        end

        def recreate_tutorial
          Seed.create_tutorial(Store.instance)
          dialog.add_toast(Adwaita::Toast.new(_("“Meet Planify” recreated")))
        end
      end
    end
  end
end
