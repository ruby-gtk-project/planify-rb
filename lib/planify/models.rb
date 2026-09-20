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

    # Every table but Queue keys on `id`; Queue keys on `uuid`.
    def self.key = "id"

    # Boolean columns are stored as 1/0 integers, which is what SQLite and the
    # Vala build both expect.
    def self.flag(value) = value ? 1 : 0

    # Only Queue needs a column whose SQL name differs from its accessor.
    def self.column_for(name) = name.to_s

    def self.from_row(row)
      new.tap do |record|
        column_names.each do |column|
          record.public_send(:"#{column}=", row[column_for(column)])
        end
      end
    end

    def initialize(**attributes)
      self.class.column_names.each { |column| instance_variable_set(:"@#{column}", nil) }
      defaults.each { |column, value| public_send(:"#{column}=", value) }
      attributes.each { |column, value| public_send(:"#{column}=", value) }
      if id.nil?
        self.id = SecureRandom.uuid
      end
    end

    def defaults = {}

    def to_row = self.class.column_names.to_h { |column| [column, public_send(column)] }

    def key_value = public_send(self.class.key)

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

  # core/Objects/Source.vala. `data` is a JSON blob whose shape depends on the
  # source type — Todoist tokens or CalDAV credentials — which is why it is
  # kept as a hash rather than split into columns the schema does not have.
  class Source < Record
    columns :id,
      :source_type,
      :display_name,
      :added_at,
      :updated_at,
      :is_visible,
      :child_order,
      :sync_server,
      :last_sync,
      :data

    TODOIST_DEFAULTS = {
      "access_token"    => "",
      "sync_token"      => "*",
      "user_id"         => "",
      "user_image_id"   => "",
      "user_email"      => "",
      "user_name"       => "",
      "user_avatar"     => "",
      "user_is_premium" => false,
      "api_version"     => "v1",
    }.freeze

    CALDAV_DEFAULTS = {
      "server_url"        => "",
      "username"          => "",
      "password"          => "",
      "user_displayname"  => "",
      "user_email"        => "",
      "calendar_home_url" => "",
      "caldav_type"       => "nextcloud",
      "ignore_ssl"        => false,
      "use_deck"          => false,
      "deck_last_sync"    => "",
    }.freeze

    def defaults
      {
        source_type:  "local",
        display_name: "",
        added_at:     Time.now.iso8601,
        updated_at:   Time.now.iso8601,
        is_visible:   1,
        child_order:  0,
        sync_server:  0,
        last_sync:    "",
        data:         "{}",
      }
    end

    def local? = source_type == "local"

    def todoist? = source_type == "todoist"

    def caldav? = source_type == "caldav"

    def visible? = is_visible.to_i == 1

    def sync_server? = sync_server.to_i == 1

    def payload
      begin
        JSON.parse(data.to_s)
      rescue JSON::ParserError
        {}
      end.then { |parsed| parsed.is_a?(Hash) ? parsed : {} }
    end

    def payload_defaults
      if todoist?
        TODOIST_DEFAULTS
      elsif caldav?
        CALDAV_DEFAULTS
      else
        {}
      end
    end

    def [](key) = payload_defaults.merge(payload)[key]

    def []=(key, value)
      self.data = JSON.generate(payload_defaults.merge(payload).merge(key => value))
    end

    def merge_payload(values)
      self.data = JSON.generate(payload_defaults.merge(payload).merge(values))
    end

    def header_text = display_name.to_s

    def subheader_text
      if todoist?
        _("Todoist")
      elsif caldav?
        self["caldav_type"] == "nextcloud" ? _("Nextcloud") : _("CalDAV")
      else
        _("On This Computer")
      end
    end

    def user_displayname
      if todoist?
        self["user_name"].to_s
      elsif caldav?
        self["user_displayname"].to_s
      else
        ""
      end
    end

    def user_email
      if todoist?
        self["user_email"].to_s
      elsif caldav?
        self["user_email"].to_s
      else
        ""
      end
    end

    # A CalDAV home defaults to the conventional /calendars/<user>/ path when
    # discovery has not filled one in.
    def calendar_home_url
      self["calendar_home_url"].to_s.then do |url|
        if url.empty?
          File.join(
            server_url,
            "calendars",
            self["username"].to_s,
            "/",
          )
        else
          url.end_with?("/") ? url : "#{url}/"
        end
      end
    end

    def server_url
      self["server_url"].to_s.then { |url| url.end_with?("/") ? url : "#{url}/" }
    end

    # Nextcloud Deck hangs off the host, not the CalDAV path.
    def deck_base_url
      begin
        URI.parse(server_url).then do |uri|
          if uri.port && uri.port != uri.default_port
            port = ":#{uri.port}"
          else
            port = ""
          end
          "#{uri.scheme}://#{uri.host}#{port}/index.php/apps/deck/api/v1.0"
        end
      rescue URI::Error
        ""
      end
    end

    def icon_name
      if todoist?
        "todoist"
      elsif caldav?
        self["caldav_type"] == "nextcloud" ? "nextcloud" : "cloud-outline-thick-symbolic"
      else
        "computer-symbolic"
      end
    end

    # A Todoist source still on the v9 sync API has to re-authorise before it
    # can talk to the current one.
    def needs_migration?
      todoist? && ["", "v9"].include?(self["api_version"].to_s)
    end

    def projects = Store.instance.projects_by_source(id)
  end

  # The offline write queue: every change to a synced object is recorded here
  # and replayed when the server is next reachable.
  class QueueEntry < Record
    # The column is `object_id`; the accessor is not, because redefining
    # Object#object_id on a model breaks equality and identity everywhere.
    columns :uuid, :target_id, :query, :temp_id, :args, :source_id, :date_added

    COLUMN_ALIASES = { target_id: "object_id" }.freeze

    def self.column_for(name) = COLUMN_ALIASES.fetch(name, name.to_s)

    def self.table = "Queue"

    # The primary key is `uuid`, not `id`, so the generic writers need telling.
    def self.key = "uuid"

    def self.from_row(row)
      new(uuid: row["uuid"]).tap do |record|
        column_names.each do |column|
          record.public_send(:"#{column}=", row[column_for(column)])
        end
      end
    end

    def defaults
      {
        target_id:  "",
        query:      "",
        temp_id:    "",
        args:       "{}",
        source_id:  "",
        date_added: Time.now.iso8601,
      }
    end

    def id = uuid

    def id=(value)
      self.uuid = value
    end

    def arguments
      begin
        JSON.parse(args.to_s)
      rescue JSON::ParserError
        {}
      end
    end
  end

  # One recorded change to an item, written by the database triggers and read
  # back by the activity view.
  class ObjectEvent
    KEY_TITLES = {
      "content"     => -> { _("Name") },
      "description" => -> { _("Description") },
      "due"         => -> { _("Schedule") },
      "priority"    => -> { _("Priority") },
      "labels"      => -> { _("Labels") },
      "pinned"      => -> { _("Pinned") },
      "checked"     => -> { _("Completed") },
      "section"     => -> { _("Section") },
      "project"     => -> { _("Project") },
      "deadline"    => -> { _("Deadline") },
      "parent"      => -> { _("Parent task") },
    }.freeze

    def initialize(row)
      @row = row
    end

    attr_reader :row

    def event_type = row["event_type"]

    def event_date = Datetime.parse(row["event_date"])

    def target_id = row["object_id"]

    def key = row["object_key"]

    def old_value = row["object_old_value"].to_s

    def new_value = row["object_new_value"].to_s

    def inserted? = event_type == "insert"

    def title
      if inserted?
        _("Task created")
      else
        _("%s changed") % KEY_TITLES.fetch(key, -> { key.to_s }).call
      end
    end

    # Raw column values are not what a person wants to read: a due column is
    # JSON, a project is an id, a boolean is 0 or 1.
    def describe(value)
      case key
      when "due"      then describe_due(value)
      when "project"  then Store.instance.project(value)&.name.to_s
      when "section"  then Store.instance.section(value)&.name.to_s
      when "parent"   then Store.instance.item(value)&.content.to_s
      when "labels"   then describe_labels(value)
      when "priority" then Item.new(priority: value.to_i).priority_text
      when "pinned", "checked" then value.to_i == 1 ? _("Yes") : _("No")
      when "deadline" then Datetime.relative(Datetime.parse(value))
      else value
      end
    end

    def describe_due(value)
      begin
        JSON.parse(value.to_s)["date"].then { |date| Datetime.relative(Datetime.parse(date)) }
      rescue JSON::ParserError, NoMethodError
        ""
      end
    end

    def describe_labels(value)
      begin
        JSON.parse(value.to_s).filter_map { |id| Store.instance.label(id)&.name }.join(", ")
      rescue JSON::ParserError
        ""
      end
    end
  end
end
