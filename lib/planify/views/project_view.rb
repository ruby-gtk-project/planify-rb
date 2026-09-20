# frozen_string_literal: true

module Planify
  # src/Views/Project: the list and board layouts of a single project, with
  # its unsectioned tasks first and each section below.
  module Views
    class ProjectView < BaseView
      def initialize(window, project)
        super(window)
        @project = project
        @section_rows = {}
      end

      attr_reader :project

      def title = project.name.to_s

      def subtitle
        pending.size.then { |count| n_("%d task", "%d tasks", count) % count }
      end

      def pending = store.items_by_project(project.id).reject(&:checked?)

      def items = store.items_by_project_unsectioned(project.id).then { |all| visible(all) }

      def visible(all)
        if project.show_completed?
          all
        else
          all.reject(&:checked?)
        end
      end

      def quick_add_defaults = { project: project }

      def empty_title = _("This project is empty")

      def empty_description = _("Add your first task with the button below.")

      def empty_icon = "shoe-box-symbolic"

      def build
        @build ||= super.tap do
          header.pack_end(view_style_button)
          header.pack_end(add_section_button)

          view_style_button.signal_connect("clicked") { toggle_view_style }
          add_section_button.signal_connect("clicked") { add_section }

          clamp.child = column_box

          column_box.tap do |box|
            box.append(description_label)
            box.append(list_box)
            box.append(sections_box)
          end

          subscribe_sections
        end
      end

      def subscribe_sections
        %i[section_added section_updated section_deleted project_updated]
          .each { |event| store.on(event, owner: self) { refresh } }
      end

      def refresh
        window_title.title = title
        window_title.subtitle = subtitle
        description_label.label = project.description.to_s
        description_label.visible = !project.description.to_s.strip.empty?
        if project.board?
          view_style_button.icon_name = "list-symbolic"
        else
          view_style_button.icon_name = "view-columns-symbolic"
        end
        rebuild
        rebuild_sections
        if empty?
          stack.visible_child_name = "empty"
        else
          stack.visible_child_name = "list"
        end
      end

      def empty? = items.empty? && store.sections_by_project(project.id).empty?

      def rebuild_sections
        @section_rows = {}
        while sections_box.first_child
          sections_box.remove(sections_box.first_child)
        end

        store.sections_by_project(project.id).reject(&:hidden?).each do |section|
          SectionRow.new(window, section, project).build.tap do |row|
            @section_rows[section.id] = row
            sections_box.append(row)
          end
        end

        if project.board?
          sections_box.orientation = :horizontal
        else
          sections_box.orientation = :vertical
        end
      end

      def toggle_view_style
        if project.board?
          project.view_style = "list"
        else
          project.view_style = "board"
        end
        store.update_project(project)
      end

      def add_section
        Dialogs::SectionDialog.new(window, project).present(window.window)
      end

      def view_menu
        @view_menu ||= Gio::Menu.new.tap do |menu|
          Gio::Menu.new.tap do |section|
            section.append(_("Add Task"), "win.new-item")
            section.append(_("Add Section"), "view.add-section")
            menu.append_section(nil, section)
          end

          Gio::Menu.new.tap do |section|
            section.append(_("Show Completed Tasks"), "view.show-completed")
            menu.append_section(nil, section)
          end
        end
      end

      def view_style_button
        @view_style_button ||= Gtk::Button.new(icon_name: "view-columns-symbolic").tap do |button|
          button.add_css_class("flat")
          button.tooltip_text = _("Change Layout")
        end
      end

      def add_section_button
        @add_section_button ||= Gtk::Button.new(icon_name: "plus-large-symbolic").tap do |button|
          button.add_css_class("flat")
          button.tooltip_text = _("Add Section")
        end
      end

      def column_box = @column_box ||= Gtk::Box.new(:vertical, 0)

      def description_label
        @description_label ||= Gtk::Label.new("").tap do |label|
          label.xalign = 0
          label.wrap = true
          label.add_css_class("dim-label")
          label.margin_bottom = 12
          label.visible = false
        end
      end

      def sections_box
        @sections_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
          box.spacing = 12
        end
      end
    end
  end
end
