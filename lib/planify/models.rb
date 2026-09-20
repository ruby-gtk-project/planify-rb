# frozen_string_literal: true

module Planify
  # The database columns are the model. Each class knows the table it lives in
  # and the columns it owns; Store does the reading and writing. This is the
  # whole of core/Objects minus the sync plumbing — no from_json, no ical, no
  # per-object signal bus, because nothing local needs them.
  class Record
    def self.columns(*names)
      @columns = names
      attr_accessor(*names)
    end

    def self.column_names = @columns

    def self.table = name.split("::").last.concat("s")

    def self.from_row(row)
      new.tap do |record|
        column_names.each { |column| record.public_send(:"#{column}=", row[column.to_s]) }
      end
    end

    def initialize(**attributes)
      self.class.column_names.each { |column| instance_variable_set(:"@#{column}", nil) }
      defaults.each { |column, value| public_send(:"#{column}=", value) }
      attributes.each { |column, value| public_send(:"#{column}=", value) }
      @id ||= SecureRandom.uuid
    end

    def defaults = {}

    def to_row = self.class.column_names.to_h { |column| [column, public_send(column)] }

    def ==(other) = other.is_a?(self.class) && other.id == id

    alias eql? ==

    def hash = id.hash
  end

  class Label < Record
    columns :id, :name, :color, :item_order, :is_deleted, :is_favorite, :backend_type, :source_id

    def defaults
      {
        name:         "",
        color:        "blue",
        item_order:   0,
        is_deleted:   0,
        is_favorite:  0,
        backend_type: "local",
        source_id:    "local",
      }
    end

    def favorite? = is_favorite.to_i == 1
  end

  class Project < Record
    columns :id,
      :name,
      :color,
      :backend_type,
      :inbox_project,
      :team_inbox,
      :child_order,
      :is_deleted,
      :is_archived,
      :is_favorite,
      :shared,
      :view_style,
      :sort_order,
      :parent_id,
      :collapsed,
      :icon_style,
      :emoji,
      :show_completed,
      :description,
      :due_date,
      :inbox_section_hidded,
      :sync_id,
      :source_id,
      :calendar_url,
      :sorted_by,
      :calendar_source_uid,
      :markdown_setting

    def defaults
      {
        name:                 "",
        color:                "blue",
        backend_type:         "local",
        inbox_project:        0,
        team_inbox:           0,
        child_order:          0,
        is_deleted:           0,
        is_archived:          0,
        is_favorite:          0,
        shared:               0,
        view_style:           "list",
        sort_order:           0,
        parent_id:            "",
        collapsed:            1,
        icon_style:           "progress",
        emoji:                "🚀️",
        show_completed:       0,
        description:          "",
        due_date:             "",
        inbox_section_hidded: 0,
        sync_id:              "",
        source_id:            "local",
        calendar_url:         "",
        sorted_by:            0,
        calendar_source_uid:  "",
        markdown_setting:     "",
      }
    end

    def inbox? = inbox_project.to_i == 1

    def archived? = is_archived.to_i == 1

    def favorite? = is_favorite.to_i == 1

    def collapsed? = collapsed.to_i == 1

    def show_completed? = show_completed.to_i == 1

    def board? = view_style == "board"

    def emoji? = icon_style == "emoji"

    def subproject? = !parent_id.to_s.empty?

    def items = Store.instance.items_by_project(id)

    def sections = Store.instance.sections_by_project(id)

    def subprojects = Store.instance.subprojects_of(id)

    # The progress ring in the sidebar and the project header both read this.
    def percentage
      all = items.reject { |item| item.parent_id.to_s != "" }

      if all.empty?
        0.0
      else
        all.count(&:checked?).to_f / all.size
      end
    end
  end

  class Section < Record
    columns :id,
      :name,
      :archived_at,
      :added_at,
      :project_id,
      :section_order,
      :collapsed,
      :is_deleted,
      :is_archived,
      :color,
      :description,
      :hidded

    def defaults
      {
        name:          "",
        archived_at:   "",
        added_at:      Time.now.iso8601,
        project_id:    "",
        section_order: 0,
        collapsed:     0,
        is_deleted:    0,
        is_archived:   0,
        color:         "blue",
        description:   "",
        hidded:        0,
      }
    end

    def archived? = is_archived.to_i == 1

    def collapsed? = collapsed.to_i == 1

    def hidden? = hidded.to_i == 1

    def items = Store.instance.items_by_section(id)

    def project = Store.instance.project(project_id)
  end

  class Item < Record
    columns :id,
      :content,
      :description,
      :due,
      :added_at,
      :completed_at,
      :updated_at,
      :section_id,
      :project_id,
      :parent_id,
      :priority,
      :child_order,
      :checked,
      :is_deleted,
      :day_order,
      :collapsed,
      :pinned,
      :labels,
      :extra_data,
      :item_type,
      :calendar_event_uid,
      :deadline_date,
      :responsible_uid,
      :is_trash

    PRIORITY_1 = 4
    PRIORITY_2 = 3
    PRIORITY_3 = 2
    PRIORITY_4 = 1

    PRIORITY_COLORS = {
      PRIORITY_1 => "#ff7066",
      PRIORITY_2 => "#ff9914",
      PRIORITY_3 => "#5297ff",
    }.freeze

    def defaults
      {
        content:            "",
        description:        "",
        due:                "",
        added_at:           Time.now.iso8601,
        completed_at:       "",
        updated_at:         Time.now.iso8601,
        section_id:         "",
        project_id:         "",
        parent_id:          "",
        priority:           PRIORITY_4,
        child_order:        0,
        checked:            0,
        is_deleted:         0,
        day_order:          -1,
        collapsed:          0,
        pinned:             0,
        labels:             "[]",
        extra_data:         "",
        item_type:          "task",
        calendar_event_uid: "",
        deadline_date:      "",
        responsible_uid:    "",
        is_trash:           0,
      }
    end

    def checked? = checked.to_i == 1

    def pinned? = pinned.to_i == 1

    def collapsed? = collapsed.to_i == 1

    def trashed? = is_trash.to_i == 1

    def note? = item_type == "note"

    def project = Store.instance.project(project_id)

    def section = Store.instance.section(section_id)

    def subitems = Store.instance.subitems_of(id)

    def priority_color = PRIORITY_COLORS.fetch(priority.to_i, "@text_color")

    def priority_text
      {
        PRIORITY_1 => _("Priority 1: high"),
        PRIORITY_2 => _("Priority 2: medium"),
        PRIORITY_3 => _("Priority 3: low"),
      }.fetch(priority.to_i, _("Priority 4: none"))
    end

    def priority_icon
      {
        PRIORITY_1 => "flag-outline-thick-symbolic",
        PRIORITY_2 => "flag-outline-thick-symbolic",
        PRIORITY_3 => "flag-outline-thick-symbolic",
      }.fetch(priority.to_i, "flag-outline-thick-symbolic")
    end

    # `due` is a JSON blob upstream, because Todoist sends recurrence in it.
    # Locally only `date` and the recurrence fields are ever populated.
    def due_hash
      begin
        JSON.parse(due.to_s)
      rescue JSON::ParserError
        {}
      end.then { |parsed| parsed.is_a?(Hash) ? parsed : {} }
    end

    def due_date = Datetime.parse(due_hash["date"])

    def has_due? = !due_date.nil?

    def due_date=(time)
      if time.nil?
        self.due = ""
      else
        self.due = JSON.generate(due_hash.merge("date" => Datetime.format(time)))
      end
    end

    def recurring? = due_hash["is_recurring"] == true

    def deadline = Datetime.parse(deadline_date)

    def label_ids
      begin
        JSON.parse(labels.to_s)
      rescue JSON::ParserError
        []
      end.then { |parsed| parsed.is_a?(Array) ? parsed : [] }
    end

    def label_ids=(ids)
      self.labels = JSON.generate(ids)
    end

    def label_objects = label_ids.filter_map { |label_id| Store.instance.label(label_id) }
  end

  class Reminder < Record
    columns :id, :notify_uid, :item_id, :service, :type, :due, :mm_offset, :is_deleted

    def self.table = "Reminders"

    def defaults
      {
        notify_uid: 0,
        item_id:    "",
        service:    "local",
        type:       "absolute",
        due:        "",
        mm_offset:  0,
        is_deleted: 0,
      }
    end

    def due_date
      begin
        Datetime.parse(JSON.parse(due.to_s)["date"])
      rescue JSON::ParserError
        nil
      end
    end

    def due_date=(time)
      self.due = JSON.generate("date" => Datetime.format(time))
    end
  end

  class Attachment < Record
    columns :id, :item_id, :file_type, :file_name, :file_size, :file_path

    def defaults
      {
        item_id:   "",
        file_type: "",
        file_name: "",
        file_size: "",
        file_path: "",
      }
    end
  end
end
