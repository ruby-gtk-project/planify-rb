# frozen_string_literal: true

module Planify
  # src/Widgets/SectionsOrderPopover.vala. The popover behind a project's
  # section menu: every section as a draggable row with a switch for whether it
  # shows, and an Add Section item under them. Dragging a row writes the new
  # section_order, and the switch writes `hidded` — upstream's spelling of the
  # column, kept because the sync backends exchange it.
  class SectionsOrderPopover
    def initialize(window, project)
      @window = window
      @project = project
      @rows = []
    end

    attr_reader :window, :project

    def store = Store.instance

    def build
      @build ||= popover.tap do |p|
        p.child = content_box

        content_box.tap do |box|
          box.append(listbox)
          box.append(separator)
          box.append(add_section_item.build)
        end

        reload

        store.on(:section_added, owner: self) { reload }
        store.on(:section_deleted, owner: self) { reload }
      end
    end

    def popup
      build
      popover.popup
    end

    def sections
      store.sections_by_project(project.id).sort_by { |section| section.section_order.to_i }
    end

    def reload
      @rows = []

      while listbox.first_child
        listbox.remove(listbox.first_child)
      end

      sections.each do |section|
        SectionsOrderItem.new(section) { |listbox_| persist_order(listbox_) }.tap do |item|
          @rows << item
          listbox.append(item.build)
        end
      end
    end

    # A drop moves one row, which shifts every row below it, so the whole
    # list's order is rewritten from where the rows now sit.
    def persist_order(listbox_widget)
      child = listbox_widget.first_child
      index = 0
      while child
        store.section(child.name.to_s).then do |section|
          unless section.nil?
            section.section_order = index
            store.update_section(section)
          end
        end
        index += 1
        child = child.next_sibling
      end
    end

    def add_section
      popover.popdown
      Dialogs::SectionDialog.new(window, project).present(window.window)
    end

    # --- widgets ----------------------------------------------------------

    def popover
      @popover ||= Gtk::Popover.new.tap do |p|
        p.has_arrow = false
        p.position = :bottom
        p.width_request = 250
      end
    end

    def content_box
      @content_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.hexpand = true
        box.vexpand = true
      end
    end

    def listbox
      @listbox ||= Gtk::ListBox.new.tap do |list|
        list.selection_mode = :none
        list.add_css_class("menu-listbox")
      end
    end

    def separator = @separator ||= Gtk::Separator.new(:horizontal)

    def add_section_item
      @add_section_item ||= ContextMenu::MenuItem.new(
        _("Add Section"),
        icon: "plus-large-symbolic",
      ) { add_section }
    end
  end

  # The row inside the popover. Upstream calls it SectionsOrderItem and gives
  # it its own drag source and drop target rather than reusing ReorderChild,
  # because the rows here are a flat reorderable list with no drop strips.
  class SectionsOrderItem
    def initialize(section, &on_drop_end)
      @section = section
      @on_drop_end = on_drop_end
    end

    attr_reader :section

    def store = Store.instance

    def build
      @build ||= row.tap do |r|
        r.child = handle_grid

        handle_grid.attach(
          content_box,
          0,
          0,
          1,
          1,
        )

        content_box.tap do |box|
          box.append(order_icon)
          box.append(color_dot)
          box.append(name_label)
          box.append(visible_switch)

          visible_switch.signal_connect("notify::active") { toggle_visible }
        end

        build_drag_and_drop
        refresh
      end
    end

    def refresh
      name_label.label = section.name.to_s
      visible_switch.active = !section.hidden?
      tint(color_dot, Palette.hex(section.color))
    end

    def toggle_visible
      Record.flag(!visible_switch.active?).then do |hidden|
        unless section.hidded.to_s == hidden.to_s
          section.hidded = hidden
          store.update_section(section)
        end
      end
    end

    def tint(widget, hex)
      Gtk::CssProvider.new.tap do |provider|
        provider.load(data: "grid { background-color: #{hex}; border-radius: 50%; }")
        widget.style_context.add_provider(provider, Gtk::StyleProvider::PRIORITY_APPLICATION)
      end
    end

    # --- drag and drop ----------------------------------------------------

    def build_drag_and_drop
      row.add_controller(drag_source)
      row.add_controller(drop_target)

      drag_source.tap do |source|
        source.signal_connect("prepare") { |_, _, _| Gdk::ContentProvider.new(section.id.to_s) }
        source.signal_connect("drag-begin") do
          source.set_icon(Gtk::WidgetPaintable.new(handle_grid), 0, 0)
          drag_begin
        end
        source.signal_connect("drag-end") { drag_end }
        source.signal_connect("drag-cancel") do
          drag_end
          false
        end
      end

      drop_target.signal_connect("drop") { |_, value, _x, y| accept_drop(value, y) }
    end

    # The dragged row lands after this one, except on the first row's top
    # half, where it lands before it — the only way to reach position zero.
    def accept_drop(value, pointer_y)
      drag_end

      row.parent.then do |listbox|
        find_row(listbox, value.to_s).then do |picked|
          if picked.nil? || picked == row
            false
          else
            move(listbox, picked, pointer_y)
            true
          end
        end
      end
    end

    def move(listbox, picked, pointer_y)
      position = row.index + 1
      if row.index.zero? && pointer_y <= (row.height / 2.0)
        position = 0
      end

      listbox.remove(picked)
      listbox.insert(picked, position)
      @on_drop_end&.call(listbox)
    end

    def find_row(listbox, id)
      child = listbox.first_child
      while child && child.name.to_s != id
        child = child.next_sibling
      end
      child
    end

    def drag_begin
      handle_grid.add_css_class("card")
      row.opacity = 0.3
    end

    def drag_end
      handle_grid.remove_css_class("card")
      row.opacity = 1
    end

    # --- widgets ----------------------------------------------------------

    # The id rides on the widget name, which is how a drop reads the order
    # back off the listbox.
    def row
      @row ||= Gtk::ListBoxRow.new.tap do |r|
        r.name = section.id.to_s
        r.activatable = false
        r.add_css_class("no-selectable")
        r.add_css_class("transition")
      end
    end

    def handle_grid = @handle_grid ||= Gtk::Grid.new

    def content_box
      @content_box ||= Gtk::Box.new(:horizontal, 6).tap do |box|
        box.margin_top = 6
        box.margin_start = 10
        box.margin_end = 6
        box.margin_bottom = 6
      end
    end

    def order_icon
      @order_icon ||= Gtk::Image.new(icon_name: "list-drag-handle-symbolic").tap do |image|
        image.pixel_size = 12
        image.add_css_class("dim-label")
      end
    end

    def color_dot
      @color_dot ||= Gtk::Grid.new.tap do |grid|
        grid.height_request = 12
        grid.width_request = 12
        grid.valign = :center
        grid.halign = :center
      end
    end

    def name_label
      @name_label ||= Gtk::Label.new.tap do |label|
        label.valign = :center
        label.ellipsize = :end
      end
    end

    def visible_switch
      @visible_switch ||= Gtk::Switch.new.tap do |switch|
        switch.valign = :center
        switch.hexpand = true
        switch.halign = :end
        switch.margin_start = 6
      end
    end

    def drag_source
      @drag_source ||= Gtk::DragSource.new.tap do |source|
        source.actions = Gdk::DragAction::MOVE
      end
    end

    def drop_target
      @drop_target ||= Gtk::DropTarget.new(GLib::Type["gchararray"], Gdk::DragAction::MOVE)
    end
  end
end
