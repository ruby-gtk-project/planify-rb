# frozen_string_literal: true

module Planify
  module Services
    # core/Services/CalendarEvents. The system's own calendars, read through
    # Evolution Data Server. There are no Ruby gems for libecal or
    # libedataserver, so both are loaded straight from their typelibs — which
    # is why the dev shell puts them on GI_TYPELIB_PATH and LD_LIBRARY_PATH.
    module CalendarEvents
      Event = Struct.new(

        :uid,

        :summary,

        :location,

        :start_time,

        :end_time,

        :all_day,
        :source_uid,

        :source_name,

        :color,

        keyword_init: true,
      ) do
        def duration = end_time - start_time

        def range = (start_time.to_date..(end_time - 1).to_date)
      end

      module_function

      # Loading is attempted once and its failure remembered: a system without
      # EDS is normal, and the feature simply stays off rather than raising on
      # every view refresh.
      def available?
        if @available.nil?
          @available = load_bindings
        end

        @available
      end

      def load_bindings
        %w[EDataServer ECal ICalGLib].all? { |namespace| GI.load(namespace) }
      end

      def enabled? = Settings.get_boolean("calendar-enabled") && available?

      def disabled_sources = Settings.settings.get_strv("calendar-sources-disabled").to_a

      def registry
        @registry ||= ::EDataServer::SourceRegistry.new(nil)
      rescue StandardError => error
        LogService.warn("Calendar", "no source registry: #{error.message}")
        nil
      end

      # Only calendars the user has ticked in their desktop, minus the ones
      # turned off in Planify's own preferences.
      def sources
        if registry.nil?
          []
        else
          registry.list_sources(::EDataServer::SOURCE_EXTENSION_CALENDAR)
                  .select { |source| selected?(source) }
        end
      rescue StandardError => error
        LogService.warn("Calendar", "listing failed: #{error.message}")
        []
      end

      def all_sources
        registry.nil? ? [] : registry.list_sources(::EDataServer::SOURCE_EXTENSION_CALENDAR)
      rescue StandardError
        []
      end

      def selected?(source)
        source.enabled? &&
          source.get_extension(::EDataServer::SOURCE_EXTENSION_CALENDAR).selected? &&
          !disabled_sources.include?(source.uid)
      rescue StandardError
        false
      end

      def enable_source(uid, enabled)
        (disabled_sources - [uid]).then do |remaining|
          Settings.settings.set_strv(
            "calendar-sources-disabled",
            enabled ? remaining : remaining + [uid],
          )
        end
      end

      def source_color(source)
        source.get_extension(::EDataServer::SOURCE_EXTENSION_CALENDAR).color.to_s
      rescue StandardError
        Palette::DEFAULT
      end

      def client_for(source)
        clients[source.uid] ||= ::ECal::Client.connect_sync(
          source,
          ::ECal::ClientSourceType::EVENTS,
          30,
          nil,
        )
      rescue StandardError => error
        LogService.warn("Calendar", "#{source.display_name}: #{error.message}")
        nil
      end

      def clients = @clients ||= {}

      # S-expression query, the only thing ECal takes; the range is inclusive
      # of the whole end day.
      def query_for(from, to)
        "(occur-in-time-range? (make-time \"%s\") (make-time \"%s\"))" % [
          from.utc.strftime("%Y%m%dT%H%M%SZ"),
          (to + 86_400).utc.strftime("%Y%m%dT%H%M%SZ"),
        ]
      end

      def events_between(from, to)
        if !enabled?
          []
        else
          sources.flat_map { |source| events_for(source, from, to) }
                 .sort_by { |event| [event.all_day ? 0 : 1, event.start_time] }
        end
      end

      def events_for(source, from, to)
        client_for(source).then do |client|
          if client.nil?
            []
          else
            client.get_object_list_as_comps_sync(query_for(from, to), nil).then do |result|
              components(result).filter_map { |component| to_event(component, source) }
            end
          end
        end
      rescue StandardError => error
        LogService.debug("Calendar", "query failed: #{error.message}")
        []
      end

      # The binding hands back either the component list or a [ok, list] pair
      # depending on the introspection annotation; both shapes are accepted.
      def components(result)
        if result.is_a?(Array) && result.first.is_a?(TrueClass)
          Array(result[1])
        else
          Array(result)
        end
      end

      def to_event(component, source)
        Event.new(
          uid:         component.uid.to_s,
          summary:     component.summary.to_s,
          location:    safe(component, :location).to_s,
          start_time:  component_time(component, :dtstart),
          end_time:    component_time(component, :dtend),
          all_day:     all_day?(component),
          source_uid:  source.uid,
          source_name: source.display_name.to_s,
          color:       source_color(source),
        ).then { |event| event.start_time.nil? ? nil : finish(event) }
      rescue StandardError => error
        LogService.debug("Calendar", "component skipped: #{error.message}")
        nil
      end

      # An event with no end is treated as ending when it starts, which is
      # what a zero-length appointment means.
      def finish(event)
        event.tap do |record|
          if record.end_time.nil?
            record.end_time = record.start_time
          end
        end
      end

      def safe(component, method)
        component.public_send(method)
      rescue StandardError
        nil
      end

      def component_time(component, which)
        safe(component, which).then do |value|
          value.nil? ? nil : ical_to_time(value)
        end
      end

      # ECal hands back an ECal::ComponentDateTime wrapping an ICalGLib::Time;
      # the fields are read directly rather than through as_timet, so an
      # all-day date does not pick up a spurious midnight-UTC offset.
      def ical_to_time(value)
        ical_time(value).then do |time|
          if time.nil?
            nil
          elsif time.is_date?
            Time.new(time.year, time.month, time.day)
          else
            Time.new(
              time.year,
              time.month,
              time.day,
              time.hour,
              time.minute,
              time.second,
            )
          end
        end
      rescue StandardError
        nil
      end

      def ical_time(value)
        if value.respond_to?(:value)
          value.value
        else
          value
        end
      end

      def all_day?(component)
        ical_time(safe(component, :dtstart)).then do |time|
          !time.nil? && time.respond_to?(:is_date?) && time.is_date?
        end
      rescue StandardError
        false
      end

      def events_on(date)
        Time.new(date.year, date.month, date.day).then do |start|
          events_between(start, start).select { |event| event.range.cover?(date) }
        end
      end
    end
  end
end
