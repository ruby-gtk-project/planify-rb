# frozen_string_literal: true

module Planify
  module Services
    # src/Services/TimeMonitor.vala. A single timeout armed for the next
    # midnight. When it fires, every view that shows "today" is stale and
    # every reminder has to reconsider whether it is due, so both are told.
    module TimeMonitor
      module_function

      def init
        arm
      end

      def arm
        stop
        @timeout = GLib::Timeout.add(seconds_until_midnight * 1000) do
          fire
          false
        end
      end

      def stop
        unless @timeout.nil?
          GLib::Source.remove(@timeout)
        end
        @timeout = nil
      end

      # A second past midnight, so the date has actually rolled over by the
      # time anything reads Time.now.
      def seconds_until_midnight
        Time.now.then do |now|
          [(Time.new(now.year, now.month, now.day) + 86_401) - now, 1].max.to_i
        end
      end

      def fire
        LogService.info("TimeMonitor", "day rolled over")
        EventBus.emit(:day_changed)
        Notification.refresh
        arm
      end
    end
  end
end
