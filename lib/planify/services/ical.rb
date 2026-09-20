# frozen_string_literal: true

module Planify
  module Services
    # The iCalendar side of CalDAV. Only VTODO is handled, and only the
    # properties Planify stores, which is what keeps this small enough to be
    # worth doing directly rather than pulling in a calendar library.
    module Ical
      PRODID = "-//Planify//Ruby GTK4//EN"

      # RFC 5545 folds long lines at 75 octets, continuing with a leading
      # space or tab. Unfolding has to happen before anything is parsed.
      def self.unfold(text)
        text.gsub(/\r\n/, "\n").gsub(/\n[ \t]/, "")
      end

      def self.fold(line)
        line.scan(/.{1,73}/m).join("\r\n ")
      end

      # Property values escape comma, semicolon, backslash and newline.
      def self.escape(value)
        value.to_s.gsub("\\", "\\\\\\\\").gsub("\n", "\\n").gsub(",", "\\,").gsub(";", "\;")
      end

      def self.unescape(value)
        value.to_s.gsub("\\n", "\n").gsub("\\N", "\n")
             .gsub("\\,", ",").gsub("\;", ";").gsub("\\\\", "\\")
      end

      # Each line is NAME;PARAM=VALUE:VALUE. Parameters matter for dates,
      # where VALUE=DATE marks an all-day date and TZID names a zone.
      def self.parse_line(line)
        line.split(":", 2).then do |(head, value)|
          head.to_s.split(";").then do |parts|
            {
              name:   parts.first.to_s.upcase,
              params: parts.drop(1).to_h { |p| p.split("=", 2).then { |(k, v)| [k.to_s.upcase, v.to_s] } },
              value:  value.to_s,
            }
          end
        end
      end

      # Returns the properties of the first VTODO in the document.
      def self.parse_todo(text)
        properties(unfold(text.to_s)).then do |all|
          all.select { |property| property[:component] == "VTODO" }
        end
      end

      def self.properties(text)
        [].tap do |collected|
          stack = []

          text.each_line do |raw|
            raw.strip.then do |line|
              if line.empty?
                next
              end

              parse_line(line).then do |property|
                if property[:name] == "BEGIN"
                  stack.push(property[:value].upcase)
                elsif property[:name] == "END"
                  stack.pop
                else
                  collected << property.merge(component: stack.last)
                end
              end
            end
          end
        end
      end

      def self.value_of(properties, name)
        properties.find { |property| property[:name] == name }&.fetch(:value)
      end

      def self.property(properties, name)
        properties.find { |property| property[:name] == name }
      end

      # CalDAV priorities run 1 (highest) to 9; Todoist's run 4 (highest) to 1.
      # The mapping is Item.update_from_ical's, inverted for the way out.
      def self.priority_from_ical(value)
        value.to_i.then do |priority|
          if priority <= 0 then Item::PRIORITY_4
          elsif priority <= 4 then Item::PRIORITY_1
          elsif priority == 5 then Item::PRIORITY_2
          elsif priority <= 9 then Item::PRIORITY_3
          else Item::PRIORITY_4
          end
        end
      end

      def self.priority_to_ical(priority)
        {
          Item::PRIORITY_1 => 1,
          Item::PRIORITY_2 => 5,
          Item::PRIORITY_3 => 9,
        }.fetch(priority.to_i, 0)
      end

      # "20300501T093000Z", "20300501T093000" or "20300501" for an all-day.
      def self.parse_datetime(property)
        if property.nil? || property[:value].to_s.empty?
          nil
        else
          property[:value].strip.then do |value|
            begin
              if property[:params]["VALUE"] == "DATE" || value.length == 8
                Time.new(value[0, 4].to_i, value[4, 2].to_i, value[6, 2].to_i)
              elsif value.end_with?("Z")
                Time.parse("#{value[0, 8]}T#{value[9, 6]}Z").localtime
              else
                Time.parse("#{value[0, 8]}T#{value[9, 6]}")
              end
            rescue ArgumentError
              nil
            end
          end
        end
      end

      def self.format_datetime(time)
        if Datetime.has_time?(time)
          ["DATE-TIME", time.strftime("%Y%m%dT%H%M%S")]
        else
          ["DATE", time.strftime("%Y%m%d")]
        end
      end

      def self.format_utc(time) = time.utc.strftime("%Y%m%dT%H%M%SZ")

      # --- reading ---------------------------------------------------------

      def self.to_item(text, project_id)
        parse_todo(text).then do |properties|
          Item.new(
            id:         value_of(properties, "UID").to_s,
            project_id: project_id,
          ).tap { |item| assign(item, properties) }
        end
      end

      def self.assign(item, properties)
        item.tap do |record|
          record.content = unescape(value_of(properties, "SUMMARY"))
          record.description = unescape(value_of(properties, "DESCRIPTION"))
          record.priority = priority_from_ical(value_of(properties, "PRIORITY"))
          record.parent_id = value_of(properties, "RELATED-TO").to_s
          record.added_at = assign_time(properties, "CREATED", item.added_at)
          record.updated_at = assign_time(properties, "LAST-MODIFIED", item.updated_at)
          assign_status(record, properties)
          assign_due(record, properties)
          assign_deadline(record, properties)
          assign_labels(record, properties)
          assign_order(record, properties)
        end
      end

      def self.assign_time(properties, name, fallback)
        parse_datetime(property(properties, name)).then do |time|
          time.nil? ? fallback : time.iso8601
        end
      end

      # COMPLETED carries the timestamp; STATUS says whether it is done, and
      # a server that sets only one of the two still has to be understood.
      def self.assign_status(item, properties)
        value_of(properties, "STATUS").to_s.upcase.then do |status|
          parse_datetime(property(properties, "COMPLETED")).then do |completed|
            done = status == "COMPLETED" || !completed.nil?
            item.checked = Record.flag(done)
            item.completed_at = completion_stamp(done, completed)
          end
        end
      end

      # A server may mark a task done without saying when; "now" is the only
      # honest answer available, and an undone task has no stamp at all.
      def self.completion_stamp(done, completed)
        if !completed.nil?
          completed.iso8601
        elsif done
          Time.now.iso8601
        else
          ""
        end
      end

      def self.assign_due(item, properties)
        parse_datetime(property(properties, "DUE")).then do |due|
          if due.nil?
            item.due = ""
          else
            item.due_date = due
            merge_recurrence(item, properties)
          end
        end
      end

      def self.merge_recurrence(item, properties)
        value_of(properties, "RRULE").then do |rule|
          unless rule.to_s.empty?
            item.due = JSON.generate(item.due_hash.merge(Recurrency.from_rrule(rule)))
          end
        end
      end

      # Tasks.org and Nextcloud both put the deadline in X-APPLE-SORT-ORDER-
      # free custom fields; Planify writes and reads X-PLANIFY-DEADLINE.
      def self.assign_deadline(item, properties)
        parse_datetime(property(properties, "X-PLANIFY-DEADLINE")).then do |deadline|
          if deadline.nil?
            item.deadline_date = ""
          else
            item.deadline_date = Datetime.format(deadline)
          end
        end
      end

      def self.assign_labels(item, properties)
        value_of(properties, "CATEGORIES").to_s.split(",").map { |name| unescape(name).strip }
              .reject(&:empty?).then do |names|
          item.label_ids = names.map do |name|
            Store.instance.label_by_name(name).then do |label|
              if label.nil?
                Store.instance.insert_label(Label.new(name: name, color: Palette.random)).id
              else
                label.id
              end
            end
          end
        end
      end

      def self.assign_order(item, properties)
        value_of(properties, "X-APPLE-SORT-ORDER").then do |order|
          unless order.nil?
            item.child_order = order.to_i
          end
        end
      end

      # --- writing ---------------------------------------------------------

      def self.from_item(item)
        lines(item).map { |line| fold(line) }.join("\r\n").concat("\r\n")
      end

      def self.lines(item)
        [
          "BEGIN:VCALENDAR",
          "VERSION:2.0",
          "PRODID:#{PRODID}",
          "BEGIN:VTODO",
          "UID:#{item.id}",
          "DTSTAMP:#{format_utc(Time.now)}",
          "SUMMARY:#{escape(item.content)}",
        ].tap do |out|
          unless item.description.to_s.empty?
            out << "DESCRIPTION:#{escape(item.description)}"
          end
          out.concat(due_lines(item))
          out.concat(deadline_lines(item))
          out.concat(status_lines(item))
          unless priority_to_ical(item.priority).zero?
            out << "PRIORITY:#{priority_to_ical(item.priority)}"
          end
          unless item.parent_id.to_s.empty?
            out << "RELATED-TO:#{item.parent_id}"
          end
          out.concat(label_lines(item))
          out << "X-APPLE-SORT-ORDER:#{item.child_order.to_i}"
          out << "CREATED:#{created_stamp(item)}"
          out << "LAST-MODIFIED:#{format_utc(Time.now)}"
          out << "END:VTODO"
          out << "END:VCALENDAR"
        end
      end

      def self.created_stamp(item)
        Datetime.parse(item.added_at).then { |time| format_utc(time.nil? ? Time.now : time) }
      end

      def self.due_lines(item)
        if item.has_due?
          format_datetime(item.due_date).then do |(kind, value)|
            ["DUE;VALUE=#{kind}:#{value}"].tap do |out|
              Recurrency.to_rrule(item.due_hash).then do |rule|
                unless rule.nil?
                  out << "RRULE:#{rule}"
                end
              end
            end
          end
        else
          []
        end
      end

      def self.deadline_lines(item)
        if item.deadline.nil?
          []
        else
          format_datetime(item.deadline).then do |(kind, value)|
            ["X-PLANIFY-DEADLINE;VALUE=#{kind}:#{value}"]
          end
        end
      end

      def self.status_lines(item)
        if item.checked?
          Datetime.parse(item.completed_at).then do |completed|
            [
              "STATUS:COMPLETED",
              "PERCENT-COMPLETE:100",
              "COMPLETED:#{format_utc(completed.nil? ? Time.now : completed)}",
            ]
          end
        else
          ["STATUS:NEEDS-ACTION", "PERCENT-COMPLETE:0"]
        end
      end

      def self.label_lines(item)
        item.label_objects.map(&:name).then do |names|
          names.empty? ? [] : ["CATEGORIES:#{names.map { |n| escape(n) }.join(',')}"]
        end
      end
    end
  end
end
