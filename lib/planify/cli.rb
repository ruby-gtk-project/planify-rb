# frozen_string_literal: true

require "optparse"

module Planify
  # cli/. The headless half of Planify: add, list and update tasks, list
  # projects, and take a backup, against the same database the window uses.
  # A running window is told about a change over DBus so it refreshes.
  module CLI
    COMMANDS = {
      "add"      => -> { _("Add a task") },
      "list"     => -> { _("List tasks") },
      "projects" => -> { _("List projects") },
      "update"   => -> { _("Update a task") },
      "backup"   => -> { _("Write a backup") },
      "help"     => -> { _("Show this help") },
    }.freeze

    module_function

    def store = @store ||= Store.new(Database.new).tap(&:load)

    def run(argv)
      argv.first.to_s.then do |command|
        if command.empty? || command == "help" || %w[-h --help].include?(command)
          usage
          0
        elsif COMMANDS.key?(command)
          dispatch(command, argv.drop(1))
        else
          warn(_("Unknown command: %s") % command)
          usage
          1
        end
      end
    end

    def dispatch(command, argv)
      public_send(:"run_#{command}", argv)
    rescue OptionParser::ParseError => error
      warn(error.message)
      1
    rescue StandardError => error
      warn(_("Error: %s") % error.message)
      1
    end

    def usage
      puts _("Usage: planify-cli <command> [options]")
      puts
      COMMANDS.each { |name, description| puts format("  %-10s %s", name, description.call) }
      puts
      puts _("Run 'planify-cli <command> --help' for a command's options.")
    end

    # --- add --------------------------------------------------------------

    def run_add(argv)
      options = { priority: Item::PRIORITY_4 }

      parser("add").tap do |parser|
        parser.on("-c", "--content CONTENT", _("Task name")) { |v| options[:content] = v }
        parser.on("-d", "--description TEXT") { |v| options[:description] = v }
        parser.on("-p", "--project NAME") { |v| options[:project] = v }
        parser.on("--project-id ID") { |v| options[:project_id] = v }
        parser.on("-s", "--section NAME") { |v| options[:section] = v }
        parser.on("--section-id ID") { |v| options[:section_id] = v }
        parser.on("--parent-id ID") { |v| options[:parent_id] = v }
        parser.on("--priority N", Integer, _("1 is highest, 4 is none")) do |v|
          options[:priority] = priority_from_cli(v)
        end
        parser.on("--due DATE", _("YYYY-MM-DD, or today/tomorrow")) { |v| options[:due] = v }
        parser.on("-l", "--labels LIST", _("Comma-separated")) { |v| options[:labels] = v }
        parser.on("--pinned") { options[:pinned] = true }
        parser.parse!(argv)
      end

      # The remaining words are the task name, so `planify-cli add buy milk`
      # works without quoting.
      options[:content] ||= argv.join(" ")
      create(options)
    end

    def create(options)
      if options[:content].to_s.strip.empty?
        warn(_("A task needs a name."))
        1
      else
        resolve_project(options).then do |(project, section)|
          build_item(options, project, section).then do |item|
            store.insert_item(item)
            notify_window(item)
            puts _("Added: %s") % item.content
            0
          end
        end
      end
    end

    def build_item(options, project, section)
      Item.new(
        content:     options[:content].to_s.strip,
        description: options[:description].to_s,
        project_id:  project.id,
        section_id:  section&.id.to_s,
        parent_id:   options[:parent_id].to_s,
        priority:    options[:priority],
        child_order: store.next_child_order(project.id, section&.id.to_s),
      ).tap do |item|
        item.due_date = parse_due(options[:due])
        item.label_ids = label_ids(options[:labels])
        item.pinned = Record.flag(options[:pinned])
      end
    end

    # The CLI takes Todoist's user-facing numbering (1 highest); the stored
    # value runs the other way.
    def priority_from_cli(value) = { 1 => 4, 2 => 3, 3 => 2 }.fetch(value.to_i, 1)

    def priority_to_cli(value) = { 4 => 1, 3 => 2, 2 => 3 }.fetch(value.to_i, 4)

    def parse_due(value)
      case value.to_s.strip.downcase
      when "" then nil
      when "today" then Datetime.strip_time(Time.now)
      when "tomorrow" then Datetime.strip_time(Time.now + 86_400)
      else Datetime.parse(value)
      end
    end

    def label_ids(list)
      list.to_s.split(",").map(&:strip).reject(&:empty?).map do |name|
        store.label_by_name(name).then do |label|
          if label.nil?
            store.insert_label(Label.new(name: name, color: Palette.random)).id
          else
            label.id
          end
        end
      end
    end

    def resolve_project(options)
      find_project(options).then do |project|
        if project.nil?
          raise ArgumentError, _("No such project.")
        end

        [project, find_section(project, options)]
      end
    end

    def find_project(options)
      if !options[:project_id].to_s.empty?
        store.project(options[:project_id])
      elsif !options[:project].to_s.empty?
        store.projects.find { |p| p.name.to_s.casecmp?(options[:project].to_s) }
      else
        store.inbox_project
      end
    end

    def find_section(project, options)
      if !options[:section_id].to_s.empty?
        store.section(options[:section_id])
      elsif !options[:section].to_s.empty?
        store.sections_by_project(project.id)
             .find { |s| s.name.to_s.casecmp?(options[:section].to_s) }
      end
    end

    # --- list -------------------------------------------------------------

    def run_list(argv)
      options = {}

      parser("list").tap do |parser|
        parser.on("-p", "--project NAME") { |v| options[:project] = v }
        parser.on("--project-id ID") { |v| options[:project_id] = v }
        parser.on("-a", "--all", _("Include completed tasks")) { options[:all] = true }
        parser.parse!(argv)
      end

      listed(options).then do |items|
        items.each { |item| puts format_item(item) }
        if items.empty?
          puts(_("No tasks."))
        end
        0
      end
    end

    def listed(options)
      base_items(options).then do |items|
        if options[:all]
          items
        else
          items.reject(&:checked?)
        end
      end
    end

    def base_items(options)
      if options[:project_id].to_s.empty? && options[:project].to_s.empty?
        store.items.reject(&:trashed?)
      else
        find_project(options).then do |project|
          if project.nil?
            raise ArgumentError, _("No such project.")
          end

          store.items_by_project(project.id)
        end
      end
    end

    def format_item(item)
      [
        item.checked? ? "[x]" : "[ ]",
        item.id.to_s[0, 8],
        item.content.to_s,
        item.has_due? ? "(#{Datetime.format(item.due_date)})" : nil,
        item.priority.to_i == Item::PRIORITY_4 ? nil : "P#{priority_to_cli(item.priority)}",
        item.label_objects.map { |label| "@#{label.name}" }.join(" ").then { |l| l.empty? ? nil : l },
      ].compact.join(" ")
    end

    def run_projects(_argv)
      store.projects.reject(&:archived?).each do |project|
        puts format(
          "%-10s %-30s %s",
          project.id.to_s[0, 8],
          project.name.to_s,
          n_("%d task", "%d tasks", store.items_by_project(project.id).size) %
            store.items_by_project(project.id).size,
        )
      end
      0
    end

    # --- update -----------------------------------------------------------

    def run_update(argv)
      options = {}

      parser("update").tap do |parser|
        parser.on("-i", "--id ID", _("Task id, or its first characters")) { |v| options[:id] = v }
        parser.on("-c", "--content CONTENT") { |v| options[:content] = v }
        parser.on("-d", "--description TEXT") { |v| options[:description] = v }
        parser.on("-p", "--project NAME") { |v| options[:project] = v }
        parser.on("-s", "--section NAME") { |v| options[:section] = v }
        parser.on("--priority N", Integer) { |v| options[:priority] = priority_from_cli(v) }
        parser.on("--due DATE") { |v| options[:due] = v }
        parser.on("-l", "--labels LIST") { |v| options[:labels] = v }
        parser.on("--complete") { options[:checked] = true }
        parser.on("--uncomplete") { options[:checked] = false }
        parser.on("--pin") { options[:pinned] = true }
        parser.on("--unpin") { options[:pinned] = false }
        parser.parse!(argv)
      end

      options[:id] ||= argv.shift
      apply_update(options)
    end

    # An abbreviated id is accepted, and an ambiguous one is refused rather
    # than guessed at.
    def find_item(prefix)
      store.items.select { |item| item.id.to_s.start_with?(prefix.to_s) }.then do |matches|
        if matches.empty?
          raise ArgumentError, _("No such task.")
        end
        if matches.size > 1
          raise ArgumentError, _("That id matches more than one task.")
        end

        matches.first
      end
    end

    def apply_update(options)
      if options[:id].to_s.empty?
        warn(_("Which task? Pass --id."))
        1
      else
        find_item(options[:id]).then do |item|
          assign_updates(item, options)
          store.update_item(item)
          notify_window(item)
          puts _("Updated: %s") % item.content
          0
        end
      end
    end

    def assign_updates(item, options)
      unless options[:content].nil?
        item.content = options[:content]
      end
      unless options[:description].nil?
        item.description = options[:description]
      end
      unless options[:priority].nil?
        item.priority = options[:priority]
      end
      unless options[:due].nil?
        item.due_date = parse_due(options[:due])
      end
      unless options[:labels].nil?
        item.label_ids = label_ids(options[:labels])
      end
      unless options[:pinned].nil?
        item.pinned = Record.flag(options[:pinned])
      end
      move_item(item, options)
      complete_item(item, options)
    end

    def move_item(item, options)
      unless options[:project].to_s.empty?
        resolve_project(options).then do |(project, section)|
          item.project_id = project.id
          item.section_id = section&.id.to_s
        end
      end
    end

    def complete_item(item, options)
      unless options[:checked].nil?
        item.checked = Record.flag(options[:checked])

        if options[:checked]
          item.completed_at = Time.now.iso8601
        else
          item.completed_at = ""
        end
      end
    end

    # --- backup -----------------------------------------------------------

    def run_backup(argv)
      options = {}

      parser("backup").tap do |parser|
        parser.on("-o", "--output PATH") { |v| options[:output] = v }
        parser.parse!(argv)
      end

      Services::BackupManager.create(options[:output] || Services::BackupManager.default_path)
                             .then do |path|
        puts _("Backup written to %s") % path
        0
      end
    end

    # --- plumbing ---------------------------------------------------------

    def parser(command)
      OptionParser.new do |parser|
        parser.banner = _("Usage: planify-cli %s [options]") % command
      end
    end

    # A running window is told over the bus, so a task added from a terminal
    # appears without a restart. No window is not an error.
    def notify_window(item)
      Gio::DBusConnection.default.then do |connection|
        connection.call_sync(
          Services::DBusServer::BUS_NAME,
          "/io/github/alainm23/planify",
          "org.gtk.Actions",
          "Activate",
          GLib::Variant.new(["add-item", [GLib::Variant.new(item.id.to_s)], {}]),
          nil,
          :none,
          200,
        )
      end
    rescue StandardError => error
      Services::LogService.debug("CLI", "no running window: #{error.message}")
    end
  end
end
