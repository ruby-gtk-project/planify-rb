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
  end
end
