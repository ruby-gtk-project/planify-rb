# frozen_string_literal: true

module Planify
  module Views
    # src/Views/Today.vala. Overdue with a reschedule control, today's tasks,
    # the day's calendar events, and completed tasks behind a disclosure.
    class TodayView < BaseView
      include Sorting

      def settings_prefix = "today"

      def title = _("Today")

      def subtitle
        Time.now.strftime(_("%A, %B %e")).squeeze(" ")
      end

      def overdue = store.overdue_items

      def today = store.pending.select { |item| Datetime.today?(item.due_date) }

      def completed_today
        store.completed_items.select { |item| Datetime.today?(Datetime.parse(item.completed_at)) }
      end

      def items = overdue + today

      def empty_title = _("Nothing due today")

      def empty_description = _("Enjoy the rest of your day.")

      def empty_icon = "star-outline-thick-symbolic"

      def quick_add_defaults = { project: store.inbox_project, due: Time.now }

      def build
        @build ||= super.tap do
          header.pack_end(sort_button)
          header.pack_end(productivity.build)
          sort_button.menu_model = sort_menu_model
          register_sort_actions(toolbar)

          clamp.child = column_box

          column_box.tap do |box|
            box.append(overdue_box)
            box.append(events_list.build)
            box.append(today_box)
            box.append(completed_expander)

            overdue_box.append(overdue_header)
            overdue_box.append(overdue_list)

            overdue_header.tap do |h|
              h.append(overdue_label)
              h.append(overdue_count)
              h.append(reschedule_button)
            end

            today_box.append(today_header)
            today_box.append(today_list)

            today_header.append(today_label)
            today_header.append(today_count)
          end

          Services::EventBus.on(:day_changed, owner: self) { refresh }
        end
      end

      def refresh
        window_title.title = title
        window_title.subtitle = subtitle
        rebuild_overdue
        rebuild_today
        rebuild_completed
        events_list.date = Date.today
        productivity.refresh
        if items.empty?
          stack.visible_child_name = "empty"
        else
          stack.visible_child_name = "list"
        end
      end

      def rebuild_overdue
        fill(overdue_list, apply_sort(overdue))
        overdue_count.label = overdue.size.to_s
        overdue_box.visible = !overdue.empty?
      end

      def rebuild_today
        fill(today_list, apply_sort(today))
        today_count.label = today.size.to_s
        today_box.visible = !today.empty?
      end

      # Completed tasks are opt-in per the preference, and collapsed even then.
      def rebuild_completed
        @completed_rows ||= []
        @completed_rows.each { |row| completed_expander.remove(row) }

        if Settings.get_boolean("show-today-completed")
          @completed_rows = completed_today.map { |item| CompletedTaskRow.new(window, item).build }
          @completed_rows.each { |row| completed_expander.add_row(row) }
        else
          @completed_rows = []
        end

        completed_expander.subtitle = n_("%d task", "%d tasks", completed_today.size) %
                                      completed_today.size
        completed_expander.visible = Settings.get_boolean("show-today-completed") &&
                                     !completed_today.empty?
      end

      # Each list keeps its own row cache, so a refresh touches only what
      # actually changed rather than rebuilding both sections.
      def caches = @caches ||= Hash.new { |hash, key| hash[key] = {} }

      def fill(list, group)
        caches[list].then do |cache|
          ids = group.map(&:id)

          (cache.keys - ids).each { |id| list.remove(cache.delete(id).build) }

          group.each do |item|
            if cache.key?(item.id)
              cache.fetch(item.id).refresh
            else
              ItemRow.new(window, item).tap do |row|
                cache[item.id] = row
                @rows[item.id] = row.build
                list.append(row.build)
              end
            end
          end
        end
      end

      # --- widgets ---------------------------------------------------------

      def column_box = @column_box ||= Gtk::Box.new(:vertical, 12)

      def overdue_box
        @overdue_box ||= Gtk::Box.new(:vertical, 3).tap { |b| b.visible = false }
      end

      def overdue_header = @overdue_header ||= Gtk::Box.new(:horizontal, 6)

      def overdue_label
        @overdue_label ||= Gtk::Label.new(_("Overdue")).tap do |label|
          label.add_css_class("heading")
          label.add_css_class("error")
          label.xalign = 0
          label.hexpand = true
        end
      end

      def overdue_count
        @overdue_count ||= Gtk::Label.new("").tap do |label|
          label.add_css_class("dim-label")
          label.add_css_class("caption")
        end
      end

      def reschedule_button
        @reschedule_button ||= Gtk::MenuButton.new.tap do |button|
          button.label = _("Reschedule")
          button.add_css_class("flat")
          button.popover = reschedule_popover
          reschedule_popover.child = reschedule_picker.build
        end
      end

      def reschedule_popover = @reschedule_popover ||= Gtk::Popover.new

      def reschedule_picker
        @reschedule_picker ||= DateTimePicker.new do |time, due|
          overdue.each do |item|
            item.due_date = time

            unless time.nil?
              item.due = JSON.generate(item.due_hash.merge(due))
            end

            store.update_item(item)
          end

          reschedule_popover.popdown
        end
      end

      def overdue_list
        @overdue_list ||= Gtk::ListBox.new.tap do |list|
          list.selection_mode = :none
          list.add_css_class("background")
        end
      end

      def events_list = @events_list ||= EventsList.new(Date.today)

      def today_box = @today_box ||= Gtk::Box.new(:vertical, 3)

      def today_header = @today_header ||= Gtk::Box.new(:horizontal, 6)

      def today_label
        @today_label ||= Gtk::Label.new(_("Today")).tap do |label|
          label.add_css_class("heading")
          label.xalign = 0
          label.hexpand = true
        end
      end

      def today_count
        @today_count ||= Gtk::Label.new("").tap do |label|
          label.add_css_class("dim-label")
          label.add_css_class("caption")
        end
      end

      def today_list
        @today_list ||= Gtk::ListBox.new.tap do |list|
          list.selection_mode = :none
          list.add_css_class("background")
        end
      end

      def completed_expander
        @completed_expander ||= Adwaita::ExpanderRow.new.tap do |row|
          row.title = _("Completed")
          row.add_css_class("card")
          row.visible = false
        end
      end

      def productivity = @productivity ||= ProductivityMiniWidget.new

      def sort_button
        @sort_button ||= Gtk::MenuButton.new.tap do |button|
          button.icon_name = "vertical-arrows-long-symbolic"
          button.add_css_class("flat")
          button.tooltip_text = _("View Option Menu")
        end
      end
    end
  end
end
