# frozen_string_literal: true

module Planify
  module Views
    # What every view shares: a toolbar with a header, a scrolled list of task
    # rows, an empty state, and a floating add button. Subclasses say what the
    # title is and which items belong in the list.
    class BaseView
      def initialize(window)
        @window = window
        @rows = {}
      end

      attr_reader :window, :rows

      def store = Store.instance

      def root = build

      def build
        @build ||= overlay.tap do |o|
          o.child = toolbar
          o.add_overlay(add_button)

          toolbar.tap do |view|
            view.add_top_bar(header)
            view.content = stack

            header.tap do |h|
              h.title_widget = window_title
              h.pack_end(menu_button)
              menu_button.menu_model = view_menu
            end

            stack.tap do |s|
              s.add_named(scrolled, "list")
              s.add_named(empty_page, "empty")
            end

            scrolled.child = clamp
            clamp.child = list_box
          end

          add_button.signal_connect("clicked") { add_task }

          subscribe
        end
      end

      # Every view reacts to the same item events; redrawing the whole list is
      # what upstream does too when a filter's contents change.
      def subscribe
        %i[item_added item_updated item_deleted label_updated label_deleted]
          .each { |event| store.on(event, owner: self) { refresh } }
      end

      def refresh
        window_title.title = title
        window_title.subtitle = subtitle
        rebuild
      end

      # Rows are reused across refreshes. Rebuilding every row on every item
      # event is both wasteful and, with a MenuButton per row, enough widget
      # churn to trip a GC bug in the introspection bindings — so only the
      # rows that actually appeared or disappeared are touched, and the rest
      # are refreshed in place.
      def rebuild
        ordered.then do |items|
          drop_removed(items.map(&:id))
          sync_rows(items)
          if items.empty?
            stack.visible_child_name = "empty"
          else
            stack.visible_child_name = "list"
          end
        end
      end

      def drop_removed(ids)
        (@rows.keys - ids).each do |id|
          list_box.remove(@rows.delete(id))
        end
      end

      def sync_rows(items)
        items.each_with_index do |item, index|
          if @rows.key?(item.id)
            row_for(item.id).refresh
          else
            insert_row(item, index)
          end
        end

        reorder(items)
      end

      def row_objects = @row_objects ||= {}

      def row_for(id) = row_objects.fetch(id)

      def insert_row(item, index)
        ItemRow.new(window, item).tap do |row|
          row_objects[item.id] = row
          @rows[item.id] = row.build
          list_box.insert(row.build, index)
        end
      end

      # A row whose position changed is moved rather than recreated.
      def reorder(items)
        items.each_with_index do |item, index|
          @rows[item.id].then do |row|
            if row.index != index
              list_box.remove(row)
              list_box.insert(row, index)
            end
          end
        end
      end

      def add_task
        QuickAdd.new(window, **quick_add_defaults).present(window.window)
      end

      # Views that mix in Sorting order their items; the rest take them as the
      # store handed them over.
      def ordered
        if respond_to?(:apply_sort)
          apply_sort(items)
        else
          items
        end
      end

      # --- subclass contract ----------------------------------------------

      def title = ""

      def subtitle = ""

      def items = []

      def quick_add_defaults = {}

      def empty_title = _("No tasks")

      def empty_description = _("Nothing to do here.")

      def empty_icon = "check-round-outline-symbolic"

      def view_menu
        @view_menu ||= Gio::Menu.new.tap do |menu|
          menu.append(_("Add Task"), "win.new-item")
        end
      end

      # --- widgets ---------------------------------------------------------

      def overlay = @overlay ||= Gtk::Overlay.new

      def toolbar = @toolbar ||= Adwaita::ToolbarView.new

      def header
        @header ||= Adwaita::HeaderBar.new.tap do |h|
          h.add_css_class("flat")
        end
      end

      def window_title = @window_title ||= Adwaita::WindowTitle.new("", "")

      def menu_button
        @menu_button ||= Gtk::MenuButton.new.tap do |button|
          button.icon_name = "view-more-symbolic"
          button.add_css_class("flat")
        end
      end

      def stack = @stack ||= Gtk::Stack.new

      def scrolled
        @scrolled ||= Gtk::ScrolledWindow.new.tap do |scroll|
          scroll.hscrollbar_policy = :never
          scroll.vexpand = true
        end
      end

      def clamp
        @clamp ||= Adwaita::Clamp.new.tap do |c|
          c.maximum_size = 720
          c.margin_start = 12
          c.margin_end = 12
          c.margin_top = 12
          c.margin_bottom = 64
        end
      end

      def list_box
        @list_box ||= Gtk::ListBox.new.tap do |list|
          list.selection_mode = :none
          list.add_css_class("background")
        end
      end

      def empty_page
        @empty_page ||= Adwaita::StatusPage.new.tap do |page|
          page.icon_name = empty_icon
          page.title = empty_title
          page.description = empty_description
        end
      end

      # The plus button upstream floats over the list and can be dragged; it
      # floats here, without the drag.
      def add_button
        @add_button ||= Gtk::Button.new(icon_name: "plus-large-symbolic").tap do |button|
          button.add_css_class("suggested-action")
          button.add_css_class("circular")
          button.halign = :end
          button.valign = :end
          button.margin_end = 24
          button.margin_bottom = 24
          button.width_request = 48
          button.height_request = 48
          button.tooltip_text = _("Add Task")
        end
      end
    end
  end
end
