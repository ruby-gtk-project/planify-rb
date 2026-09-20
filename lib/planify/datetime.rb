# frozen_string_literal: true

module Planify
  # Ported from core/Utils/Datetime.vala. Dates cross the database as Todoist
  # strings — "2024-05-01" for an all-day date, "2024-05-01T09:30:00" once a
  # time is attached — and a zero time is what "no time" means, exactly as
  # Datetime.has_time decides it upstream.
  module Datetime
    module_function

    def parse(value)
      if value.nil? || value.to_s.empty?
        nil
      else
        begin
          Time.parse(value.to_s)
        rescue ArgumentError
          nil
        end
      end
    end

    def format(time)
      if has_time?(time)
        time.strftime("%FT%T")
      else
        time.strftime("%F")
      end
    end

    def has_time?(time)
      !time.nil? && !(time.hour.zero? && time.min.zero? && time.sec.zero?)
    end

    def same_day?(one, other) = !one.nil? && !other.nil? && one.to_date == other.to_date

    def today?(time) = same_day?(time, Time.now)

    def tomorrow?(time) = same_day?(time, Time.now + 86_400)

    def yesterday?(time) = same_day?(time, Time.now - 86_400)

    def overdue?(time) = !time.nil? && time.to_date < Date.today

    def this_week?(time)
      if time.nil?
        false
      else
        (time.to_date - Date.today).to_i.between?(0, 6)
      end
    end

    # "Today", "Tomorrow", "Yesterday", otherwise a localized date — with the
    # time appended when the due date carries one.
    def relative(time)
      if time.nil?
        ""
      else
        [date_word(time), clock(time)].compact.join(", ")
      end
    end

    def date_word(time)
      if today?(time)
        _("Today")
      elsif tomorrow?(time)
        _("Tomorrow")
      elsif yesterday?(time)
        _("Yesterday")
      else
        default_format(time)
      end
    end

    def clock(time)
      if has_time?(time)
        time.strftime(time_format)
      end
    end

    def time_format
      if Settings.clock_format_12h?
        "%I:%M %p"
      else
        "%H:%M"
      end
    end

    def default_format(time)
      if time.year == Time.now.year
        time.strftime(_("%b %e"))
      else
        time.strftime(_("%b %e, %Y"))
      end
    end

    # Planify labels each date with the calendar icon for its day of month, so
    # a due-date button shows "the 14th" rather than a generic calendar.
    def calendar_icon(time)
      if today?(time)
        "star-outline-thick-symbolic"
      else
        "month-symbolic"
      end
    end

    def days_left(time, show_today: false)
      days = (time.to_date - Date.today).to_i

      if days.zero?
        show_today ? _("Today") : ""
      elsif days.negative?
        n_("%d day ago", "%d days ago", days.abs) % days.abs
      else
        n_("%d day left", "%d days left", days) % days
      end
    end

    def strip_time(time) = Time.new(time.year, time.month, time.day)
  end
end
