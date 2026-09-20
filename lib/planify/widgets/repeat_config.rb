# frozen_string_literal: true

module Planify
  # core/Widgets/DateTimePicker/RepeatConfig.vala. Everything the recurrence
  # model can express: unit and interval, which weekdays, last-day-of-month,
  # counting from completion rather than from the due date, and an end that is
  # never, on a date, or after a number of occurrences.
  class RepeatConfig
    UNITS = [
      ["minutely", -> { _("Minute") }],
      ["hourly", -> { _("Hour") }],
      ["every_day", -> { _("Day") }],
      ["every_week", -> { _("Week") }],
      ["every_month", -> { _("Month") }],
      ["every_year", -> { _("Year") }],
    ].freeze

    WEEKDAYS = [
      [1, -> { _("Mo") }], [2, -> { _("Tu") }], [3, -> { _("We") }], [4, -> { _("Th") }],
      [5, -> { _("Fr") }], [6, -> { _("Sa") }], [7, -> { _("Su") }],
    ].freeze

    END_MODES = %i[never on after].freeze

    def initialize(&on_change)
      @on_change = on_change
      @due = {}
      @weekday_buttons = {}
      @end_buttons = {}
      @applying = false
    end

    attr_reader :due

    def build
      @build ||= box.tap do |b|
        b.append(unit_row)
        b.append(weeks_revealer)
        b.append(last_day_row)
        b.append(from_completion_row)
        b.append(end_label)
        b.append(end_box)
        b.append(end_date_revealer)
        b.append(end_count_revealer)
        b.append(summary_label)

        unit_row.tap do |row|
          row.append(interval_spin)
          row.append(unit_button)
          unit_button.popover = unit_popover
          unit_popover.child = unit_list
        end

        interval_spin.signal_connect("value-changed") { changed }

        unit_list.tap do |list|
          UNITS.each { |(_, title)| list.append(unit_option(title.call)) }
          list.signal_connect("row-activated") do |_, row|
            @due["recurrency_type"] = UNITS[row.index][0]
            unit_popover.popdown
            changed
          end
        end

        weeks_revealer.child = weeks_box

        weeks_box.tap do |wb|
          WEEKDAYS.each do |(number, title)|
            weekday_button(number, title.call).tap do |button|
              @weekday_buttons[number] = button
              wb.append(button)
            end
          end
        end

        last_day_row.tap do |row|
          row.append(last_day_check)
          row.append(Gtk::Label.new(_("On the last day of the month")))
          last_day_check.signal_connect("toggled") { changed }
        end

        from_completion_row.tap do |row|
          row.append(from_completion_check)
          row.append(Gtk::Label.new(_("Count from the completion date")))
          from_completion_check.signal_connect("toggled") { changed }
        end

        end_box.tap do |eb|
          END_MODES.each_with_index do |mode, index|
            end_button(mode, index).tap do |button|
              @end_buttons[mode] = button
              eb.append(button)
            end
          end
        end

        end_date_revealer.child = end_calendar
        end_calendar.signal_connect("day-selected") { changed }

        end_count_revealer.child = end_count_box

        end_count_box.tap do |cb|
          cb.append(count_spin)
          cb.append(Gtk::Label.new(_("times")))
          count_spin.signal_connect("value-changed") { changed }
        end
      end
    end

    def due=(hash)
      @applying = true
      @due = hash.dup
      load
      @applying = false
      refresh
    end

    def load
      interval_spin.value = [@due["recurrency_interval"].to_i, 1].max
      last_day_check.active = @due["recurrency_last_day_of_month"] == true
      from_completion_check.active = @due["recurrency_from_completion"] == true
      count_spin.value = [@due["recurrency_count"].to_i, 1].max
      load_weeks
      load_end
    end

    def load_weeks
      @due["recurrency_weeks"].to_s.split(",").map(&:to_i).then do |days|
        @weekday_buttons.each { |number, button| button.active = days.include?(number) }
      end
    end

    def load_end
      end_mode.then do |mode|
        @end_buttons.each { |name, button| button.active = name == mode }
        Datetime.parse(@due["recurrency_end"]).then do |ends|
          unless ends.nil?
            end_calendar.select_day(DateTimePicker.glib_datetime(ends))
          end
        end
      end
    end

    def end_mode
      if !@due["recurrency_end"].to_s.empty?
        :on
      elsif @due["recurrency_count"].to_i.positive?
        :after
      else
        :never
      end
    end

    def changed
      unless @applying
        collect
        refresh
        @on_change&.call(@due)
      end
    end

    def collect
      @due["is_recurring"] = true
      @due["recurrency_interval"] = interval_spin.value.to_i
      @due["recurrency_weeks"] = selected_weeks
      @due["recurrency_last_day_of_month"] = last_day_check.active?
      @due["recurrency_from_completion"] = from_completion_check.active?
      collect_end
    end

    def selected_weeks
      @weekday_buttons.select { |_, button| button.active? }.keys.sort.join(",")
    end

    # The three end modes are exclusive: choosing one clears the others'
    # stored value, so a saved count cannot outlive a switch to "never".
    def collect_end
      selected_end.then do |mode|
        @due["recurrency_end"] = ""
        @due["recurrency_count"] = 0

        if mode == :on
          @due["recurrency_end"] = Datetime.format(DateTimePicker.calendar_time(end_calendar))
        elsif mode == :after
          @due["recurrency_count"] = count_spin.value.to_i
        end
      end
    end

    def selected_end
      @end_buttons.find { |_, button| button.active? }&.first || :never
    end

    def refresh
      weeks_revealer.reveal_child = @due["recurrency_type"] == "every_week"
      last_day_row.visible = @due["recurrency_type"] == "every_month"
      end_date_revealer.reveal_child = selected_end == :on
      end_count_revealer.reveal_child = selected_end == :after
      unit_label.label = unit_title
      summary_label.label = Recurrency.to_friendly_string(
        @due["recurrency_type"].to_s,
        @due["recurrency_interval"].to_i,
      )
    end

    def unit_title
      UNITS.find { |(key, _)| key == @due["recurrency_type"] }
           .then { |found| found.nil? ? UNITS[2][1].call : found[1].call }
    end

    # --- widgets ----------------------------------------------------------

    def box
      @box ||= Gtk::Box.new(:vertical, 9).tap do |b|
        b.margin_start = 12
        b.margin_end = 12
        b.margin_top = 12
        b.margin_bottom = 12
        b.width_request = 320
      end
    end

    def unit_row = @unit_row ||= Gtk::Box.new(:horizontal, 9)

    def interval_spin
      @interval_spin ||= Gtk::SpinButton.new(
        Gtk::Adjustment.new(
          1,
          1,
          999,
          1,
          5,
          0,
        ),
        1,
        0,
      )
    end

    def unit_button
      @unit_button ||= Gtk::MenuButton.new.tap do |button|
        button.child = unit_label
        button.hexpand = true
      end
    end

    def unit_label = @unit_label ||= Gtk::Label.new(_("Day"))

    def unit_popover = @unit_popover ||= Gtk::Popover.new

    def unit_list
      @unit_list ||= Gtk::ListBox.new.tap do |list|
        list.selection_mode = :none
        list.add_css_class("menu-listbox")
      end
    end

    def unit_option(title)
      Gtk::ListBoxRow.new.tap do |row|
        row.child = Gtk::Label.new(title).tap do |label|
          label.xalign = 0
          label.margin_start = 9
          label.margin_end = 9
          label.margin_top = 6
          label.margin_bottom = 6
        end
      end
    end

    def weeks_revealer
      @weeks_revealer ||= Gtk::Revealer.new.tap { |r| r.transition_type = :slide_down }
    end

    def weeks_box
      @weeks_box ||= Gtk::Box.new(:horizontal, 3).tap do |b|
        b.homogeneous = true
      end
    end

    def weekday_button(number, title)
      Gtk::ToggleButton.new(label: title).tap do |button|
        button.add_css_class("circular")
        button.signal_connect("toggled") { changed }
        button.tooltip_text = title
        @weekday_buttons ||= {}
        @weekday_buttons[number] = button
      end
    end

    def last_day_row
      @last_day_row ||= Gtk::Box.new(:horizontal, 9).tap { |b| b.visible = false }
    end

    def last_day_check = @last_day_check ||= Gtk::CheckButton.new

    def from_completion_row = @from_completion_row ||= Gtk::Box.new(:horizontal, 9)

    def from_completion_check = @from_completion_check ||= Gtk::CheckButton.new

    def end_label
      @end_label ||= Gtk::Label.new(_("Ends")).tap do |label|
        label.add_css_class("heading")
        label.xalign = 0
        label.margin_top = 6
      end
    end

    def end_box
      @end_box ||= Gtk::Box.new(:horizontal, 0).tap do |b|
        b.add_css_class("linked")
        b.homogeneous = true
      end
    end

    END_TITLES = {
      never: -> { _("Never") },
      on:    -> { _("On Date") },
      after: -> { _("After") },
    }.freeze

    def end_button(mode, _index)
      Gtk::ToggleButton.new(label: END_TITLES.fetch(mode).call).tap do |button|
        button.signal_connect("toggled") do
          if button.active?
            @end_buttons.each do |name, other|
              unless name == mode
                other.active = false
              end
            end
            changed
          end
        end
      end
    end

    def end_date_revealer
      @end_date_revealer ||= Gtk::Revealer.new.tap { |r| r.transition_type = :slide_down }
    end

    def end_calendar = @end_calendar ||= Gtk::Calendar.new

    def end_count_revealer
      @end_count_revealer ||= Gtk::Revealer.new.tap { |r| r.transition_type = :slide_down }
    end

    def end_count_box = @end_count_box ||= Gtk::Box.new(:horizontal, 9)

    def count_spin
      @count_spin ||= Gtk::SpinButton.new(
        Gtk::Adjustment.new(
          1,
          1,
          999,
          1,
          5,
          0,
        ),
        1,
        0,
      )
    end

    def summary_label
      @summary_label ||= Gtk::Label.new("").tap do |label|
        label.add_css_class("dim-label")
        label.add_css_class("caption")
        label.margin_top = 6
        label.wrap = true
      end
    end
  end
end
