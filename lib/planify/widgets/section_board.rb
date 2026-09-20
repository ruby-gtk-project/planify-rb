# frozen_string_literal: true

module Planify
  # src/Layouts/SectionBoard.vala. One column of a board: a section's header
  # over a scrolling list of its tasks, with an add row at the bottom and a
  # drop target so a card can be dragged into it.
  class SectionBoard
    WIDTH = 290

    def initialize(window, section, project)
      @window = window
      @section = section
      @project = project
      @rows = {}
    end

    attr_reader :window, :section, :project

    def store = Store.instance

    def build
      @build ||= box.tap do |b|
        b.append(header)
        b.append(scrolled)
        b.append(add_button)

        header.tap do |h|
          h.append(color_dot)
          h.append(name_label)
          h.append(count_label)
          h.append(menu_button)
          menu_button.menu_model = context_menu
        end

        scrolled.child = listbox

        listbox.signal_connect("row-activated") do |_, row|
          @rows.find { |_, card| card.build == row }.then do |found|
            unless found.nil?
              window.show_item(store.item(found.first))
            end
          end
        end

        add_button.signal_connect("clicked") { add_task }

        b.add_controller(drop_target)
        drop_target.signal_connect("drop") { |_, value, _, _| accept(value) }

        register_actions
        refresh
      end
    end

    # A column with no section is the project's loose tasks, which still needs
    # a home on a board.
    def loose? = section.nil?

    def items
      loose? ? store.items_by_project_unsectioned(project.id) : store.items_by_section(section.id)
    end

    def visible_items
      if project.show_completed?
        items
      else
        items.reject(&:checked?)
      end
    end

    def refresh
      if loose?
        name_label.label = _("No Section")
      else
        name_label.label = section.name.to_s
      end
      count_label.label = visible_items.count { |item| !item.checked? }.to_s
      color_dot.visible = !loose?
      unless loose?
        tint
      end
      rebuild
    end

    # Cards are reused between refreshes, for the same reason list rows are.
    def rebuild
      visible_items.then do |current|
        ids = current.map(&:id)

        (@rows.keys - ids).each { |id| listbox.remove(@rows.delete(id).build) }

        current.each do |item|
          if @rows.key?(item.id)
            @rows.fetch(item.id).refresh
          else
            add_card(item)
          end
        end

        placeholder.visible = current.empty?
      end
    end

    def add_card(item)
      ItemBoard.new(window, item).tap do |card|
        @rows[item.id] = card
        listbox.append(card.build)
      end
    end

    def tint
      Gtk::CssProvider.new.tap do |provider|
        provider.load(
          data: "box { background: #{Palette.hex(section.color)}; " \
                                      "border-radius: 50%; }",
        )
        color_dot.style_context.add_provider(provider, Gtk::StyleProvider::PRIORITY_APPLICATION)
      end
    end

    def add_task
      QuickAdd.new(window, project: project, section: section).present(window.window)
    end

    # Dropping a card here moves it into this column.
    def accept(value)
      store.item(value.to_s).then do |item|
        if item.nil?
          false
        else
          if loose?
            item.section_id = ""
          else
            item.section_id = section.id
          end
          item.project_id = project.id
          item.child_order = store.next_child_order(item.project_id, item.section_id)
          store.update_item(item)
          true
        end
      end
    end

    SECTION_ACTIONS = {
      "edit"      => :edit,
      "duplicate" => :duplicate,
      "archive"   => :archive,
      "delete"    => :delete,
    }.freeze

    def register_actions
      unless loose?
        Gio::SimpleActionGroup.new.tap do |group|
          SECTION_ACTIONS.each do |name, method|
            Gio::SimpleAction.new(name).tap do |action|
              action.signal_connect("activate") { public_send(method) }
              group.add_action(action)
            end
          end

          box.insert_action_group("section", group)
        end
      end
    end

    def context_menu
      @context_menu ||= Gio::Menu.new.tap do |menu|
        Gio::Menu.new.tap do |group|
          group.append(_("Edit Section"), "section.edit")
          group.append(_("Duplicate"), "section.duplicate")
          menu.append_section(nil, group)
        end

        Gio::Menu.new.tap do |group|
          group.append(_("Archive"), "section.archive")
          group.append(_("Delete Section"), "section.delete")
          menu.append_section(nil, group)
        end
      end
    end

    def edit
      Dialogs::SectionDialog.new(window, project, section: section).present(window.window)
    end

    def duplicate
      SectionRow.new(window, section, project).duplicate
    end

    def archive
      section.is_archived = 1
      store.update_section(section)
    end

    def delete
      SectionRow.new(window, section, project).delete
    end

    # --- widgets ----------------------------------------------------------

    def box
      @box ||= Gtk::Box.new(:vertical, 6).tap do |b|
        b.width_request = WIDTH
        b.add_css_class("section-board")
        b.margin_start = 6
        b.margin_end = 6
      end
    end

    def header = @header ||= Gtk::Box.new(:horizontal, 6)

    def color_dot
      @color_dot ||= Gtk::Box.new(:vertical, 0).tap do |b|
        b.width_request = 9
        b.height_request = 9
        b.valign = :center
      end
    end

    def name_label
      @name_label ||= Gtk::Label.new("").tap do |label|
        label.add_css_class("heading")
        label.xalign = 0
        label.hexpand = true
        label.ellipsize = :end
      end
    end

    def count_label
      @count_label ||= Gtk::Label.new("").tap do |label|
        label.add_css_class("dim-label")
        label.add_css_class("caption")
      end
    end

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.icon_name = "view-more-symbolic"
        button.add_css_class("flat")
      end
    end

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
        list.set_placeholder(placeholder)
      end
    end

    def placeholder
      @placeholder ||= Gtk::Label.new(_("No tasks")).tap do |label|
        label.add_css_class("dim-label")
        label.add_css_class("caption")
        label.margin_top = 12
        label.margin_bottom = 12
      end
    end

    def add_button
      @add_button ||= Gtk::Button.new.tap do |button|
        button.child = Adwaita::ButtonContent.new.tap do |content|
          content.icon_name = "plus-large-symbolic"
          content.label = _("Add Task")
        end
        button.add_css_class("flat")
      end
    end

    def drop_target
      @drop_target ||= Gtk::DropTarget.new(GLib::Type["gchararray"], Gdk::DragAction::MOVE)
    end
  end

  # src/Layouts/ItemBoard.vala: a task as a card rather than a row.
  class ItemBoard
    def initialize(window, item)
      @window = window
      @item = item
    end

    attr_reader :window, :item

    def store = Store.instance

    def build
      @build ||= row.tap do |r|
        r.child = card

        card.tap do |c|
          c.append(top_box)
          c.append(description_label)
          c.append(labels.build)
          c.append(footer_box)

          top_box.append(check_button)
          top_box.append(content_label)

          footer_box.append(due_label)
          footer_box.append(subtasks_label)
          footer_box.append(priority_icon)

          check_button.signal_connect("toggled") { toggle }
        end

        r.add_controller(drag_source)
        drag_source.signal_connect("prepare") do |_, _, _|
          Gdk::ContentProvider.new(item.id.to_s)
        end

        refresh
      end
    end

    def refresh
      check_button.active = item.checked?
      content_label.label = item.content.to_s
      description_label.label = Markdown.preview(item.description)
      description_label.visible = !description_label.label.empty?
      labels.labels = item.label_objects
      refresh_due
      refresh_subtasks
      priority_icon.visible = item.priority.to_i != Item::PRIORITY_4
      tint_priority
    end

    def refresh_due
      item.due_date.then do |due|
        due_label.visible = !due.nil?

        unless due.nil?
          due_label.label = Datetime.date_word(due)
          due_label.remove_css_class("error")
          if Datetime.overdue?(due)
            due_label.add_css_class("error")
          end
        end
      end
    end

    def refresh_subtasks
      item.subitems.then do |subitems|
        subtasks_label.visible = !subitems.empty?
        subtasks_label.label = "#{subitems.count(&:checked?)}/#{subitems.size}"
      end
    end

    def tint_priority
      Gtk::CssProvider.new.tap do |provider|
        provider.load(data: "image { color: #{item.priority_color}; }")
        priority_icon.style_context.add_provider(provider, Gtk::StyleProvider::PRIORITY_APPLICATION)
      end
    end

    def toggle
      unless check_button.active? == item.checked?
        store.complete_item(item, check_button.active?)
      end
    end

    def row
      @row ||= Gtk::ListBoxRow.new.tap do |r|
        r.margin_bottom = 6
      end
    end

    def card
      @card ||= Gtk::Box.new(:vertical, 6).tap do |b|
        b.add_css_class("card")
        b.add_css_class("item-board")
        b.margin_start = 3
        b.margin_end = 3
        b.margin_top = 3
        b.margin_bottom = 3
      end
    end

    def top_box
      @top_box ||= Gtk::Box.new(:horizontal, 6).tap do |b|
        b.margin_start = 9
        b.margin_end = 9
        b.margin_top = 9
      end
    end

    def check_button
      @check_button ||= Gtk::CheckButton.new.tap { |check| check.valign = :start }
    end

    def content_label
      @content_label ||= Gtk::Label.new("").tap do |label|
        label.xalign = 0
        label.wrap = true
        label.wrap_mode = :word_char
        label.hexpand = true
      end
    end

    def description_label
      @description_label ||= Gtk::Label.new("").tap do |label|
        label.xalign = 0
        label.ellipsize = :end
        label.add_css_class("dim-label")
        label.add_css_class("caption")
        label.margin_start = 9
        label.margin_end = 9
        label.visible = false
      end
    end

    def labels = @labels ||= ItemLabels.new

    def footer_box
      @footer_box ||= Gtk::Box.new(:horizontal, 6).tap do |b|
        b.margin_start = 9
        b.margin_end = 9
        b.margin_bottom = 9
      end
    end

    def due_label
      @due_label ||= Gtk::Label.new("").tap do |label|
        label.add_css_class("caption")
        label.visible = false
      end
    end

    def subtasks_label
      @subtasks_label ||= Gtk::Label.new("").tap do |label|
        label.add_css_class("caption")
        label.add_css_class("dim-label")
        label.hexpand = true
        label.xalign = 0
        label.visible = false
      end
    end

    def priority_icon
      @priority_icon ||= Gtk::Image.new(icon_name: "flag-outline-thick-symbolic").tap do |image|
        image.visible = false
        image.pixel_size = 12
      end
    end

    def drag_source
      @drag_source ||= Gtk::DragSource.new.tap do |source|
        source.actions = Gdk::DragAction::MOVE
      end
    end
  end
end
