# frozen_string_literal: true

module Planify
  module Services
    # src/Services/BackupManager.vala plus BackupExporter. The file is plain
    # JSON with a version stamp and every table in it, which is the same shape
    # the Vala build writes and reads.
    module BackupManager
      VERSION = 1
      INTERVAL = 24 * 60 * 60

      TABLES = {
        "sources"     => Source,
        "labels"      => Label,
        "projects"    => Project,
        "sections"    => Section,
        "items"       => Item,
        "reminders"   => Reminder,
        "attachments" => Attachment,
      }.freeze

      module_function

      def store = Store.instance

      # Automatic backups are checked once at startup and then daily; the
      # last run is remembered in settings so a restart does not re-run one.
      def init_auto_backup
        if Settings.get_boolean("backup-automatic")
          run_if_due
          GLib::Timeout.add_seconds(INTERVAL) do
            run_if_due
            true
          end
        end
      end

      def run_if_due
        Datetime.parse(Settings.get_string("backup-last-date")).then do |last|
          if last.nil? || (Time.now - last) >= INTERVAL
            create
            prune
          end
        end
      end

      def create(path = default_path)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(payload))
        Settings.set_string("backup-last-date", Time.now.iso8601)
        LogService.info("Backup", "wrote #{path}")
        path
      end

      def default_path
        File.join(Paths.backups, "planify-#{Time.now.strftime('%Y-%m-%d-%H%M%S')}.json")
      end

      def payload
        {
          "version"     => VERSION,
          "app_version" => Planify::VERSION,
          "date"        => Time.now.iso8601,
          "settings"    => settings_payload,
        }.merge(
          TABLES.keys.to_h do |table|
            [table, store.public_send(table).map { |record| stringify(record.to_row) }]
          end,
        )
      end

      def stringify(row) = row.to_h { |key, value| [key.to_s, value] }

      # Only the keys that describe the user's setup travel with a backup;
      # window geometry and dismissed-update markers do not.
      PORTABLE_SETTINGS = %w[
        appearance dark-mode system-appearance use-system-accent font-scale
        default-priority new-tasks-position start-week clock-format home-view
        show-tasks-count description-preview underline-completed-tasks
        smart-date-recognition always-show-details-sidebar labels-show-active-only
        show-today-completed enable-markdown-formatting task-complete-tone
        daily-task-goal weekly-task-goal use-dynamic-goal
      ].freeze

      def settings_payload
        PORTABLE_SETTINGS.to_h do |key|
          [key, Settings.settings.get_value(key).then { |value| value.value }]
        end
      rescue StandardError => error
        LogService.debug("Backup", "settings skipped: #{error.message}")
        {}
      end

      # Restoring replaces the database wholesale: a merge would have to
      # resolve id collisions between two independent histories, and upstream
      # does not attempt it either.
      def restore(path)
        JSON.parse(File.read(path)).then do |payload|
          validate!(payload)
          wipe
          TABLES.each do |table, model|
            payload.fetch(table, []).each { |row| store.database.insert(model.from_row(row)) }
          end
          restore_settings(payload["settings"])
          store.load
          LogService.info("Backup", "restored #{path}")
        end
      end

      def validate!(payload)
        unless payload.is_a?(Hash) && payload.key?("items") && payload.key?("projects")
          raise ArgumentError, _("That file is not a Planify backup.")
        end
      end

      def wipe
        %w[Attachments Reminders Items Sections Projects Labels Sources Queue CurTempIds]
          .each { |table| store.database.execute("DELETE FROM #{table}") }
      end

      def restore_settings(values)
        (values || {}).each do |key, value|
          begin
            Settings.settings.set_value(key, GLib::Variant.new(value))
          rescue StandardError
            LogService.debug("Backup", "could not restore setting #{key}")
          end
        end
      end

      def list
        Dir.glob(File.join(Paths.backups, "planify-*.json")).sort.reverse
      end

      # Automatic backups would otherwise accumulate forever.
      def prune(keep = 10)
        list.drop(keep).each { |path| File.delete(path) }
      end

      def describe(path)
        JSON.parse(File.read(path)).then do |payload|
          {
            date:     Datetime.parse(payload["date"]),
            version:  payload["app_version"].to_s,
            projects: payload.fetch("projects", []).size,
            items:    payload.fetch("items", []).size,
          }
        end
      rescue StandardError
        nil
      end
    end
  end
end
