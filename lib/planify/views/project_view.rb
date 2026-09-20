# frozen_string_literal: true

module Planify
  # src/Views/Project: the list and board layouts of a single project, with
  # its unsectioned tasks first and each section below.
  module Views
    class ProjectView < BaseView
      include Sorting

      def initialize(window, project)
        super(window)
        @project = project
        @section_rows = {}
        @boards = {}
      end

      def settings_prefix = "project-#{project.id}"

      # A project remembers its own completed-task visibility, unlike the
      # filter views where the flag lives only for the session.
      def show_completed? = project.show_completed?

      def toggle_completed
        project.show_completed = Record.flag(!project.show_completed?)
        store.update_project(project)
        refresh
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
          header.pack_end(sort_button)

          view_style_button.signal_connect("clicked") { toggle_view_style }
          add_section_button.signal_connect("clicked") { add_section }
          sort_button.menu_model = sort_menu_model
          register_sort_actions(toolbar)

          # The list and the board are two different containers rather than
          # two arrangements of one, so the view holds both and swaps pages.
          stack.add_named(board_scrolled, "board")
          board_scrolled.child = board_box

          clamp.child = column_box

          column_box.tap do |box|
            box.append(description_label)
            box.append(pinned_box.build)
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
        refresh_style_button
        pinned_box.refresh
        rebuild
        rebuild_sections
        rebuild_board
        stack.visible_child_name = visible_page
      end

      def refresh_style_button
        if project.board?
          view_style_button.icon_name = "list-symbolic"
          view_style_button.tooltip_text = _("Switch to List")
        else
          view_style_button.icon_name = "view-columns-symbolic"
          view_style_button.tooltip_text = _("Switch to Board")
        end
      end

      def visible_page
        if empty?
          "empty"
        elsif project.board?
          "board"
        else
          "list"
        end
      end

      # A board column exists for every section plus one for the loose tasks,
      # which otherwise have nowhere to appear.
      def rebuild_board
        @boards = {}

        while board_box.first_child
          board_box.remove(board_box.first_child)
        end

        ([nil] + store.sections_by_project(project.id).reject(&:hidden?)).each do |section|
          SectionBoard.new(window, section, project).build.tap do |column|
            @boards[section&.id.to_s] = column
            board_box.append(column)
          end
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

      def pinned_box = @pinned_box ||= PinnedItemsBox.new(window, project)

      def board_scrolled
        @board_scrolled ||= Gtk::ScrolledWindow.new.tap do |scroll|
          scroll.vscrollbar_policy = :never
          scroll.hexpand = true
          scroll.vexpand = true
        end
      end

      def board_box
        @board_box ||= Gtk::Box.new(:horizontal, 0).tap do |b|
          b.margin_start = 12
          b.margin_end = 12
          b.margin_top = 12
          b.margin_bottom = 12
        end
      end

      def sort_button
        @sort_button ||= Gtk::MenuButton.new.tap do |button|
          button.icon_name = "vertical-arrows-long-symbolic"
          button.add_css_class("flat")
          button.tooltip_text = _("View Option Menu")
        end
      end

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
