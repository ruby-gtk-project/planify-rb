# frozen_string_literal: true

module Planify
  # Layouts/Sidebar.vala: the filter tiles, the favourites header and the
  # project tree under "On This Computer". Upstream draws the filters either as
  # a FlowBox of tiles or a ListBox of rows depending on `filters-list-view`;
  # both are here and the setting switches between them live.
  class Sidebar
    FILTERS = [
      { key: "inbox", title: -> { _("Inbox") }, icon: "mailbox-symbolic", color: "#3584e4" },
      { key: "today", title: -> { _("Today") }, icon: "star-outline-thick-symbolic", color: "#33d17a" },
      { key: "scheduled", title: -> { _("Scheduled") }, icon: "month-symbolic", color: "#9141ac" },
      { key: "labels", title: -> { _("Labels") }, icon: "tag-outline-symbolic", color: "#ff7800" },
      { key: "pinboard", title: -> { _("Pinboard") }, icon: "pin-symbolic", color: "#e01b24" },
    ].freeze

    def initialize(window)
      @window = window
      @project_rows = {}
      @favorite_rows = {}
      @filter_rows = {}
    end

    attr_reader :window

    def build
      @build ||= scrolled.tap do |scroll|
        scroll.child = content_box

        content_box.tap do |box|
          box.append(filters_revealer)
          box.append(favorites_header)
          box.append(favorites_listbox)
          box.append(projects_header)
          box.append(projects_listbox)

          filters_revealer.child = filters_container

          projects_header.tap do |header|
            header.append(projects_label)
            header.append(add_project_button)

            add_project_button.signal_connect("clicked") { window.new_project }
          end

          favorites_header.append(favorites_label)

          projects_listbox.signal_connect("row-activated") do |_, row|
            @project_rows.key(row).then do |project_id|
              store.project(project_id).then do |project|
                unless project.nil?
                  window.show_project(project)
                end
              end
            end
          end

          favorites_listbox.signal_connect("row-activated") do |_, row|
            @favorite_rows.key(row).then { |id| activate_favorite(id) }
          end
        end
      end
    end

    def store = Store.instance

    def init
      build_filters
      reload_favorites
      reload_projects
      subscribe
      filters_revealer.reveal_child = true
    end

    def subscribe
      %i[project_added project_updated project_deleted project_archived project_unarchived]
        .each { |event| store.on(event, owner: self) { reload_projects } }

      %i[project_updated label_updated label_added label_deleted project_deleted]
        .each { |event| store.on(event, owner: self) { reload_favorites } }

      %i[item_added item_updated item_deleted]
        .each { |event| store.on(event, owner: self) { refresh_counts } }

      Settings.changed("filters-list-view") { build_filters }
      Settings.changed("show-tasks-count") { refresh_counts }
    end

    # --- filters --------------------------------------------------------

    def build_filters
      @filter_rows = {}

      filters_container.tap do |container|
        container.child = filters_box

        filters_box.tap do |box|
          box.children.each { |child| box.remove(child) }

          FILTERS.each do |filter|
            filter_tile(filter).tap do |tile|
              @filter_rows[filter[:key]] = tile
              box.append(tile)
            end
          end
        end
      end

      refresh_counts
    end

    def filter_tile(filter)
      Gtk::Button.new.tap do |button|
        button.add_css_class("flat")
        button.add_css_class("filter-tile")
        button.hexpand = true
        button.child = filter_tile_content(filter)
        button.signal_connect("clicked") { window.show_filter(filter[:key]) }
      end
    end

    def filter_tile_content(filter)
      Gtk::Box.new(:horizontal, 9).tap do |box|
        box.append(filter_icon(filter))
        box.append(Gtk::Label.new(filter[:title].call).tap { |label| label.xalign = 0 })
        box.append(filter_count_label(filter))
      end
    end

    def filter_icon(filter)
      Gtk::Image.new(icon_name: filter[:icon]).tap do |image|
        image.add_css_class("filter-icon")
        image.pixel_size = 16
      end
    end

    def filter_count_label(filter)
      Gtk::Label.new("").tap do |label|
        label.add_css_class("dim-label")
        label.add_css_class("caption")
        label.hexpand = true
        label.xalign = 1
        @counts ||= {}
        @counts[filter[:key]] = label
      end
    end

    FILTER_COUNTS = {
      "inbox"     => ->(store) { store.inbox_project.then { |p| p.nil? ? [] : store.items_by_project(p.id).reject(&:checked?) } },
      "today"     => ->(store) { store.today_items },
      "scheduled" => ->(store) { store.scheduled_items },
      "labels"    => ->(store) { store.labels },
      "pinboard"  => ->(store) { store.pinboard_items },
    }.freeze

    def refresh_counts
      (@counts || {}).each do |key, label|
        if Settings.get_boolean("show-tasks-count")
          label.label = FILTER_COUNTS.fetch(key).call(store).size.to_s
        else
          label.label = ""
        end
      end
    end

    # --- projects and favourites ----------------------------------------

    def reload_projects
      @project_rows = {}
      clear(projects_listbox)

      store.root_projects.each { |project| append_project(project, 0) }
      projects_label.label = _("On This Computer")
    end

    # Subprojects are indented under their parent rather than nested in an
    # expander, which is how the sidebar reads upstream.
    def append_project(project, depth)
      ProjectRow.new(window, project, depth).build.tap do |row|
        @project_rows[project.id] = row
        projects_listbox.append(row)
        store.subprojects_of(project.id).each { |child| append_project(child, depth + 1) }
      end
    end

    def reload_favorites
      @favorite_rows = {}
      clear(favorites_listbox)

      store.favorites.each do |record|
        favorite_row(record).tap do |row|
          @favorite_rows[record.id] = row
          favorites_listbox.append(row)
        end
      end

      favorites_header.visible = !store.favorites.empty?
      favorites_listbox.visible = !store.favorites.empty?
    end

    def favorite_row(record)
      Gtk::ListBoxRow.new.tap do |row|
        row.child = Gtk::Box.new(:horizontal, 9).tap do |box|
          box.margin_start = 6
          box.margin_end = 6
          box.margin_top = 3
          box.margin_bottom = 3
          box.append(favorite_icon(record))
          box.append(Gtk::Label.new(record.name).tap { |label| label.xalign = 0 })
        end
      end
    end

    def favorite_icon(record)
      Gtk::Image.new(icon_name: record.is_a?(Label) ? "tag-outline-symbolic" : "shoe-box-symbolic")
                .tap { |image| image.pixel_size = 16 }
    end

    def activate_favorite(id)
      store.project(id).then do |project|
        if project.nil?
          store.label(id).then do |label|
            unless label.nil?
              window.show_label(label)
            end
          end
        else
          window.show_project(project)
        end
      end
    end

    # The selected view gets the highlight, wherever in the sidebar it lives.
    def select(key)
      @filter_rows.each_value { |tile| tile.remove_css_class("selected") }
      @filter_rows[key.delete_prefix("filter-")]&.add_css_class("selected")

      if key.start_with?("project-")
        projects_listbox.select_row(@project_rows[key.delete_prefix("project-")])
      end
    end

    def clear(listbox)
      while listbox.first_child
        listbox.remove(listbox.first_child)
      end
    end

    # --- widgets --------------------------------------------------------

    def scrolled
      @scrolled ||= Gtk::ScrolledWindow.new.tap do |scroll|
        scroll.hscrollbar_policy = :never
        scroll.hexpand = true
        scroll.vexpand = true
      end
    end

    def content_box
      @content_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.margin_start = 12
        box.margin_end = 12
        box.margin_bottom = 12
        box.margin_top = 6
        box.valign = :start
      end
    end

    def filters_revealer
      @filters_revealer ||= Gtk::Revealer.new.tap do |revealer|
        revealer.transition_type = :crossfade
        revealer.hexpand = true
      end
    end

    def filters_container = @filters_container ||= Adwaita::Bin.new

    def filters_box = @filters_box ||= Gtk::Box.new(:vertical, 0)

    def favorites_header
      @favorites_header ||= Gtk::Box.new(:horizontal, 6).tap do |box|
        box.margin_top = 12
        box.margin_bottom = 3
        box.visible = false
      end
    end

    def favorites_label
      @favorites_label ||= Gtk::Label.new(_("Favorites")).tap do |label|
        label.add_css_class("heading")
        label.add_css_class("dim-label")
        label.xalign = 0
        label.hexpand = true
      end
    end

    def favorites_listbox
      @favorites_listbox ||= Gtk::ListBox.new.tap do |listbox|
        listbox.add_css_class("navigation-sidebar")
        listbox.selection_mode = :none
        listbox.visible = false
      end
    end

    def projects_header
      @projects_header ||= Gtk::Box.new(:horizontal, 6).tap do |box|
        box.margin_top = 12
        box.margin_bottom = 3
      end
    end

    def projects_label
      @projects_label ||= Gtk::Label.new(_("On This Computer")).tap do |label|
        label.add_css_class("heading")
        label.add_css_class("dim-label")
        label.xalign = 0
        label.hexpand = true
      end
    end

    def add_project_button
      @add_project_button ||= Gtk::Button.new(icon_name: "plus-large-symbolic").tap do |button|
        button.add_css_class("flat")
        button.tooltip_text = _("Add Project")
      end
    end

    def projects_listbox
      @projects_listbox ||= Gtk::ListBox.new.tap do |listbox|
        listbox.add_css_class("navigation-sidebar")
        listbox.selection_mode = :single
      end
    end
  end
end
