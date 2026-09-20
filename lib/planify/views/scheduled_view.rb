# frozen_string_literal: true

module Planify
  module Views
    # src/Views/Scheduled. Overdue first, then one section per day for the
    # rest of this week, then a range covering the remainder of the month,
    # then one section per month after that. Empty days are skipped; an empty
    # overdue section is not shown at all.
    class ScheduledView < BaseView
      include Sorting

      DAYS_AHEAD = 7

      def settings_prefix = "scheduled"

      def title = _("Scheduled")

      def subtitle
        items.size.then { |count| n_("%d task", "%d tasks", count) % count }
      end

      def items = store.scheduled_items

      def overdue = store.overdue_items

      def empty_title = _("Nothing scheduled")

      def empty_description = _("Tasks with a future due date show up here.")

      def empty_icon = "month-symbolic"

      def quick_add_defaults = { project: store.inbox_project }

      def build
        @build ||= super.tap do
          header.pack_end(sort_button)
          sort_button.menu_model = sort_menu_model
          register_sort_actions(toolbar)

          clamp.child = sections_box
          Services::EventBus.on(:day_changed, owner: self) { refresh }
        end
      end

      def refresh
        window_title.title = title
        window_title.subtitle = subtitle
        rebuild_sections
        if items.empty? && overdue.empty?
          stack.visible_child_name = "empty"
        else
          stack.visible_child_name = "list"
        end
      end

      def rebuild_sections
        while sections_box.first_child
          sections_box.remove(sections_box.first_child)
        end

        @rows = {}
        overdue_section.then do |section|
          unless section.nil?
            sections_box.append(section)
          end
        end
        day_sections.each { |section| sections_box.append(section) }
        month_sections.each { |section| sections_box.append(section) }
      end

      # Overdue carries a reschedule button, because that is the action almost
      # every overdue list wants.
      def overdue_section
        if overdue.empty?
          nil
        else
          section_box(_("Overdue"), apply_sort(overdue), reschedule_button)
        end
      end

      def day_sections
        (0...DAYS_AHEAD).filter_map do |offset|
          (Date.today + offset).then do |date|
            items_on(date).then do |found|
              if found.empty?
                next nil
              end

              section_box(
                Datetime.date_word(Time.new(date.year, date.month, date.day)),
                apply_sort(found),
              )
            end
          end
        end
      end

      # Everything past the per-day window, bucketed by month.
      def month_sections
        items.reject { |item| within_days?(item) }
             .group_by { |item| item.due_date.strftime("%Y-%m") }
             .sort.map do |(key, group)|
          section_box(month_title(key), apply_sort(group))
        end
      end

      def month_title(key)
        Time.new(key.split("-")[0].to_i, key.split("-")[1].to_i, 1).then do |time|
          if time.year == Time.now.year
            time.strftime(_("%B"))
          else
            time.strftime(_("%B %Y"))
          end
        end
      end

      def within_days?(item)
        item.due_date.to_date.then do |date|
          date >= Date.today && date < Date.today + DAYS_AHEAD
        end
      end

      def items_on(date)
        items.select { |item| item.due_date.to_date == date }
      end

      def section_box(heading, group, suffix = nil)
        Gtk::Box.new(:vertical, 3).tap do |box|
          box.margin_bottom = 18
          box.append(section_header(heading, group.size, suffix))
          box.append(events_for(heading))
          box.append(section_list(group))
        end
      end

      # The system calendar's events for a day sit above that day's tasks.
      def events_for(heading)
        Date.today.then do |today|
          if heading == Datetime.date_word(Time.new(today.year, today.month, today.day))
            EventsList.new(today).build
          else
            Gtk::Box.new(:vertical, 0).tap { |b| b.visible = false }
          end
        end
      end

      def section_header(heading, count, suffix)
        Gtk::Box.new(:horizontal, 6).tap do |box|
          box.append(
            Gtk::Label.new(heading).tap do |label|
                        label.add_css_class("heading")
                        label.xalign = 0
                        label.hexpand = true
                      end,
          )
          box.append(
            Gtk::Label.new(count.to_s).tap do |label|
                        label.add_css_class("dim-label")
                        label.add_css_class("caption")
                      end,
          )
          unless suffix.nil?
            box.append(suffix)
          end
        end
      end

      def section_list(group)
        Gtk::ListBox.new.tap do |list|
          list.selection_mode = :none
          list.add_css_class("background")

          group.each do |item|
            ItemRow.new(window, item).build.tap do |row|
              @rows[item.id] = row
              list.append(row)
            end
          end
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

      def sections_box = @sections_box ||= Gtk::Box.new(:vertical, 0)

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
