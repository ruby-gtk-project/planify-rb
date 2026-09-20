# frozen_string_literal: true

module Planify
  module Services
    # The offline write queue. Every change to an object belonging to a synced
    # source is recorded here first, so an edit made with no network still
    # reaches the server on the next sync, in the order it was made.
    #
    # Todoist's sync API takes the queue as a batch of commands and answers per
    # uuid; CalDAV has no batch, so its backend replays the entries one at a
    # time. Both read the same rows.
    module SyncQueue
      module_function

      def store = Store.instance

      def database = store.database

      # Nothing is queued for a local-only object — there is no server to tell.
      def synced?(source_id)
        store.source(source_id).then { |source| !source.nil? && !source.local? }
      end

      def add(query, object, source_id, args = {}, temp_id: nil)
        if synced?(source_id)
          QueueEntry.new(
            target_id: object.id,
            query:     query,
            temp_id:   temp_id.to_s,
            args:      JSON.generate(args),
            source_id: source_id,
          ).tap do |entry|
            database.insert(entry)
            LogService.debug("SyncQueue", "queued #{query} for #{object.id}")
          end
        end
      end

      def all(source_id)
        database.query(
          "SELECT * FROM Queue WHERE source_id = ? ORDER BY date_added ASC",
          [source_id],
        ).map { |row| QueueEntry.from_row(row) }
      end

      def remove(entry)
        database.execute("DELETE FROM Queue WHERE uuid = ?", [entry.uuid])
      end

      def clear(source_id)
        database.execute("DELETE FROM Queue WHERE source_id = ?", [source_id])
      end

      def size(source_id) = all(source_id).size

      # Todoist assigns real ids server-side, so a locally created object holds
      # a temporary id until the response maps it. CurTempIds remembers which
      # local ids are still provisional.
      def add_temp_id(object_id, temp_id, kind)
        database.execute(
          "INSERT OR REPLACE INTO CurTempIds (id, temp_id, object) VALUES (?, ?, ?)",
          [object_id, temp_id, kind],
        )
      end

      def temp_id(object_id)
        database.query("SELECT temp_id FROM CurTempIds WHERE id = ?", [object_id])
                .dig(0, "temp_id")
      end

      def temp_id?(object_id) = !temp_id(object_id).nil?

      def remove_temp_id(object_id)
        database.execute("DELETE FROM CurTempIds WHERE id = ?", [object_id])
      end
    end
  end
end
