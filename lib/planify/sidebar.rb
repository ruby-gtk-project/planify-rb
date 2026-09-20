# frozen_string_literal: true

module Planify
  # src/Layouts/Sidebar.vala. The filter tiles, favourites, one group per
  # account, and the update popup over the bottom. The project tree itself
  # belongs to each account's SidebarSourceRow.
  class Sidebar
    def initialize(window)
      @window = window
      @favorite_rows = {}
      @source_rows = {}
    end

    attr_reader :window, :source_rows

    def store = Store.instance

    def build
      @build ||= overlay.tap do |o|
        o.child = scrolled
        o.add_overlay(update_revealer)

        scrolled.child = content_box

        content_box.tap do |box|
          box.append(filters.build)
          box.append(favorites_header)
          box.append(favorites_listbox)
          box.append(sources_box)

          favorites_header.append(favorites_label)

          favorites_listbox.signal_connect("row-activated") do |_, row|
            @favorite_rows.key(row).then { |id| activate_favorite(id) }
          end
        end

        add_controller(right_click)
        right_click.signal_connect("pressed") { context_menu.popup }
      end
    end

    def add_controller(controller)
      scrolled.add_controller(controller)
    end

    def init
      reload_favorites
      reload_sources
      subscribe
    end

    def subscribe
      %i[project_added project_updated project_deleted project_archived project_unarchived]
        .each { |event| store.on(event, owner: self) { reload_projects } }

      %i[source_added source_updated source_deleted]
        .each { |event| store.on(event, owner: self) { reload_sources } }

      %i[project_updated label_updated label_added label_deleted project_deleted]
        .each { |event| store.on(event, owner: self) { reload_favorites } }

      %i[item_added item_updated item_deleted]
        .each { |event| store.on(event, owner: self) { refresh_counts } }

      Settings.changed("filters-list-view") { filters.rebuild }
      Settings.changed("views-order-visible") { filters.rebuild }
      Settings.changed("show-tasks-count") { refresh_counts }
    end

    def refresh_counts
      filters.refresh_counts
      source_rows.each_value(&:reload)
    end

    # --- accounts ---------------------------------------------------------

    # One group per account. A database written before sources existed has
    # none, so one is created and the orphaned projects moved onto it.
    def reload_sources
      ensure_local_source

      @source_rows = {}
      clear(sources_box)

      # The row object is kept, not the widget it builds: reload, select and
      # project_rows all live on the object.
      store.visible_sources.each do |source|
        SidebarSourceRow.new(window, source).tap do |row|
          @source_rows[source.id] = row
          sources_box.append(row.build)
        end
      end
    end

    def ensure_local_source
      if store.local_source.nil?
        store.insert_source(
          Source.new(source_type: "local", display_name: _("On This Computer")),
        ).tap { |source| adopt_orphans(source) }
      end
    end

    def adopt_orphans(source)
      store.projects.select { |project| project.source_id.to_s == "local" }.each do |project|
        project.source_id = source.id
        store.database.update(project)
      end
    end

    def reload_projects
      source_rows.each_value(&:reload)
    end

    def project_rows
      source_rows.values.map(&:project_rows).reduce({}, :merge)
    end

    # --- favourites -------------------------------------------------------

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
      if record.is_a?(Label)
        Gtk::Image.new(icon_name: "tag-outline-symbolic").tap { |image| image.pixel_size = 16 }
      else
        IconColorProject.new(record).build
      end
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

    # --- selection and the update popup -----------------------------------

    def select(key)
      filters.select(key)

      if key.start_with?("project-")
        key.delete_prefix("project-").then do |project_id|
          source_rows.each_value { |row| row.select(project_id) }
        end
      end
    end

    def show_update(widget)
      update_revealer.child = widget
      update_revealer.reveal_child = true
    end

    def hide_update
      update_revealer.reveal_child = false
    end

    def clear(container)
      while container.first_child
        container.remove(container.first_child)
      end
    end

    # --- widgets ----------------------------------------------------------

    def overlay = @overlay ||= Gtk::Overlay.new

    def filters
      @filters ||= FilterFlowBox.new { |key| window.show_filter(key) }
    end

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

    def sources_box = @sources_box ||= Gtk::Box.new(:vertical, 0)

    def update_revealer
      @update_revealer ||= Gtk::Revealer.new.tap do |revealer|
        revealer.transition_type = :slide_up
        revealer.valign = :end
      end
    end

    def right_click
      @right_click ||= Gtk::GestureClick.new.tap { |gesture| gesture.button = Gdk::BUTTON_SECONDARY }
    end

    def context_menu
      @context_menu ||= Gtk::PopoverMenu.new(:model, sidebar_menu).tap do |popover|
        popover.set_parent(scrolled)
        popover.has_arrow = false
      end
    end

    def sidebar_menu
      @sidebar_menu ||= Gio::Menu.new.tap do |menu|
        Gio::Menu.new.tap do |section|
          section.append(_("Add Project"), "win.new-project")
          section.append(_("Manage Projects"), "win.manage-projects")
          menu.append_section(nil, section)
        end

        Gio::Menu.new.tap do |section|
          section.append(_("Preferences"), "app.preferences")
          menu.append_section(nil, section)
        end
      end
    end
  end
end
