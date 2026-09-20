# frozen_string_literal: true

module Planify
  module Dialogs
    # src/Dialogs/ManageProjects.vala. Reorder, hide and archive projects in
    # one place rather than through each project's own menu.
    class ManageProjects
      def initialize(window)
        @window = window
      end

      attr_reader :window

      def store = Store.instance

      def present(parent)
        dialog.tap do |d|
          d.child = toolbar

          toolbar.tap do |view|
            view.add_top_bar(header)
            view.content = page

            header.title_widget = Adwaita::WindowTitle.new(_("Manage Projects"), "")

            page.add(active_group)
            page.add(archived_group)
          end

          reload
          d.present(parent)
        end
      end

      def reload
        @active_rows ||= []
        @archived_rows ||= []
        @active_rows.each { |row| active_group.remove(row) }
        @archived_rows.each { |row| archived_group.remove(row) }

        @active_rows = store.root_projects.map { |project| active_row(project) }
        @active_rows.each { |row| active_group.add(row) }

        @archived_rows = store.archived_projects.map { |project| archived_row(project) }
        @archived_rows.each { |row| archived_group.add(row) }
        archived_group.visible = !@archived_rows.empty?
      end

      def active_row(project)
        Adwaita::ActionRow.new.tap do |row|
          row.title = project.name.to_s
          row.subtitle = n_(
            "%d task",
            "%d tasks",
            store.items_by_project(project.id).size,
          ) %
                         store.items_by_project(project.id).size
          row.add_prefix(IconColorProject.new(project).build)
          row.add_suffix(move_button(project, -1, "go-up-symbolic"))
          row.add_suffix(move_button(project, 1, "go-down-symbolic"))
          row.add_suffix(archive_button(project))
        end
      end

      def archived_row(project)
        Adwaita::ActionRow.new.tap do |row|
          row.title = project.name.to_s
          row.subtitle = _("Archived")
          row.add_suffix(unarchive_button(project))
          row.add_suffix(delete_button(project))
        end
      end

      # Reordering swaps child_order with the neighbour rather than
      # renumbering the list, so only two rows are written.
      def move_button(project, direction, icon)
        Gtk::Button.new(icon_name: icon).tap do |button|
          button.add_css_class("flat")
          button.valign = :center
          button.signal_connect("clicked") { move(project, direction) }
        end
      end

      def move(project, direction)
        store.root_projects.then do |ordered|
          ordered.index(project).then do |index|
            neighbour = ordered[index + direction]

            unless neighbour.nil? || index + direction.negative?
              swap(project, neighbour)
              reload
            end
          end
        end
      end

      def swap(one, other)
        one.child_order.to_i.then do |order|
          one.child_order = other.child_order.to_i
          other.child_order = order
          store.update_project(one)
          store.update_project(other)
        end
      end

      def archive_button(project)
        Gtk::Button.new(icon_name: "shoe-box-symbolic").tap do |button|
          button.add_css_class("flat")
          button.valign = :center
          button.tooltip_text = _("Archive")
          button.signal_connect("clicked") do
            store.archive_project(project)
            window.drop_view("project-#{project.id}")
            reload
          end
        end
      end

      def unarchive_button(project)
        Gtk::Button.new(label: _("Restore")).tap do |button|
          button.add_css_class("flat")
          button.valign = :center
          button.signal_connect("clicked") do
            store.unarchive_project(project)
            reload
          end
        end
      end

      def delete_button(project)
        Gtk::Button.new(icon_name: "user-trash-symbolic").tap do |button|
          button.add_css_class("flat")
          button.valign = :center
          button.signal_connect("clicked") do
            store.delete_project(project)
            reload
          end
        end
      end

      def dialog
        @dialog ||= Adwaita::Dialog.new.tap do |d|
          d.title = _("Manage Projects")
          d.content_width = 480
          d.content_height = 560
        end
      end

      def toolbar = @toolbar ||= Adwaita::ToolbarView.new

      def header = @header ||= Adwaita::HeaderBar.new

      def page = @page ||= Adwaita::PreferencesPage.new

      def active_group
        @active_group ||= Adwaita::PreferencesGroup.new.tap { |g| g.title = _("Projects") }
      end

      def archived_group
        @archived_group ||= Adwaita::PreferencesGroup.new.tap do |g|
          g.title = _("Archived")
          g.visible = false
        end
      end
    end

    # src/Dialogs/ManageSectionOrder.vala.
    class ManageSectionOrder
      def initialize(window, project)
        @window = window
        @project = project
      end

      attr_reader :window, :project

      def store = Store.instance

      def present(parent)
        dialog.tap do |d|
          d.child = toolbar

          toolbar.tap do |view|
            view.add_top_bar(header)
            view.content = page
            header.title_widget = Adwaita::WindowTitle.new(_("Section Order"), project.name.to_s)
            page.add(group)
          end

          reload
          d.present(parent)
        end
      end

      def sections = store.sections_by_project(project.id)

      def reload
        @rows ||= []
        @rows.each { |row| group.remove(row) }
        @rows = sections.map { |section| section_row(section) }
        @rows.each { |row| group.add(row) }
      end

      def section_row(section)
        Adwaita::ActionRow.new.tap do |row|
          row.title = section.name.to_s
          row.subtitle = n_("%d task", "%d tasks", store.items_by_section(section.id).size) %
                         store.items_by_section(section.id).size
          row.add_suffix(move_button(section, -1, "go-up-symbolic"))
          row.add_suffix(move_button(section, 1, "go-down-symbolic"))
          row.add_suffix(hide_switch(section))
        end
      end

      def move_button(section, direction, icon)
        Gtk::Button.new(icon_name: icon).tap do |button|
          button.add_css_class("flat")
          button.valign = :center
          button.signal_connect("clicked") { move(section, direction) }
        end
      end

      def move(section, direction)
        sections.then do |ordered|
          ordered.index(section).then do |index|
            neighbour = ordered[index + direction]

            unless neighbour.nil? || index + direction.negative?
              section.section_order.to_i.then do |order|
                section.section_order = neighbour.section_order.to_i
                neighbour.section_order = order
                store.update_section(section)
                store.update_section(neighbour)
              end
              reload
            end
          end
        end
      end

      def hide_switch(section)
        Gtk::Switch.new.tap do |switch|
          switch.valign = :center
          switch.active = !section.hidden?
          switch.tooltip_text = _("Show this section")
          switch.signal_connect("notify::active") do
            section.hidded = Record.flag(!switch.active?)
            store.update_section(section)
          end
        end
      end

      def dialog
        @dialog ||= Adwaita::Dialog.new.tap do |d|
          d.title = _("Section Order")
          d.content_width = 440
        end
      end

      def toolbar = @toolbar ||= Adwaita::ToolbarView.new

      def header = @header ||= Adwaita::HeaderBar.new

      def page = @page ||= Adwaita::PreferencesPage.new

      def group = @group ||= Adwaita::PreferencesGroup.new
    end

    # src/Dialogs/CompletedTasks.vala. Everything completed in a project, with
    # the option to put one back.
    class CompletedTasks
      def initialize(window, project = nil)
        @window = window
        @project = project
      end

      attr_reader :window, :project

      def store = Store.instance

      def present(parent)
        dialog.tap do |d|
          d.child = toolbar

          toolbar.tap do |view|
            view.add_top_bar(header)
            view.content = stack

            header.title_widget = Adwaita::WindowTitle.new(_("Completed Tasks"), subtitle)
            header.pack_end(clear_button)

            stack.add_named(scrolled, "list")
            stack.add_named(empty_page, "empty")

            scrolled.child = listbox
            clear_button.signal_connect("clicked") { confirm_clear }
          end

          reload
          d.present(parent)
        end
      end

      def subtitle = project.nil? ? _("Everywhere") : project.name.to_s

      def items
        if project.nil?
          store.completed_items
        else
          store.completed_items.select { |item| item.project_id == project.id }
        end
      end

      def reload
        while listbox.first_child
          listbox.remove(listbox.first_child)
        end

        items.each { |item| listbox.append(CompletedTaskRow.new(window, item).build) }
        if items.empty?
          stack.visible_child_name = "empty"
        else
          stack.visible_child_name = "list"
        end
        clear_button.sensitive = !items.empty?
      end

      def confirm_clear
        Adwaita::AlertDialog.new(
          _("Delete Completed Tasks?"),
          n_(
            "%d completed task will be deleted. This cannot be undone.",
            "%d completed tasks will be deleted. This cannot be undone.",
            items.size,
          ) % items.size,
        ).tap do |alert|
          alert.add_response("cancel", _("Cancel"))
          alert.add_response("delete", _("Delete"))
          alert.set_response_appearance("delete", Adwaita::ResponseAppearance::DESTRUCTIVE)
          alert.signal_connect("response") do |_, response|
            if response == "delete"
              items.each { |item| store.delete_item(item) }
              reload
            end
          end
          alert.present(dialog)
        end
      end

      def dialog
        @dialog ||= Adwaita::Dialog.new.tap do |d|
          d.title = _("Completed Tasks")
          d.content_width = 480
          d.content_height = 560
        end
      end

      def toolbar = @toolbar ||= Adwaita::ToolbarView.new

      def header = @header ||= Adwaita::HeaderBar.new

      def clear_button
        @clear_button ||= Gtk::Button.new(icon_name: "user-trash-symbolic").tap do |button|
          button.add_css_class("flat")
          button.tooltip_text = _("Delete Completed Tasks")
        end
      end

      def stack = @stack ||= Gtk::Stack.new

      def scrolled
        @scrolled ||= Gtk::ScrolledWindow.new.tap do |scroll|
          scroll.hscrollbar_policy = :never
          scroll.vexpand = true
        end
      end

      def listbox
        @listbox ||= Gtk::ListBox.new.tap do |list|
          list.selection_mode = :none
          list.add_css_class("background")
        end
      end

      def empty_page
        @empty_page ||= Adwaita::StatusPage.new.tap do |p|
          p.icon_name = "check-round-outline-symbolic"
          p.title = _("Nothing completed yet")
          p.description = _("Completed tasks are collected here.")
        end
      end
    end
  end
end
