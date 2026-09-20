# frozen_string_literal: true

module Planify
  # core/Services/Store.vala: the single place that owns the loaded objects and
  # the only writer to the database. Views subscribe to events rather than
  # reaching for the database, so a change made anywhere reaches every view.
  #
  # Upstream emits GObject signals; here a subscription is a block keyed by the
  # widget that registered it, so a destroyed view can drop all of its
  # subscriptions in one call.
  class Store
    EVENTS = %i[
      project_added project_updated project_deleted project_archived project_unarchived
      section_added section_updated section_deleted
      item_added item_updated item_deleted item_archived
      label_added label_updated label_deleted
      reminder_added reminder_deleted
      attachment_added attachment_deleted
      source_added source_updated source_deleted
      sync_started sync_finished sync_failed
    ].freeze

    def self.instance = @instance ||= new

    # Tests build their own store over a scratch database.
    def self.instance=(store)
      @instance = store
    end

    def initialize(database = Database.instance)
      @database = database
      @subscribers = Hash.new { |hash, key| hash[key] = [] }
      @projects = []
      @sections = []
      @items = []
      @labels = []
      @reminders = []
      @attachments = []
      @sources = []
      @pending_writes = {}
    end

    attr_reader :database,
      :projects,
      :sections,
      :items,
      :labels,
      :reminders,
      :attachments,
      :sources

    def load
      @labels = @database.all("Labels").map { |row| Label.from_row(row) }
      @projects = @database.all("Projects").map { |row| Project.from_row(row) }
      @sections = @database.all("Sections").map { |row| Section.from_row(row) }
      @items = @database.all("Items").map { |row| Item.from_row(row) }
      @reminders = @database.all("Reminders").map { |row| Reminder.from_row(row) }
      @attachments = @database.all("Attachments").map { |row| Attachment.from_row(row) }
      @sources = @database.all("Sources").map { |row| Source.from_row(row) }
    end

    # --- events ---------------------------------------------------------

    def on(event, owner: nil, &block)
      @subscribers[event] << [owner, block]
    end

    def unsubscribe(owner)
      @subscribers.each_value { |list| list.reject! { |(subscriber, _)| subscriber.equal?(owner) } }
    end

    def emit(event, *args)
      @subscribers[event].dup.each { |(_, block)| block.call(*args) }
    end

    # --- lookups --------------------------------------------------------

    def project(id) = @projects.find { |project| project.id == id }

    def section(id) = @sections.find { |section| section.id == id }

    def item(id) = @items.find { |item| item.id == id }

    def label(id) = @labels.find { |label| label.id == id }

    def label_by_name(name) = @labels.find { |label| label.name == name }

    def reminder(id) = @reminders.find { |reminder| reminder.id == id }

    def source(id) = @sources.find { |source| source.id == id }

    def local_source = @sources.find(&:local?)

    def visible_sources = @sources.select(&:visible?).sort_by { |s| s.child_order.to_i }

    def synced_sources = @sources.reject(&:local?)

    def projects_by_source(source_id)
      @projects.select { |project| project.source_id == source_id && !project.archived? }
    end

    def root_projects_by_source(source_id)
      projects_by_source(source_id).select { |project| project.parent_id.to_s.empty? && !project.inbox? }
                                   .sort_by { |project| project.child_order.to_i }
    end

    # A task the UI is mid-edit on must not be overwritten by a sync response
    # carrying the state the server had before that edit reached it.
    def pending_write?(item_id) = @pending_writes.key?(item_id)

    def with_pending_write(item_id)
      @pending_writes[item_id] = true
      yield
    ensure
      @pending_writes.delete(item_id)
    end

    def inbox_project = project(Settings.get_string("local-inbox-project-id")) || @projects.find(&:inbox?)

    def active_projects
      @projects.reject { |project| project.archived? || project.inbox? }
    end

    def root_projects
      active_projects.select { |project| project.parent_id.to_s.empty? }
                     .sort_by(&:child_order)
    end

    def subprojects_of(project_id)
      @projects.select { |project| project.parent_id == project_id && !project.archived? }
               .sort_by(&:child_order)
    end

    def archived_projects = @projects.select(&:archived?)

    def favorites
      (@projects.select { |project| project.favorite? && !project.archived? } +
        @labels.select(&:favorite?)).sort_by { |record| record.respond_to?(:child_order) ? record.child_order.to_i : 0 }
    end

    def sections_by_project(project_id)
      @sections.select { |section| section.project_id == project_id && !section.archived? }
               .sort_by { |section| section.section_order.to_i }
    end

    def items_by_project(project_id)
      @items.select { |item| item.project_id == project_id && !item.trashed? }
    end

    # A project's loose items — the ones not filed under any section.
    def items_by_project_unsectioned(project_id)
      items_by_project(project_id)
        .select { |item| item.section_id.to_s.empty? && item.parent_id.to_s.empty? }
        .sort_by { |item| item.child_order.to_i }
    end

    def items_by_section(section_id)
      @items.select { |item| item.section_id == section_id && item.parent_id.to_s.empty? && !item.trashed? }
            .sort_by { |item| item.child_order.to_i }
    end

    def subitems_of(item_id)
      @items.select { |item| item.parent_id == item_id && !item.trashed? }
            .sort_by { |item| item.child_order.to_i }
    end

    def items_by_label(label_id)
      pending.select { |item| item.label_ids.include?(label_id) }
    end

    def reminders_by_item(item_id) = @reminders.select { |reminder| reminder.item_id == item_id }

    def attachments_by_item(item_id) = @attachments.select { |a| a.item_id == item_id }

    # --- the built-in filters -------------------------------------------

    def pending
      @items.reject { |item| item.checked? || item.trashed? || archived_project?(item) }
    end

    def archived_project?(item)
      project(item.project_id).then { |project| project.nil? || project.archived? }
    end

    def today_items
      pending.select do |item|
        Datetime.today?(item.due_date) || Datetime.overdue?(item.due_date)
      end.sort_by { |item| [item.due_date.to_i, -item.priority.to_i] }
    end

    def overdue_items = pending.select { |item| Datetime.overdue?(item.due_date) }

    def scheduled_items
      pending.select { |item| item.has_due? && !Datetime.overdue?(item.due_date) }
             .sort_by { |item| item.due_date.to_i }
    end

    def pinboard_items = pending.select(&:pinned?)

    def unlabeled_items = pending.select { |item| item.label_ids.empty? }

    def labeled_items = pending.reject { |item| item.label_ids.empty? }

    def repeating_items = pending.select(&:recurring?)

    def priority_items(priority) = pending.select { |item| item.priority.to_i == priority }

    def completed_items
      @items.select { |item| item.checked? && !item.trashed? }
            .sort_by { |item| item.completed_at.to_s }
            .reverse
    end

    def all_items = pending

    def anytime_items = pending.reject(&:has_due?)

    def tomorrow_items = pending.select { |item| Datetime.tomorrow?(item.due_date) }

    def trashed_items = @items.select(&:trashed?)

    def search(term)
      term.downcase.then do |needle|
        {
          items:    pending.select { |item| item.content.to_s.downcase.include?(needle) },
          projects: active_projects.select { |project| project.name.to_s.downcase.include?(needle) },
          labels:   @labels.select { |label| label.name.to_s.downcase.include?(needle) },
        }
      end
    end

    # --- writes ---------------------------------------------------------

    def insert_source(source)
      @sources << source
      @database.insert(source)
      emit(:source_added, source)
      source
    end

    def update_source(source)
      source.updated_at = Time.now.iso8601
      @database.update(source)
      emit(:source_updated, source)
      source
    end

    # Removing an account takes its projects, sections, items and queued
    # writes with it; nothing of it is left to sync against a server the user
    # has disconnected.
    def delete_source(source)
      projects_by_source(source.id).each { |project| delete_project(project) }
      @labels.select { |label| label.source_id == source.id }.each { |label| delete_label(label) }
      Services::SyncQueue.clear(source.id)
      @sources.delete(source)
      @database.delete(source)
      emit(:source_deleted, source)
    end

    def insert_project(project, queue: true)
      @projects << project
      @database.insert(project)
      if queue
        enqueue_add("project_add", project, project.source_id)
      end
      emit(:project_added, project)
      project
    end

    def update_project(project, queue: true)
      @database.update(project)
      if queue
        enqueue(

          "project_update",

          project,

          project.source_id,
          Services::Todoist.project_args(project).merge("id" => project.id),
        )
      end
      emit(:project_updated, project)
      project
    end

    # Deleting a project takes its sections, its items and its subprojects with
    # it — SQLite cascades the sections, the rest is ours to sweep.
    def delete_project(project, queue: true)
      # Same reason as for items: the calendar URL is needed after the record
      # is gone.
      if queue
        enqueue(

          "project_delete",

          project,

          project.source_id,
          "id"           => project.id,
          "calendar_url" => project.calendar_url.to_s,
        )
      end
      subprojects_of(project.id).each { |child| delete_project(child, queue: false) }
      @items.reject! { |item| item.project_id == project.id }
      @sections.reject! { |section| section.project_id == project.id }
      @projects.delete(project)
      @database.delete(project)
      emit(:project_deleted, project)
    end

    def archive_project(project)
      project.is_archived = 1
      items_by_project(project.id).each do |item|
        item.is_deleted = 1
      end
      @database.update(project)
      emit(:project_archived, project)
    end

    def unarchive_project(project)
      project.is_archived = 0
      @database.update(project)
      emit(:project_unarchived, project)
    end

    def insert_section(section, queue: true)
      @sections << section
      @database.insert(section)
      if queue
        enqueue_add("section_add", section, source_id_of(section))
      end
      emit(:section_added, section)
      section
    end

    def update_section(section, queue: true)
      @database.update(section)
      if queue
        enqueue(

          "section_update",

          section,

          source_id_of(section),
          Services::Todoist.section_args(section).merge("id" => section.id),
        )
      end
      emit(:section_updated, section)
      section
    end

    def delete_section(section, queue: true)
      if queue
        enqueue(
          "section_delete",
          section,
          source_id_of(section),
          "id" => section.id,
        )
      end
      items_by_section(section.id).each { |item| delete_item(item, queue: false) }
      @sections.delete(section)
      @database.delete(section)
      emit(:section_deleted, section)
    end

    def insert_item(item, queue: true)
      @items << item
      @database.insert(item)
      if queue
        enqueue_add("item_add", item, source_id_of(item))
      end
      emit(:item_added, item)
      item
    end

    def update_item(item, queue: true)
      item.updated_at = Time.now.iso8601
      @database.update(item)
      if queue
        enqueue(

          "item_update",

          item,

          source_id_of(item),
          Services::Todoist.item_args(item).merge("id" => item.id),
        )
      end
      emit(:item_updated, item)
      item
    end

    # Completing a recurring task moves it forward instead of closing it, which
    # is what upstream's complete_item does with the recurrency block.
    def complete_item(item, checked)
      if checked && item.recurring?
        advance_recurrency(item)
      else
        if checked
          item.checked = 1
          item.completed_at = Time.now.iso8601
        else
          item.checked = 0
          item.completed_at = ""
        end
        subitems_of(item.id).each do |subitem|
          subitem.checked = item.checked
          subitem.completed_at = item.completed_at
          @database.update(subitem)
          emit(:item_updated, subitem)
        end
        update_item(item, queue: false)
        enqueue(

          checked ? "item_complete" : "item_uncomplete",

          item,

          source_id_of(item),
          "id" => item.id,
        )
      end
    end

    def advance_recurrency(item)
      Recurrency.next_date(item).then do |next_date|
        if next_date.nil?
          item.checked = 1
          item.completed_at = Time.now.iso8601
          update_item(item)
        else
          item.due_date = next_date
          update_item(item)
        end
      end
    end

    def delete_item(item, queue: true)
      # The record is gone by the time the queue is flushed, so the entry
      # carries everything the server call will need to address it.
      if queue
        enqueue(
          "item_delete",
          item,
          source_id_of(item),
          delete_args(item),
        )
      end
      subitems_of(item.id).each { |subitem| delete_item(subitem, queue: false) }
      @items.delete(item)
      @database.delete(item)
      emit(:item_deleted, item)
    end

    # The trash is a soft delete, so "Undo" in the toast can put it back.
    def trash_item(item)
      item.is_trash = 1
      @database.update(item)
      emit(:item_deleted, item)
    end

    def restore_item(item)
      item.is_trash = 0
      @database.update(item)
      emit(:item_added, item)
    end

    def insert_label(label, queue: true)
      @labels << label
      @database.insert(label)
      if queue
        enqueue_add("label_add", label, label.source_id)
      end
      emit(:label_added, label)
      label
    end

    def update_label(label, queue: true)
      @database.update(label)
      if queue
        enqueue(

          "label_update",

          label,

          label.source_id,
          Services::Todoist.label_args(label).merge("id" => label.id),
        )
      end
      emit(:label_updated, label)
      label
    end

    def delete_label(label, queue: true)
      if queue
        enqueue(
          "label_delete",
          label,
          label.source_id,
          "id" => label.id,
        )
      end

      @items.each do |item|
        if item.label_ids.include?(label.id)
          item.label_ids = item.label_ids - [label.id]
          @database.update(item)
          emit(:item_updated, item)
        end
      end

      @labels.delete(label)
      @database.delete(label)
      emit(:label_deleted, label)
    end

    def insert_reminder(reminder)
      @reminders << reminder
      @database.insert(reminder)
      emit(:reminder_added, reminder)
      reminder
    end

    def delete_reminder(reminder)
      @reminders.delete(reminder)
      @database.delete(reminder)
      emit(:reminder_deleted, reminder)
    end

    def insert_attachment(attachment)
      @attachments << attachment
      @database.insert(attachment)
      emit(:attachment_added, attachment)
      attachment
    end

    def delete_attachment(attachment)
      @attachments.delete(attachment)
      @database.delete(attachment)
      emit(:attachment_deleted, attachment)
    end


    # --- sync plumbing --------------------------------------------------

    # Sections and items carry no source of their own; they belong to whatever
    # their project belongs to.
    def source_id_of(record)
      project(record.project_id).then { |owner| owner.nil? ? "" : owner.source_id.to_s }
    end

    def delete_args(item)
      {
        "id"         => item.id,
        "ical_url"   => caldav_url(item),
        "backend"    => project(item.project_id)&.backend_type.to_s,
        "project_id" => item.project_id.to_s,
        "section_id" => item.section_id.to_s,
      }
    end

    def caldav_url(item)
      begin
        JSON.parse(item.extra_data.to_s)["ical_url"].to_s
      rescue JSON::ParserError
        ""
      end
    end

    def enqueue(query, record, source_id, args = {})
      Services::SyncQueue.add(
        query,
        record,
        source_id,
        args,
      )
    end

    # A create needs a temp_id so the server's answer can be matched back to
    # the row that is still carrying a local id.
    def enqueue_add(query, record, source_id)
      if Services::SyncQueue.synced?(source_id)
        SecureRandom.uuid.then do |temp_id|
          Services::SyncQueue.add_temp_id(record.id, temp_id, query.split("_").first)
          Services::SyncQueue.add(

            query,

            record,

            source_id,

            add_args(query, record),
            temp_id: temp_id,
          )
        end
      end
    end

    ADD_ARGS = {
      "project_add" => ->(record) { Services::Todoist.project_args(record) },
      "section_add" => ->(record) { Services::Todoist.section_args(record) },
      "item_add"    => ->(record) { Services::Todoist.item_args(record) },
      "label_add"   => ->(record) { Services::Todoist.label_args(record) },
    }.freeze

    def add_args(query, record)
      ADD_ARGS.fetch(query).call(record).tap do |args|
        if args.key?("project_id")
          args["project_id"] = temp_or_real(record.project_id)
        end
      end
    end

    # A child created before its parent reached the server references the
    # parent's temp_id, which the server resolves in the same batch.
    def temp_or_real(id)
      Services::SyncQueue.temp_id(id).then { |temp| temp.nil? ? id : temp }
    end

    # Todoist assigns the real id; every row that pointed at the local one has
    # to be moved, including the rows still waiting in the queue.
    def update_project_id(old_id, new_id)
      project(old_id).then do |record|
        unless record.nil?
          reassign(record, old_id, new_id) do
            retarget(@sections, :project_id, [old_id, new_id])
            retarget(@items, :project_id, [old_id, new_id])
            retarget(@projects, :parent_id, [old_id, new_id])
          end
        end
      end
    end

    def update_section_id(old_id, new_id)
      section(old_id).then do |record|
        unless record.nil?
          reassign(record, old_id, new_id) do
            retarget(@items, :section_id, [old_id, new_id])
          end
        end
      end
    end

    def update_item_id(old_id, new_id)
      item(old_id).then do |record|
        unless record.nil?
          reassign(record, old_id, new_id) do
            retarget(@items, :parent_id, [old_id, new_id])
            retarget(@reminders, :item_id, [old_id, new_id])
            retarget(@attachments, :item_id, [old_id, new_id])
          end
        end
      end
    end

    # Every row that pointed at the local id now points at the server one.
    def retarget(records, field, ids)
      records.each do |record|
        if record.public_send(field) == ids.first
          record.public_send(:"#{field}=", ids.last)
        end
      end
    end

    def reassign(record, old_id, new_id)
      @database.delete(record)
      record.id = new_id
      yield
      @database.insert(record)
      @database.execute("UPDATE Queue SET object_id = ? WHERE object_id = ?", [new_id, old_id])
      persist_all
      emit(:"#{record.class.name.split('::').last.downcase}_updated", record)
    end

    # After an id rewrite the in-memory graph is ahead of the file; write the
    # affected tables back rather than reasoning about which rows moved.
    def persist_all
      (@projects + @sections + @items + @reminders + @attachments)
        .each { |record| @database.update(record) }
    end

    # --- change history --------------------------------------------------

    def events_for_item(item_id)
      @database.events_for_item(item_id).map { |row| ObjectEvent.new(row) }
    end

    # --- sync entry point ------------------------------------------------

    def sync_all(&done)
      synced_sources.select(&:sync_server?).then do |sources|
        if sources.empty?
          done&.call(false, _("No accounts are set up to sync."))
        else
          sources.each { |source| sync_source(source, &done) }
        end
      end
    end

    def sync_source(source, &done)
      if source.todoist?
        Services::Todoist.sync(source, &done)
      elsif source.caldav?
        Services::CalDAV.sync(source, &done)
      else
        done&.call(false, nil)
      end
    end

    # --- first run ------------------------------------------------------

    def empty? = @projects.empty?

    def next_child_order(project_id, section_id)
      if section_id.to_s.empty?
        items_by_project_unsectioned(project_id)
      else
        items_by_section(section_id)
      end.map { |item| item.child_order.to_i }.max.then { |max| max.nil? ? 0 : max + 1 }
    end
  end
end
