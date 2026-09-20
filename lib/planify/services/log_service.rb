# frozen_string_literal: true

module Planify
  module Services
    # core/Services/LogService.vala. Writes to stderr and keeps a rolling
    # in-memory tail the error dialog shows, so a user reporting a sync failure
    # has something to paste.
    module LogService
      LEVELS = %i[debug info warn error].freeze
      TAIL = 500

      module_function

      def entries = @entries ||= []

      def level
        @level ||= ENV.fetch("PLANIFY_LOG_LEVEL", "info").downcase.to_sym
      end

      def level=(value)
        @level = value
      end

      LEVELS.each do |name|
        define_method(name) do |domain, message|
          write(name, domain, message)
        end
        module_function name
      end

      def write(severity, domain, message)
        if LEVELS.index(severity) >= LEVELS.index(level)
          entries.push([Time.now, severity, domain, message])
          entries.shift while entries.size > TAIL
          # Not Kernel#warn: this module defines its own `warn` severity,
          # which shadows it inside the module body.
          $stderr.puts(
            format_line(
              Time.now.strftime("%H:%M:%S"),
              severity,
              domain,
              message,
            ),
          )
        end
      end

      def format_line(stamp, severity, domain, message)
        "[#{stamp}] #{severity.to_s.upcase.ljust(5)} #{domain.to_s.ljust(10)} #{message}"
      end

      def tail(count = 100)
        entries.last(count).map do |(at, severity, domain, message)|
          format_line(
            at.strftime("%F %T"),
            severity,
            domain,
            message,
          )
        end.join("\n")
      end
    end
  end
end
