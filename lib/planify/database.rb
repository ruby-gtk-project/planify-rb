# frozen_string_literal: true

module Planify
  # The schema is Planify's own, verbatim from core/Services/Database.vala, so
  # an existing ~/.local/share/io.github.alainm23.planify/database.db opens
  # here untouched and the Vala build can still read what this writes.
  class Database
    SCHEMA = [
      <<~SQL,
        CREATE TABLE IF NOT EXISTS Labels (
            id              TEXT PRIMARY KEY,
            name            TEXT,
            color           TEXT,
            item_order      INTEGER,
            is_deleted      INTEGER,
            is_favorite     INTEGER,
            backend_type    TEXT,
            source_id       TEXT,
            CONSTRAINT unique_label UNIQUE (name)
        );
      SQL
      <<~SQL,
        CREATE TABLE IF NOT EXISTS Projects (
            id                      TEXT PRIMARY KEY,
            name                    TEXT NOT NULL,
            color                   TEXT,
            backend_type            TEXT,
            inbox_project           INTEGER,
            team_inbox              INTEGER,
            child_order             INTEGER,
            is_deleted              INTEGER,
            is_archived             INTEGER,
            is_favorite             INTEGER,
            shared                  INTEGER,
            view_style              TEXT,
            sort_order              INTEGER,
            parent_id               TEXT,
            collapsed               INTEGER,
            icon_style              TEXT,
            emoji                   TEXT,
            show_completed          INTEGER,
            description             TEXT,
            due_date                TEXT,
            inbox_section_hidded    INTEGER,
            sync_id                 TEXT,
            source_id               TEXT,
            calendar_url            TEXT,
            sorted_by               TEXT,
            calendar_source_uid     TEXT,
            markdown_setting        TEXT
        );
      SQL
      <<~SQL,
        CREATE TABLE IF NOT EXISTS Sections (
            id              TEXT PRIMARY KEY,
            name            TEXT,
            archived_at     TEXT,
            added_at        TEXT,
            project_id      TEXT,
            section_order   INTEGER,
            collapsed       INTEGER,
            is_deleted      INTEGER,
            is_archived     INTEGER,
            color           TEXT,
            description     TEXT,
            hidded          INTEGER,
            FOREIGN KEY (project_id) REFERENCES Projects (id) ON DELETE CASCADE ON UPDATE CASCADE
        );
      SQL
      <<~SQL,
        CREATE TABLE IF NOT EXISTS Items (
            id                  TEXT PRIMARY KEY,
            content             TEXT NOT NULL,
            description         TEXT,
            due                 TEXT,
            added_at            TEXT,
            completed_at        TEXT,
            updated_at          TEXT,
            section_id          TEXT,
            project_id          TEXT,
            parent_id           TEXT,
            priority            INTEGER,
            child_order         INTEGER,
            checked             INTEGER,
            is_deleted          INTEGER,
            day_order           INTEGER,
            collapsed           INTEGER,
            pinned              INTEGER,
            labels              TEXT,
            extra_data          TEXT,
            item_type           TEXT,
            calendar_event_uid  TEXT,
            deadline_date       TEXT,
            responsible_uid     TEXT,
            is_trash            INTEGER DEFAULT 0
        );
      SQL
      <<~SQL,
        CREATE TABLE IF NOT EXISTS Reminders (
            id                  TEXT PRIMARY KEY,
            notify_uid          INTEGER,
            item_id             TEXT,
            service             TEXT,
            type                TEXT,
            due                 TEXT,
            mm_offset           INTEGER,
            is_deleted          INTEGER,
            FOREIGN KEY (item_id) REFERENCES Items (id) ON DELETE CASCADE ON UPDATE CASCADE
        );
      SQL
      <<~SQL,
        CREATE TABLE IF NOT EXISTS Attachments (
            id              TEXT PRIMARY KEY,
            item_id         TEXT,
            file_type       TEXT,
            file_name       TEXT,
            file_size       TEXT,
            file_path       TEXT,
            FOREIGN KEY (item_id) REFERENCES Items (id) ON DELETE CASCADE ON UPDATE CASCADE
        );
      SQL
    ].freeze

    def self.instance = @instance ||= new

    # Only the tests pass a path; everything else opens the user's database.
    def initialize(path = Paths.database)
      @path = path
      FileUtils.mkdir_p(File.dirname(path))
      @db = SQLite3::Database.new(path)
      @db.results_as_hash = true
      @db.execute("PRAGMA foreign_keys = ON")
      SCHEMA.each { |sql| @db.execute_batch(sql) }
      migrate
    end

    attr_reader :path

    # Older Planify databases predate some columns. Adding them back is the
    # whole of what upstream's patch_database does that matters locally.
    def migrate
      {
        "Items"    => {
          "is_trash"           => "INTEGER DEFAULT 0",
          "deadline_date"      => "TEXT",
          "responsible_uid"    => "TEXT",
          "item_type"          => "TEXT",
          "calendar_event_uid" => "TEXT",
          "pinned"             => "INTEGER",
        },
        "Projects" => {
          "markdown_setting"    => "TEXT",
          "sorted_by"           => "TEXT",
          "calendar_source_uid" => "TEXT",
          "due_date"            => "TEXT",
        },
        "Sections" => { "description" => "TEXT", "hidded" => "INTEGER", "color" => "TEXT" },
      }.each do |table, columns|
        existing = @db.table_info(table).map { |column| column["name"] }

        columns.each do |column, type|
          unless existing.include?(column)
            @db.execute("ALTER TABLE #{table} ADD COLUMN #{column} #{type}")
          end
        end
      end
    end

    # Upstream shows an error page when the file is not a usable database.
    def healthy?
      begin
        @db.execute("PRAGMA integrity_check").dig(0, "integrity_check") == "ok"
      rescue SQLite3::Exception
        false
      end
    end

    def all(table) = @db.execute("SELECT * FROM #{table}")

    def insert(record)
      columns = record.class.column_names
      @db.execute(
        "INSERT OR REPLACE INTO #{record.class.table} (#{columns.join(', ')}) " \
        "VALUES (#{(['?'] * columns.size).join(', ')})",
        columns.map { |column| record.public_send(column) },
      )
    end

    alias update insert

    def delete(record)
      @db.execute("DELETE FROM #{record.class.table} WHERE id = ?", [record.id])
    end

    def empty?
      @db.execute("SELECT COUNT(*) AS count FROM Projects").dig(0, "count").to_i.zero?
    end

    def close = @db.close
  end
end
