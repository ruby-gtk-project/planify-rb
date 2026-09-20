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
        CREATE TABLE IF NOT EXISTS Sources (
            id                  TEXT PRIMARY KEY,
            source_type         TEXT NOT NULL,
            display_name        TEXT,
            added_at            TEXT,
            updated_at          TEXT,
            is_visible          INTEGER,
            child_order         INTEGER,
            sync_server         INTEGER,
            last_sync           TEXT,
            data                TEXT
        );
      SQL
      <<~SQL,
        CREATE TABLE IF NOT EXISTS Queue (
            uuid       TEXT PRIMARY KEY,
            object_id  TEXT,
            query      TEXT,
            temp_id    TEXT,
            args       TEXT,
            source_id  TEXT,
            date_added TEXT
        );
      SQL
      <<~SQL,
        CREATE TABLE IF NOT EXISTS CurTempIds (
            id          TEXT PRIMARY KEY,
            temp_id     TEXT,
            object      TEXT
        );
      SQL
      <<~SQL,
        CREATE TABLE IF NOT EXISTS OEvents (
            id                  INTEGER PRIMARY KEY AUTOINCREMENT,
            event_type          TEXT,
            event_date          DATETIME DEFAULT (datetime('now','localtime')),
            object_id           TEXT,
            object_type         TEXT,
            object_key          TEXT,
            object_old_value    TEXT,
            object_new_value    TEXT,
            parent_item_id      TEXT,
            parent_project_id   TEXT
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
      create_triggers
    end

    attr_reader :path


    # The change history the item detail pane shows is recorded by SQLite
    # itself, so an edit made anywhere — including by the Vala build against
    # the same file — lands in OEvents. Column, event key, and the value pair
    # each trigger records, matching create_triggers upstream.
    TRACKED_COLUMNS = {
      "content"       => "content",
      "description"   => "description",
      "due"           => "due",
      "priority"      => "priority",
      "labels"        => "labels",
      "pinned"        => "pinned",
      "checked"       => "checked",
      "section_id"    => "section",
      "project_id"    => "project",
      "deadline_date" => "deadline",
      "parent_id"     => "parent",
    }.freeze

    INSERT_TRIGGER = <<~SQL
      CREATE TRIGGER IF NOT EXISTS after_insert_item
      AFTER INSERT ON Items
      BEGIN
          INSERT OR IGNORE INTO OEvents (event_type, object_id,
              object_type, object_key, object_old_value, object_new_value, parent_project_id)
          VALUES ('insert', NEW.id, 'item', 'content', NEW.content,
              NEW.content, NEW.project_id);
      END;
    SQL

    def create_triggers
      @db.execute_batch(INSERT_TRIGGER)

      TRACKED_COLUMNS.each do |column, key|
        @db.execute_batch(<<~SQL)
          CREATE TRIGGER IF NOT EXISTS after_update_#{key}_item
          AFTER UPDATE ON Items
          FOR EACH ROW
          WHEN NEW.#{column} != OLD.#{column}
          BEGIN
              INSERT OR IGNORE INTO OEvents (event_type, object_id,
                  object_type, object_key, object_old_value, object_new_value, parent_project_id)
              VALUES ('update', NEW.id, 'item', '#{key}', OLD.#{column},
                  NEW.#{column}, NEW.project_id);
          END;
        SQL
      end
    end

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
        "Sources"  => { "sync_server" => "INTEGER", "last_sync" => "TEXT" },
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

    def query(sql, binds = []) = @db.execute(sql, binds)

    def execute(sql, binds = []) = @db.execute(sql, binds)

    # OEvents has an autoincrement id, so it is written directly rather than
    # through a Record.
    def events_for_item(item_id)
      @db.execute(
        "SELECT * FROM OEvents WHERE object_id = ? ORDER BY event_date DESC, id DESC",
        [item_id],
      )
    end

    def insert(record)
      record.class.column_names.then do |columns|
        @db.execute(
          "INSERT OR REPLACE INTO #{record.class.table} " \
          "(#{columns.map { |c| record.class.column_for(c) }.join(', ')}) " \
          "VALUES (#{(['?'] * columns.size).join(', ')})",
          columns.map { |column| record.public_send(column) },
        )
      end
    end

    # A real UPDATE, not INSERT OR REPLACE: the change-history triggers are
    # AFTER UPDATE, and a replace fires DELETE + INSERT instead, so the
    # history would silently never be written.
    def update(record)
      record.class.column_names.reject { |c| c.to_s == record.class.key }.then do |columns|
        @db.execute(
          "UPDATE #{record.class.table} SET " \
          "#{columns.map { |c| "#{record.class.column_for(c)} = ?" }.join(', ')} " \
          "WHERE #{record.class.key} = ?",
          columns.map { |column| record.public_send(column) } + [record.key_value],
        ).then do
          # A row that is not there yet — a record built before it was
          # inserted — is written rather than silently dropped.
          if @db.changes.zero?
            insert(record)
          end
        end
      end
    end

    def delete(record)
      @db.execute(
        "DELETE FROM #{record.class.table} WHERE #{record.class.key} = ?",
        [record.key_value],
      )
    end

    def empty?
      @db.execute("SELECT COUNT(*) AS count FROM Projects").dig(0, "count").to_i.zero?
    end

    def close = @db.close
  end
end
