# frozen_string_literal: true

module Planify
  module Services
    # src/Services/MigrateFromPlanner.vala. Planify was called Planner; an
    # install from before the rename keeps its database under the old id and
    # is imported once, on first run, rather than being left behind.
    module MigrateFromPlanner
      OLD_IDS = %w[
        com.github.alainm23.planner
        com.github.alainm23.planify
        io.github.alainm23.planner
      ].freeze

      module_function

      def store = Store.instance

      def data_home
        ENV.fetch("XDG_DATA_HOME", File.join(Dir.home, ".local", "share"))
      end

      def candidates
        OLD_IDS.map { |id| File.join(data_home, id, "database.db") }.select { |p| File.exist?(p) }
      end

      def pending? = store.empty? && !candidates.empty?

      # The old schema is the same schema — the rename did not change it — so
      # the rows are copied table by table rather than translated.
      def migrate(path = candidates.first)
        if path.nil?
          false
        else
          copy_from(Database.new(path))
          LogService.info("Migrate", "imported #{path}")
          true
        end
      rescue StandardError => error
        LogService.error("Migrate", "import failed: #{error.message}")
        false
      end

      TABLES = {
        "Sources"     => Source,
        "Labels"      => Label,
        "Projects"    => Project,
        "Sections"    => Section,
        "Items"       => Item,
        "Reminders"   => Reminder,
        "Attachments" => Attachment,
      }.freeze

      def copy_from(old)
        TABLES.each do |table, model|
          old.all(table).each do |row|
            begin
              store.database.insert(model.from_row(row))
            rescue StandardError => error
              LogService.debug("Migrate", "skipped a #{table} row: #{error.message}")
            end
          end
        end

        store.load
      end
    end
  end
end
