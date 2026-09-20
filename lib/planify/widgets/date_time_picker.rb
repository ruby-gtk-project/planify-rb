# frozen_string_literal: true

module Planify
  # core/Widgets/DateTimePicker: the quick rows (Today, Tomorrow, Next Week),
  # a calendar, an optional time, and the repeat configuration. Returns a Time
  # and the recurrence fields that go into the item's `due` JSON.
  class DateTimePicker
    QUICK = [
      { key: "today", title: -> { _("Today") }, icon: "star-outline-thick-symbolic", offset: 0 },
      { key: "tomorrow", title: -> { _("Tomorrow") }, icon: "month-symbolic", offset: 1 },
      { key: "next_week", title: -> { _("Next Week") }, icon: "work-week-symbolic", offset: 7 },
    ].freeze

    REPEATS = [
      ["none", -> { _("Don't Repeat") }],
      ["every_day", -> { _("Every Day") }],
      ["every_week", -> { _("Every Week") }],
      ["every_month", -> { _("Every Month") }],
      ["every_year", -> { _("Every Year") }],
    ].freeze

    def initialize(&on_change)
      @on_change = on_change
      @datetime = nil
      @repeat = "none"
    end

    attr_reader :datetime, :repeat

    def build
      @build ||= box.tap do |b|
        b.append(quick_listbox)
        b.append(calendar)
        b.append(time_box)
        b.append(repeat_row)
        b.append(clear_button)

        quick_listbox.tap do |list|
          QUICK.each { |quick| list.append(quick_row(quick)) }

          list.signal_connect("row-activated") do |_, row|
            pick(Time.now + (QUICK[row.index][:offset] * 86_400))
          end
        end

        calendar.signal_connect("day-selected") do
          pick(merge_time(calendar_date))
        end

        time_box.tap do |tb|
          tb.append(time_switch)
          tb.append(time_entry)

          time_switch.signal_connect("notify::active") do
            time_entry.sensitive = time_switch.active?
            pick(merge_time(@datetime || Time.now))
          end

          time_entry.signal_connect("changed") { pick(merge_time(@datetime || Time.now)) }
        end

        repeat_row.tap do |row|
          row.model = Gtk::StringList.new(REPEATS.map { |(_, title)| title.call })
          row.signal_connect("notify::selected") do
            @repeat = REPEATS[row.selected][0]
            @on_change&.call(@datetime, @repeat)
          end
        end

        clear_button.signal_connect("clicked") { pick(nil) }
      end
    end

    def datetime=(time)
      @datetime = time

      unless time.nil?
        calendar.select_day(glib_datetime(time))
        time_switch.active = Datetime.has_time?(time)
        if Datetime.has_time?(time)
          time_entry.text = time.strftime("%H:%M")
        else
          time_entry.text = ""
        end
      end
    end

    # GLib::DateTime takes keyword options in the Ruby bindings, and requires
    # all six of them — the positional form the C API documents does not exist
    # here, and a year/month/day-only hash is rejected.
    def glib_datetime(time)
      GLib::DateTime.new(
        year:   time.year,
        month:  time.month,
        day:    time.day,
        hour:   0,
        minute: 0,
        second: 0,
      )
    end

    # ...and it offers no `to_time`, so the calendar's selection is read back
    # field by field.
    def calendar_date
      calendar.date.then do |date|
        Time.new(date.year, date.month, date.day_of_month)
      end
    end

    def repeat=(value)
      @repeat = value
      repeat_row.selected = REPEATS.index { |(key, _)| key == value } || 0
    end

    def pick(time)
      @datetime = time
      @on_change&.call(time, @repeat)
    end

    # The time entry is free text ("09:30"); an unparseable value leaves the
    # date as an all-day one rather than rejecting the keystroke.
    def merge_time(date)
      if time_switch.active?
        begin
          Time.parse(time_entry.text).then do |parsed|
            Time.new(
              date.year,
              date.month,
              date.day,
              parsed.hour,
              parsed.min,
              0,
            )
          end
        rescue ArgumentError
          Datetime.strip_time(date)
        end
      else
        Datetime.strip_time(date)
      end
    end

    def quick_row(quick)
      Gtk::ListBoxRow.new.tap do |row|
        row.child = Gtk::Box.new(:horizontal, 9).tap do |b|
          b.margin_start = 9
          b.margin_end = 9
          b.margin_top = 6
          b.margin_bottom = 6
          b.append(Gtk::Image.new(icon_name: quick[:icon]))
          b.append(Gtk::Label.new(quick[:title].call).tap { |label| label.xalign = 0 })
        end
      end
    end

    def box
      @box ||= Gtk::Box.new(:vertical, 6).tap do |b|
        b.margin_start = 9
        b.margin_end = 9
        b.margin_top = 9
        b.margin_bottom = 9
        b.width_request = 300
      end
    end

    def quick_listbox
      @quick_listbox ||= Gtk::ListBox.new.tap do |list|
        list.selection_mode = :none
        list.add_css_class("menu-listbox")
      end
    end

    def calendar = @calendar ||= Gtk::Calendar.new

    def time_box = @time_box ||= Gtk::Box.new(:horizontal, 9)

    def time_switch
      @time_switch ||= Gtk::Switch.new.tap do |switch|
        switch.valign = :center
        switch.tooltip_text = _("Time")
      end
    end

    def time_entry
      @time_entry ||= Gtk::Entry.new.tap do |entry|
        entry.placeholder_text = _("09:00")
        entry.hexpand = true
        entry.sensitive = false
      end
    end

    def repeat_row
      @repeat_row ||= Adwaita::ComboRow.new.tap do |row|
        row.title = _("Repeat")
        row.add_css_class("card")
      end
    end

    def clear_button
      @clear_button ||= Gtk::Button.new(label: _("Clear")).tap do |button|
        button.add_css_class("flat")
      end
    end
  end
end
