# frozen_string_literal: true

module Planify
  # Datetime.next_recurrency plus the end conditions DueDate.is_recurrency_end
  # decides. A nil result means the series has run out and the task is simply
  # completed instead of rescheduled.
  module Recurrency
    TYPES = %w[minutely hourly every_day every_week every_month every_year none].freeze

    module_function

    def next_date(item)
      due = item.due_hash

      if ended?(item)
        nil
      else
        advance(item.due_date, due)
      end
    end

    def ended?(item)
      due = item.due_hash

      if !due["recurrency_end"].to_s.empty?
        Datetime.parse(due["recurrency_end"]).then do |ends|
          ends.nil? ? false : advance(item.due_date, due).to_date > ends.to_date
        end
      elsif due["recurrency_count"].to_i.positive?
        due["recurrency_count"].to_i - 1 <= 0
      else
        false
      end
    end

    def advance(from, due)
      interval = [due["recurrency_interval"].to_i, 1].max
      weeks = due["recurrency_weeks"].to_s

      case due["recurrency_type"]
      when "minutely"    then from + (interval * 60)
      when "hourly"      then from + (interval * 3600)
      when "every_day"   then from + (interval * 86_400)
      when "every_week"  then next_week(from, interval, weeks)
      when "every_month" then next_month(from, interval, due["recurrency_last_day_of_month"])
      when "every_year"  then shift_months(from, interval * 12)
      else from
      end
    end

    # "Every week on Mon, Thu" — walk forward to the next selected weekday,
    # and only when none is left in this week jump by the interval.
    def next_week(from, interval, weeks)
      if weeks.empty?
        from + (interval * 7 * 86_400)
      else
        days = weeks.split(",").map(&:to_i).sort
        (1..7).each_with_object([]) { |offset, found| found << from + (offset * 86_400) }
              .find { |candidate| days.include?(iso_weekday(candidate)) }
              .then { |found| found.nil? ? from + (interval * 7 * 86_400) : found }
      end
    end

    # GLib counts Monday as 1 through Sunday as 7; Ruby's wday has Sunday at 0.
    def iso_weekday(time) = time.wday.zero? ? 7 : time.wday

    def next_month(from, interval, last_day)
      shift_months(from, interval).then do |shifted|
        if last_day
          Time.new(

            shifted.year,

            shifted.month,

            days_in_month(shifted.year, shifted.month),
            shifted.hour,

            shifted.min,

            shifted.sec,
          )
        else
          shifted
        end
      end
    end

    # Clamped, so the 31st plus one month lands on the 28th of February rather
    # than overflowing into March.
    def shift_months(from, months)
      ((from.year * 12) + (from.month - 1) + months).then do |total|
        year = total / 12
        month = (total % 12) + 1
        Time.new(

          year,

          month,

          [from.day, days_in_month(year, month)].min,
          from.hour,

          from.min,

          from.sec,
        )
      end
    end

    def days_in_month(year, month) = Date.new(year, month, -1).day

    def to_friendly_string(type, interval)
      if interval.to_i.zero?
        count = 1
      else
        count = interval.to_i
      end

      case type
      when "minutely"    then n_("Every minute", "Every %d minutes", count) % count
      when "hourly"      then n_("Every hour", "Every %d hours", count) % count
      when "every_day"   then n_("Every day", "Every %d days", count) % count
      when "every_week"  then n_("Every week", "Every %d weeks", count) % count
      when "every_month" then n_("Every month", "Every %d months", count) % count
      when "every_year"  then n_("Every year", "Every %d years", count) % count
      else _("Don't Repeat")
      end
    end

    # --- Todoist natural language ----------------------------------------

    # Upstream runs the recurrence string through a Chrono parser. The strings
    # Todoist actually emits for the recurrences Planify can create are a
    # small, regular set, so they are matched directly — an unrecognised
    # string leaves the task non-recurring rather than guessing at it.
    WEEKDAY_NAMES = %w[mon tue wed thu fri sat sun].freeze

    UNITS = {
      "hour"  => "hourly",
      "day"   => "every_day",
      "week"  => "every_week",
      "month" => "every_month",
      "year"  => "every_year",
    }.freeze

    def parse_todoist(due)
      if due["is_recurring"] != true
        "none"
      else
        parse_string(due["string"].to_s.downcase)[0]
      end
    end

    def interval_todoist(due)
      if due["is_recurring"] != true
        0
      else
        parse_string(due["string"].to_s.downcase)[1]
      end
    end

    def weeks_todoist(due)
      if due["is_recurring"] != true
        ""
      else
        parse_string(due["string"].to_s.downcase)[2]
      end
    end

    # Returns [type, interval, weeks]. "every 2 weeks", "every mon,thu",
    # "every weekday", "every day at 09:00 until 2030-01-01".
    def parse_string(text)
      match = text.match(/\bevery\s+(?:(\d+)\s+)?(hour|day|week|month|year)s?\b/)
      weeks = parse_weeks(text)

      if match
        [UNITS.fetch(match[2]), [match[1].to_i, 1].max, weeks]
      elsif !weeks.empty?
        ["every_week", 1, weeks]
      else
        ["none", 0, ""]
      end
    end

    def parse_weeks(text)
      if text.match?(/\bevery\s+(?:\d+\s+)?weekdays?\b/)
        "1,2,3,4,5"
      else
        text.scan(/\b(#{WEEKDAY_NAMES.join('|')})\b/).flatten
            .map { |name| WEEKDAY_NAMES.index(name) + 1 }
            .uniq.sort.join(",")
      end
    end

    # The inverse: what Planify sends back as the due `string`. Ported from
    # Datetime.due_to_todoist_natural_language.
    def to_todoist_string(item)
      due = item.due_hash

      if !due["recurrence_string"].to_s.empty? && due["is_recurring"] == true
        due["recurrence_string"].to_s
      elsif due["is_recurring"] != true || !UNITS.value?(due["recurrency_type"].to_s)
        item.due_date.nil? ? "" : Datetime.format(item.due_date)
      else
        build_todoist_string(item, due)
      end
    end

    def build_todoist_string(item, due)
      "every ".dup.tap do |text|
        text << interval_phrase(due)
        text << weeks_phrase(due)
        text << time_phrase(item)
        text << until_phrase(due)
      end.strip
    end

    def unit_word(type) = UNITS.key(type).to_s

    def interval_phrase(due)
      interval = due["recurrency_interval"].to_i
      weekly_with_days = due["recurrency_type"] == "every_week" &&
                         !due["recurrency_weeks"].to_s.empty?

      if interval > 1
        "#{interval} #{unit_word(due['recurrency_type'])}s "
      elsif weekly_with_days
        ""
      else
        "#{unit_word(due['recurrency_type'])} "
      end
    end

    def weeks_phrase(due)
      weeks = due["recurrency_weeks"].to_s

      if due["recurrency_type"] != "every_week" || weeks.empty?
        ""
      elsif weeks == "1,2,3,4,5"
        due["recurrency_interval"].to_i > 1 ? "weekdays " : "weekday "
      else
        weeks.split(",").map(&:to_i).select { |day| day.between?(1, 7) }
             .map { |day| WEEKDAY_NAMES[day - 1] }.join(",").concat(" ")
      end
    end

    def time_phrase(item)
      if Datetime.has_time?(item.due_date)
        "at #{item.due_date.strftime('%H:%M')} "
      else
        ""
      end
    end

    def until_phrase(due)
      if due["recurrency_end"].to_s.empty?
        ""
      else
        Datetime.parse(due["recurrency_end"]).then do |ends|
          ends.nil? ? "" : "until #{ends.strftime('%F')} "
        end
      end
    end

    # --- iCalendar RRULE --------------------------------------------------

    RRULE_FREQ = {
      "minutely"    => "MINUTELY",
      "hourly"      => "HOURLY",
      "every_day"   => "DAILY",
      "every_week"  => "WEEKLY",
      "every_month" => "MONTHLY",
      "every_year"  => "YEARLY",
    }.freeze

    RRULE_DAYS = %w[MO TU WE TH FR SA SU].freeze

    def to_rrule(due)
      RRULE_FREQ.fetch(due["recurrency_type"].to_s, nil).then do |freq|
        if freq.nil?
          nil
        else
          rrule_parts(due, freq).join(";")
        end
      end
    end

    def rrule_parts(due, freq)
      ["FREQ=#{freq}"].tap do |parts|
        if due["recurrency_interval"].to_i > 1
          parts << "INTERVAL=#{due['recurrency_interval']}"
        end
        if due["recurrency_count"].to_i.positive?
          parts << "COUNT=#{due['recurrency_count']}"
        end
        unless due["recurrency_weeks"].to_s.empty?
          parts << "BYDAY=#{rrule_days(due['recurrency_weeks'])}"
        end
        if due["recurrency_last_day_of_month"] == true
          parts << "BYMONTHDAY=-1"
        end

        unless due["recurrency_end"].to_s.empty?
          Datetime.parse(due["recurrency_end"]).then do |ends|
            unless ends.nil?
              parts << "UNTIL=#{ends.strftime('%Y%m%dT%H%M%SZ')}"
            end
          end
        end
      end
    end

    def rrule_days(weeks)
      weeks.to_s.split(",").map(&:to_i).select { |day| day.between?(1, 7) }
           .map { |day| RRULE_DAYS[day - 1] }.join(",")
    end

    def from_rrule(rule)
      rule.to_s.split(";").to_h { |part| part.split("=", 2).then { |(k, v)| [k, v.to_s] } }
          .then { |parts| rrule_hash(parts) }
    end

    def rrule_hash(parts)
      {
        "is_recurring"                 => true,
        "recurrency_type"              => RRULE_FREQ.key(parts["FREQ"].to_s) || "none",
        "recurrency_interval"          => [parts.fetch("INTERVAL", 1).to_i, 1].max,
        "recurrency_count"             => parts.fetch("COUNT", 0).to_i,
        "recurrency_weeks"             => rrule_weeks(parts["BYDAY"]),
        "recurrency_last_day_of_month" => parts["BYMONTHDAY"].to_s == "-1",
        "recurrency_end"               => rrule_until(parts["UNTIL"]),
      }
    end

    def rrule_weeks(byday)
      byday.to_s.split(",").filter_map { |day| RRULE_DAYS.index(day.strip.upcase) }
           .map { |index| index + 1 }.sort.join(",")
    end

    def rrule_until(until_value)
      if until_value.to_s.empty?
        ""
      else
        begin
          Time.parse(until_value.to_s).then { |time| Datetime.format(time) }
        rescue ArgumentError
          ""
        end
      end
    end
  end
end
