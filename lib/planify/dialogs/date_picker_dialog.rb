# frozen_string_literal: true

module Planify
  module Dialogs
    # src/Dialogs/DatePicker.vala: the date picker as a dialog, for the places
    # a popover would be clipped.
    class DatePicker
      def initialize(datetime = nil, &on_pick)
        @datetime = datetime
        @on_pick = on_pick
      end

      def present(parent)
        dialog.tap do |d|
          d.child = toolbar

          toolbar.tap do |view|
            view.add_top_bar(header)
            view.content = picker.build

            header.show_end_title_buttons = false
            header.pack_start(cancel_button)
            header.pack_end(done_button)
            header.title_widget = Adwaita::WindowTitle.new(_("Schedule"), "")

            cancel_button.signal_connect("clicked") { d.close }
            done_button.signal_connect("clicked") { finish }
          end

          picker.datetime = @datetime
          d.present(parent)
        end
      end

      def finish
        @on_pick&.call(picker.datetime, picker.due)
        dialog.close
      end

      def dialog
        @dialog ||= Adwaita::Dialog.new.tap do |d|
          d.title = _("Schedule")
          d.content_width = 360
        end
      end

      def toolbar = @toolbar ||= Adwaita::ToolbarView.new

      def header = @header ||= Adwaita::HeaderBar.new

      def cancel_button = @cancel_button ||= Gtk::Button.new(label: _("Cancel"))

      def done_button
        @done_button ||= Gtk::Button.new(label: _("Done")).tap do |button|
          button.add_css_class("suggested-action")
        end
      end

      def picker = @picker ||= DateTimePicker.new
    end

    # src/Dialogs/ProjectPicker.vala and LabelPicker.vala: the same pickers as
    # dialogs, used from the multi-select toolbar where there is no anchor.
    class ProjectPickerDialog
      def initialize(project = nil, section = nil, &on_pick)
        @project = project
        @section = section
        @on_pick = on_pick
      end

      def present(parent)
        dialog.tap do |d|
          d.child = toolbar

          toolbar.tap do |view|
            view.add_top_bar(header)
            view.content = picker.build
            header.title_widget = Adwaita::WindowTitle.new(_("Move To"), "")
          end

          d.present(parent)
        end
      end

      def picker
        @picker ||= ProjectPicker.new(project: @project, section: @section) do |project, section|
          @on_pick&.call(project, section)
          dialog.close
        end
      end

      def dialog
        @dialog ||= Adwaita::Dialog.new.tap do |d|
          d.title = _("Move To")
          d.content_width = 400
          d.content_height = 520
        end
      end

      def toolbar = @toolbar ||= Adwaita::ToolbarView.new

      def header = @header ||= Adwaita::HeaderBar.new
    end

    class LabelPickerDialog
      def initialize(selected = [], &on_change)
        @selected = selected
        @on_change = on_change
      end

      def present(parent)
        dialog.tap do |d|
          d.child = toolbar

          toolbar.tap do |view|
            view.add_top_bar(header)
            view.content = picker.build
            header.title_widget = Adwaita::WindowTitle.new(_("Labels"), "")
          end

          d.present(parent)
        end
      end

      def picker
        @picker ||= LabelPicker.new(@selected) { |ids| @on_change&.call(ids) }
      end

      def dialog
        @dialog ||= Adwaita::Dialog.new.tap do |d|
          d.title = _("Labels")
          d.content_width = 360
          d.content_height = 480
        end
      end

      def toolbar = @toolbar ||= Adwaita::ToolbarView.new

      def header = @header ||= Adwaita::HeaderBar.new
    end

    # src/Dialogs/CalendarSync.vala: which system calendars to show, offered
    # once at first run rather than buried in preferences.
    class CalendarSync
      def present(parent)
        dialog.tap do |d|
          d.child = toolbar

          toolbar.tap do |view|
            view.add_top_bar(header)
            view.content = page

            header.title_widget = Adwaita::WindowTitle.new(_("Calendar Events"), "")
            header.pack_end(done_button)
            done_button.signal_connect("clicked") { d.close }

            page.add(group)
          end

          reload
          d.present(parent)
        end
      end

      def reload
        Services::CalendarEvents.all_sources.then do |sources|
          sources.each { |source| group.add(source_row(source)) }
          group.description = description_for(sources)
        end
      end

      def description_for(sources)
        if !Services::CalendarEvents.available?
          _("Evolution Data Server is not available on this system.")
        elsif sources.empty?
          _("No calendars were found on this computer.")
        else
          _("Choose which calendars appear next to your tasks.")
        end
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

      def dialog
        @dialog ||= Adwaita::Dialog.new.tap do |d|
          d.title = _("Calendar Events")
          d.content_width = 440
        end
      end

      def toolbar = @toolbar ||= Adwaita::ToolbarView.new

      def header = @header ||= Adwaita::HeaderBar.new

      def done_button
        @done_button ||= Gtk::Button.new(label: _("Done")).tap do |button|
          button.add_css_class("suggested-action")
        end
      end

      def page = @page ||= Adwaita::PreferencesPage.new

      def group
        @group ||= Adwaita::PreferencesGroup.new.tap { |g| g.title = _("Calendars") }
      end
    end
  end
end
