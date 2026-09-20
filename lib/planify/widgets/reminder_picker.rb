# frozen_string_literal: true

module Planify
  # core/Widgets/ReminderPicker. The reminders already on a task, quick
  # relative offsets, and an absolute date-and-time for anything else.
  class ReminderPicker
    OFFSETS = [
      [5, -> { _("In 5 minutes") }],
      [15, -> { _("In 15 minutes") }],
      [30, -> { _("In 30 minutes") }],
      [60, -> { _("In 1 hour") }],
      [180, -> { _("In 3 hours") }],
      [360, -> { _("In 6 hours") }],
    ].freeze

    def initialize(item = nil)
      @item = item
    end

    attr_reader :item

    def store = Store.instance

    def build
      @build ||= box.tap do |b|
        b.append(list_label)
        b.append(listbox)
        b.append(Gtk::Separator.new(:horizontal))
        b.append(quick_label)
        b.append(quick_listbox)
        b.append(absolute_button)
        b.append(absolute_revealer)
        b.append(error_label)

        quick_listbox.tap do |list|
          OFFSETS.each { |(_, title)| list.append(option_row(title.call, "alarm-symbolic")) }
          list.signal_connect("row-activated") do |_, row|
            add_relative(OFFSETS[row.index][0])
          end
        end

        absolute_button.signal_connect("clicked") do
          absolute_revealer.reveal_child = !absolute_revealer.reveal_child?
        end

        absolute_revealer.child = absolute_box

        absolute_box.tap do |ab|
          ab.append(date_picker.build)
          ab.append(add_button.build)
        end

        refresh
      end
    end

    def item=(value)
      @item = value
      refresh
    end

    def refresh
      while listbox.first_child
        listbox.remove(listbox.first_child)
      end

      reminders.each { |reminder| listbox.append(reminder_row(reminder)) }
      placeholder.visible = reminders.empty?
      error_label.visible = false
    end

    def reminders
      item.nil? ? [] : store.reminders_by_item(item.id).sort_by { |r| r.due_date.to_i }
    end

    def reminder_row(reminder)
      Adwaita::ActionRow.new.tap do |row|
        row.title = Datetime.relative(reminder.due_date)
        if reminder.type == "relative"
          row.subtitle = _("Relative")
        else
          row.subtitle = _("Absolute")
        end
        row.add_prefix(Gtk::Image.new(icon_name: "alarm-symbolic"))
        row.add_suffix(delete_button(reminder))
      end
    end

    def delete_button(reminder)
      Gtk::Button.new(icon_name: "user-trash-symbolic").tap do |button|
        button.add_css_class("flat")
        button.valign = :center
        button.signal_connect("clicked") { store.delete_reminder(reminder) }
        button.signal_connect("clicked") { refresh }
      end
    end

    def option_row(title, icon)
      Gtk::ListBoxRow.new.tap do |row|
        row.child = Gtk::Box.new(:horizontal, 9).tap do |b|
          b.margin_start = 9
          b.margin_end = 9
          b.margin_top = 6
          b.margin_bottom = 6
          b.append(Gtk::Image.new(icon_name: icon))
          b.append(Gtk::Label.new(title).tap { |label| label.xalign = 0 })
        end
      end
    end

    def add_relative(minutes)
      base_time.then { |base| add(base + (minutes * 60), "relative", minutes) }
    end

    # A relative reminder counts from the due date when there is one, and from
    # now when there is not.
    def base_time
      if item&.has_due?
        item.due_date
      else
        Time.now
      end
    end

    def add_absolute
      date_picker.datetime.then do |time|
        if time.nil?
          show_error(_("Pick a date first"))
        else
          add(time, "absolute", 0)
        end
      end
    end

    def add(time, type, offset)
      if item.nil?
        nil
      elsif time <= Time.now
        show_error(_("Choose a time in the future"))
      elsif duplicate?(time)
        show_error(_("You already have a reminder at that time"))
      else
        store.insert_reminder(
          Reminder.new(item_id: item.id, type: type, mm_offset: offset).tap do |reminder|
            reminder.due_date = time
          end,
        )
        refresh
      end
    end

    def duplicate?(time)
      reminders.any? { |reminder| reminder.due_date.to_i == time.to_i }
    end

    def show_error(message)
      error_label.label = message
      error_label.visible = true
    end

    # --- widgets ----------------------------------------------------------

    def box
      @box ||= Gtk::Box.new(:vertical, 6).tap do |b|
        b.margin_start = 9
        b.margin_end = 9
        b.margin_top = 9
        b.margin_bottom = 9
        b.width_request = 320
      end
    end

    def list_label
      @list_label ||= Gtk::Label.new(_("Reminders")).tap do |label|
        label.add_css_class("heading")
        label.xalign = 0
      end
    end

    def listbox
      @listbox ||= Gtk::ListBox.new.tap do |list|
        list.selection_mode = :none
        list.add_css_class("boxed-list")
        list.set_placeholder(placeholder)
      end
    end

    def placeholder
      @placeholder ||= Gtk::Label.new(
        _("Your list of reminders will show up here. Add one by clicking the '+' button."),
      ).tap do |label|
        label.add_css_class("dim-label")
        label.add_css_class("caption")
        label.wrap = true
        label.margin_top = 9
        label.margin_bottom = 9
        label.margin_start = 9
        label.margin_end = 9
      end
    end

    def quick_label
      @quick_label ||= Gtk::Label.new(_("Add a Reminder")).tap do |label|
        label.add_css_class("heading")
        label.xalign = 0
        label.margin_top = 6
      end
    end

    def quick_listbox
      @quick_listbox ||= Gtk::ListBox.new.tap do |list|
        list.selection_mode = :none
        list.add_css_class("menu-listbox")
      end
    end

    def absolute_button
      @absolute_button ||= Gtk::Button.new(label: _("Pick a Date and Time")).tap do |button|
        button.add_css_class("flat")
      end
    end

    def absolute_revealer
      @absolute_revealer ||= Gtk::Revealer.new.tap { |r| r.transition_type = :slide_down }
    end

    def absolute_box = @absolute_box ||= Gtk::Box.new(:vertical, 6)

    def date_picker = @date_picker ||= DateTimePicker.new

    def add_button
      @add_button ||= LoadingButton.new(_("Add Reminder")) { add_absolute }
    end

    def error_label
      @error_label ||= Gtk::Label.new("").tap do |label|
        label.add_css_class("error")
        label.add_css_class("caption")
        label.wrap = true
        label.visible = false
      end
    end
  end
end
