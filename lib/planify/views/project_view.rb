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
          add_section_button.popover = sections_order_popover.build
          sort_button.menu_model = sort_menu_model
          register_sort_actions(toolbar)

          # The list and the board are two different containers rather than
          # two arrangements of one, so the view holds both and swaps pages.
          stack.add_named(board_scrolled, "board")
          board_scrolled.child = board_box

          clamp.child = column_box

          column_box.tap do |box|
            box.append(description_widget.build)
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
        unless description_widget.editing?
          description_widget.text = project.description.to_s
        end
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

      # Section rows are reused for the same reason task rows are.
      def rebuild_sections
        store.sections_by_project(project.id).reject(&:hidden?).then do |sections|
          ids = sections.map(&:id)

          (@section_rows.keys - ids).each do |id|
            sections_box.remove(@section_rows.delete(id).build)
          end

          sections.each do |section|
            if @section_rows.key?(section.id)
              @section_rows.fetch(section.id).refresh
            else
              add_section_row(section)
            end
          end
        end
      end

      def add_section_row(section)
        SectionRow.new(window, section, project).tap do |row|
          @section_rows[section.id] = row
          sections_box.append(row.build)
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

      def save_description(text)
        unless project.description.to_s == text
          project.description = text
          store.update_project(project)
        end
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

      # The button opens the sections popover, where the sections can be
      # reordered and hidden as well as added — upstream's section menu.
      def add_section_button
        @add_section_button ||= Gtk::MenuButton.new.tap do |button|
          button.icon_name = "plus-large-symbolic"
          button.add_css_class("flat")
          button.tooltip_text = _("Sections")
        end
      end

      def sections_order_popover
        @sections_order_popover ||= SectionsOrderPopover.new(window, project)
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

      # The project note, editable in place: clicking into it starts an edit
      # and every keystroke is written back, which is what upstream's
      # EditableTextView does on the list and board layouts alike.
      def description_widget
        @description_widget ||= EditableTextView.new(_("Note")) do |text|
          save_description(text)
        end.tap do |widget|
          widget.build.margin_bottom = 12
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
