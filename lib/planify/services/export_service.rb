# frozen_string_literal: true

module Planify
  module Services
    # src/Services/ExportService.vala. A project as plain text, Markdown or
    # CSV, for pasting somewhere that is not a task manager.
    module ExportService
      FORMATS = {
        "markdown" => { label: -> { _("Markdown") }, extension: "md" },
        "text"     => { label: -> { _("Plain Text") }, extension: "txt" },
        "csv"      => { label: -> { _("CSV") }, extension: "csv" },
      }.freeze

      module_function

      def store = Store.instance

      def export(project, format)
        case format
        when "markdown" then markdown(project)
        when "csv" then csv(project)
        else text(project)
        end
      end

      def markdown(project)
        ["# #{project.name}", ""].tap do |lines|
          unless project.description.to_s.empty?
            lines << project.description.to_s
          end
          unless project.description.to_s.empty?
            lines << ""
          end

          loose(project).each { |item| lines.concat(markdown_item(item, 0)) }

          store.sections_by_project(project.id).each do |section|
            lines << ""
            lines << "## #{section.name}"
            lines << ""
            store.items_by_section(section.id).each { |item| lines.concat(markdown_item(item, 0)) }
          end
        end.join("\n").concat("\n")
      end

      def markdown_item(item, depth)
        ["#{'  ' * depth}- [#{item.checked? ? 'x' : ' '}] #{item.content}#{markdown_suffix(item)}"]
          .tap do |lines|
          unless item.description.to_s.strip.empty?
            item.description.to_s.lines.each { |line| lines << "#{'  ' * (depth + 1)}#{line.strip}" }
          end

          item.subitems.each { |subitem| lines.concat(markdown_item(subitem, depth + 1)) }
        end
      end

      def markdown_suffix(item)
        [
          item.has_due? ? " 📅 #{Datetime.date_word(item.due_date)}" : nil,
          item.label_objects.map { |label| " @#{label.name}" }.join,
        ].compact.join
      end

      def text(project)
        ["#{project.name}", "=" * project.name.to_s.length, ""].tap do |lines|
          loose(project).each { |item| lines.concat(text_item(item, 0)) }

          store.sections_by_project(project.id).each do |section|
            lines << ""
            lines << section.name.to_s
            lines << "-" * section.name.to_s.length
            store.items_by_section(section.id).each { |item| lines.concat(text_item(item, 0)) }
          end
        end.join("\n").concat("\n")
      end

      def text_item(item, depth)
        ["#{'    ' * depth}[#{item.checked? ? 'x' : ' '}] #{item.content}"].tap do |lines|
          item.subitems.each { |subitem| lines.concat(text_item(subitem, depth + 1)) }
        end
      end

      HEADERS = %w[content description section due deadline priority labels completed].freeze

      def csv(project)
        [csv_row(HEADERS)].tap do |rows|
          (loose(project) + store.sections_by_project(project.id)
                                 .flat_map { |section| store.items_by_section(section.id) })
            .each { |item| rows << csv_row(csv_values(item)) }
        end.join("\n").concat("\n")
      end

      def csv_values(item)
        [
          item.content.to_s,
          item.description.to_s,
          item.section&.name.to_s,
          item.has_due? ? Datetime.format(item.due_date) : "",
          item.deadline_date.to_s,
          item.priority_text,
          item.label_objects.map(&:name).join(";"),
          item.checked? ? "true" : "false",
        ]
      end

      # RFC 4180: quote every field, double the quotes inside it.
      def csv_row(values)
        values.map { |value| "\"#{value.to_s.gsub('"', '""')}\"" }.join(",")
      end

      def loose(project) = store.items_by_project_unsectioned(project.id)

      def suggested_filename(project, format)
        "#{project.name.to_s.gsub(/[^\w-]+/, '-').downcase}." \
          "#{FORMATS.fetch(format).fetch(:extension)}"
      end
    end
  end
end
