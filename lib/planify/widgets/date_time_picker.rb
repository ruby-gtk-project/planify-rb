# frozen_string_literal: true

module Planify
  # core/Widgets/DateTimePicker. The quick rows, a calendar, an optional time,
  # and the repeat configuration behind a disclosure — what upstream splits
  # across DateTimePicker, TimePicker, ScheduleButton and RepeatConfig.
  class DateTimePicker
    QUICK = [
      { key: "today", title: -> { _("Today") }, icon: "star-outline-thick-symbolic", offset: 0 },
      { key: "tomorrow", title: -> { _("Tomorrow") }, icon: "month-symbolic", offset: 1 },
      { key: "next_week", title: -> { _("Next Week") }, icon: "work-week-symbolic", offset: 7 },
      {
        key:    "next_weekend",
        title:  -> { _("This Weekend") },
        icon:   "weather-few-clouds-symbolic",
        offset: nil,
      },
    ].freeze

    # GLib::DateTime takes keyword options in the Ruby bindings and requires
    # all six; the positional form the C API documents does not exist here.
    def self.glib_datetime(time)
      GLib::DateTime.new(
        year:   time.year,
        month:  time.month,
        day:    time.day,
        hour:   0,
        minute: 0,
        second: 0,
      )
    end

    # ...and GLib::DateTime has no to_time, so a calendar selection is read
    # back field by field. The day accessor is `day_of_month`; plain `day`
    # does not exist on GLib::DateTime.
    def self.calendar_time(calendar)
      calendar.date.then { |date| Time.new(date.year, date.month, date.day_of_month) }
    end

    def initialize(&on_change)
      @on_change = on_change
      @datetime = nil
      @due = { "recurrency_type" => "none" }
      @applying = false
    end

    attr_reader :datetime, :due

    def build
      @build ||= box.tap do |b|
        b.append(quick_listbox)
        b.append(calendar)
        b.append(time_row)
        b.append(repeat_expander)
        b.append(clear_button)

        quick_listbox.tap do |list|
          QUICK.each { |quick| list.append(quick_row(quick)) }
          list.signal_connect("row-activated") { |_, row| pick_quick(QUICK[row.index]) }
        end

        calendar.signal_connect("day-selected") do
          pick(merge_time(self.class.calendar_time(calendar)))
        end

        time_row.tap do |row|
          row.append(time_switch)
          row.append(time_entry)
          row.append(time_button)

          time_switch.signal_connect("notify::active") { toggle_time }
          time_entry.signal_connect("changed") { retime }
          time_button.popover = time_popover
          time_popover.child = time_list

          time_list.tap do |list|
            PRESET_TIMES.each { |(hour, minute)| list.append(time_option(hour, minute)) }
            list.signal_connect("row-activated") do |_, row|
              PRESET_TIMES[row.index].then { |(hour, minute)| set_time(hour, minute) }
              time_popover.popdown
            end
          end
        end

        repeat_expander.tap do |expander|
          expander.add_row(repeat_row)
          repeat_row.child = repeat_config.build
        end

        clear_button.signal_connect("clicked") { pick(nil) }
      end
    end

    def datetime=(time)
      @applying = true
      @datetime = time

      unless time.nil?
        calendar.select_day(self.class.glib_datetime(time))
        time_switch.active = Datetime.has_time?(time)
        if Datetime.has_time?(time)
          time_entry.text = time.strftime("%H:%M")
        else
          time_entry.text = ""
        end
      end

      time_entry.sensitive = time_switch.active?
      @applying = false
    end

    def due=(hash)
      @applying = true
      if hash.nil?
        @due = { "recurrency_type" => "none" }
      else
        @due = hash.dup
      end
      repeat_config.due = @due
      repeat_expander.subtitle = repeat_summary
      repeat_expander.enable_expansion = @due["is_recurring"] == true
      @applying = false
    end

    # Kept for the callers that only care about the unit.
    def repeat = @due["recurrency_type"].to_s

    def repeat=(value)
      self.due = @due.merge(
        "recurrency_type" => value.to_s,
        "is_recurring"    => !value.to_s.empty? && value.to_s != "none",
      )
    end

    def repeat_summary
      if @due["is_recurring"] == true
        Recurrency.to_friendly_string(
          @due["recurrency_type"].to_s,
          @due["recurrency_interval"].to_i,
        )
      else
        _("Don't Repeat")
      end
    end

    def pick_quick(quick)
      if quick[:key] == "next_weekend"
        pick(merge_time(next_saturday))
      else
        pick(merge_time(Time.now + (quick[:offset] * 86_400)))
      end
    end

    # The coming Saturday; today counts only if today is Saturday.
    def next_saturday
      Time.now.then do |now|
        ((6 - now.wday) % 7).then { |offset| now + (offset * 86_400) }
      end
    end

    def toggle_time
      time_entry.sensitive = time_switch.active?
      retime
    end

    def retime
      pick(merge_time(@datetime || Time.now))
    end

    def set_time(hour, minute)
      time_switch.active = true
      time_entry.text = format("%02d:%02d", hour, minute)
    end

    def pick(time)
      unless @applying
        @datetime = time
        @on_change&.call(time, @due)
      end
    end

    # A free-text time that cannot be read leaves the date all-day rather than
    # rejecting the keystroke as it is typed.
    def merge_time(date)
      if time_switch.active?
        parse_time.then do |parsed|
          if parsed.nil?
            Datetime.strip_time(date)
          else
            Time.new(
              date.year,
              date.month,
              date.day,
              parsed[0],
              parsed[1],
              0,
            )
          end
        end
      else
        Datetime.strip_time(date)
      end
    end

    def parse_time
      time_entry.text.strip.match(/\A(\d{1,2})[:.]?(\d{2})?\s*([ap]m?)?\z/i).then do |match|
        if match.nil?
          nil
        else
          normalize_hour(match[1].to_i, match[3]).then do |hour|
            hour.nil? ? nil : [hour, match[2].to_i]
          end
        end
      end
    end

    def normalize_hour(hour, meridiem)
      if meridiem.to_s.downcase.start_with?("p")
        hour == 12 ? 12 : hour + 12
      elsif meridiem.to_s.downcase.start_with?("a")
        hour == 12 ? 0 : hour
      elsif hour.between?(0, 23)
        hour
      end
    end

    PRESET_TIMES = [[9, 0], [12, 0], [15, 0], [18, 0], [20, 0]].freeze

    def time_option(hour, minute)
      Gtk::ListBoxRow.new.tap do |row|
        row.child = Gtk::Label.new(format("%02d:%02d", hour, minute)).tap do |label|
          label.xalign = 0
          label.margin_start = 9
          label.margin_end = 9
          label.margin_top = 6
          label.margin_bottom = 6
        end
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

    def quick_listbox
      @quick_listbox ||= Gtk::ListBox.new.tap do |list|
        list.selection_mode = :none
        list.add_css_class("menu-listbox")
      end
    end

    def calendar = @calendar ||= Gtk::Calendar.new

    def time_row = @time_row ||= Gtk::Box.new(:horizontal, 9)

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

    def time_button
      @time_button ||= Gtk::MenuButton.new.tap do |button|
        button.icon_name = "clock-symbolic"
        button.add_css_class("flat")
        button.tooltip_text = _("Pick a Time")
      end
    end

    def time_popover = @time_popover ||= Gtk::Popover.new

    def time_list
      @time_list ||= Gtk::ListBox.new.tap do |list|
        list.selection_mode = :none
        list.add_css_class("menu-listbox")
      end
    end

    def repeat_expander
      @repeat_expander ||= Adwaita::ExpanderRow.new.tap do |row|
        row.title = _("Repeat")
        row.subtitle = _("Don't Repeat")
        row.show_enable_switch = true
        row.add_css_class("card")
        row.signal_connect("notify::enable-expansion") { toggle_repeat }
      end
    end

    def toggle_repeat
      unless @applying
        if repeat_expander.enable_expansion?
          @due = @due.merge(
            "is_recurring"        => true,
            "recurrency_type"     => default_recurrency,
            "recurrency_interval" => 1,
          )
        else
          @due = @due.merge("is_recurring" => false, "recurrency_type" => "none")
        end

        repeat_config.due = @due
        repeat_expander.subtitle = repeat_summary
        pick(@datetime)
      end
    end

    def default_recurrency
      @due["recurrency_type"].to_s.then do |current|
        current.empty? || current == "none" ? "every_day" : current
      end
    end

    def repeat_row
      @repeat_row ||= Adwaita::PreferencesRow.new.tap { |row| row.activatable = false }
    end

    def repeat_config
      @repeat_config ||= RepeatConfig.new do |updated|
        @due = updated
        repeat_expander.subtitle = repeat_summary
        pick(@datetime)
      end
    end

    def clear_button
      @clear_button ||= Gtk::Button.new(label: _("Clear")).tap do |button|
        button.add_css_class("flat")
      end
    end
  end
end
