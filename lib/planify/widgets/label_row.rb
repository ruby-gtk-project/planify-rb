# frozen_string_literal: true

module Planify
  # src/Layouts/LabelRow.vala. One label in the labels view: its colour, its
  # name, how many open tasks carry it, a menu, and a chevron that opens the
  # label's own filter. The row is wrapped in a ReorderChild, so the list can
  # be dragged into a new order and the new order written back as item_order.
  class LabelRow
    def initialize(window, label)
      @window = window
      @label = label
    end

    attr_reader :window, :label

    def store = Store.instance

    def build
      @build ||= row.tap do |r|
        r.child = main_revealer

        main_revealer.child = reorder.build

        handle_box.tap do |box|
          box.append(color_icon)
          box.append(name_label)
          box.append(count_revealer)
          box.append(buttons_box)

          count_revealer.child = count_label

          buttons_box.tap do |buttons|
            buttons.append(menu_button)
            buttons.append(open_button.build)
          end

          menu_button.menu_model = context_menu
        end

        register_actions
        reorder.build_drag_and_drop
        refresh

        # The row slides in rather than appearing, which is what makes a
        # freshly created label read as added rather than as always there.
        GLib::Timeout.add(main_revealer.transition_duration) do
          main_revealer.reveal_child = true
          false
        end
      end
    end

    def refresh
      name_label.label = label.name.to_s
      count.then do |pending|
        count_label.label = pending.to_s
        count_revealer.reveal_child = pending.positive?
      end
      tint(color_icon, Palette.hex(label.color))
    end

    def count = store.items_by_label(label.id).size

    def tint(image, hex)
      Gtk::CssProvider.new.tap do |provider|
        provider.load(data: "image { color: #{hex}; }")
        image.style_context.add_provider(provider, Gtk::StyleProvider::PRIORITY_APPLICATION)
      end
    end

    # Dropping a row rewrites item_order for every row in the list, since a
    # single move shifts everything below it.
    def persist_order(listbox)
      child = listbox.first_child
      index = 0
      while child
        store.label(child.name.to_s).then do |moved|
          unless moved.nil?
            moved.item_order = index
            store.update_label(moved)
          end
        end
        index += 1
        child = child.next_sibling
      end
    end

    def open
      window.show_label(label)
    end

    def edit
      Dialogs::LabelDialog.new(window, label: label).present(window.window)
    end

    def delete
      Adwaita::AlertDialog.new(
        _("Delete Label?"),
        _("“%s” will be removed from every task that carries it.") % label.name,
      ).tap do |dialog|
        dialog.add_response("cancel", _("Cancel"))
        dialog.add_response("delete", _("Delete"))
        dialog.set_response_appearance("delete", Adwaita::ResponseAppearance::DESTRUCTIVE)
        dialog.signal_connect("response") do |_, response|
          if response == "delete"
            hide_destroy
            store.delete_label(label)
          end
        end
        dialog.present(window.window)
      end
    end

    def toggle_favorite
      label.is_favorite = Record.flag(!label.favorite?)
      store.update_label(label)
    end

    # The row collapses before it is taken out, so a deletion reads as the row
    # closing up rather than as the list snapping shorter.
    def hide_destroy
      main_revealer.reveal_child = false
      GLib::Timeout.add(main_revealer.transition_duration) do
        row.parent.then do |parent|
          unless parent.nil?
            parent.remove(row)
          end
        end
        false
      end
    end

    ROW_ACTIONS = {
      "edit"     => :edit,
      "favorite" => :toggle_favorite,
      "delete"   => :delete,
    }.freeze

    def register_actions
      Gio::SimpleActionGroup.new.tap do |group|
        ROW_ACTIONS.each do |name, method|
          Gio::SimpleAction.new(name).tap do |action|
            action.signal_connect("activate") { public_send(method) }
            group.add_action(action)
          end
        end

        row.insert_action_group("label", group)
      end
    end

    def context_menu
      @context_menu ||= Gio::Menu.new.tap do |menu|
        Gio::Menu.new.tap do |section|
          section.append(_("Edit Label"), "label.edit")
          section.append(_("Toggle Favorite"), "label.favorite")
          menu.append_section(nil, section)
        end

        Gio::Menu.new.tap do |section|
          section.append(_("Delete Label"), "label.delete")
          menu.append_section(nil, section)
        end
      end
    end

    # --- widgets ----------------------------------------------------------

    # The row carries the label id as its widget name, which is how the
    # reorder handler reads an order back off the listbox after a drop.
    def row
      @row ||= Gtk::ListBoxRow.new.tap do |r|
        r.name = label.id.to_s
        r.add_css_class("row")
        r.add_css_class("transition")
        r.add_css_class("no-padding")
      end
    end

    def reorder
      @reorder ||= ReorderChild.new(handle_box, row) { |listbox| persist_order(listbox) }
    end

    def main_revealer
      @main_revealer ||= Gtk::Revealer.new.tap do |revealer|
        revealer.transition_type = :slide_down
      end
    end

    def handle_box
      @handle_box ||= Gtk::Box.new(:horizontal, 6).tap do |box|
        box.margin_start = 6
        box.margin_end = 6
        box.margin_top = 3
        box.margin_bottom = 3
      end
    end

    def color_icon
      @color_icon ||= Gtk::Image.new(icon_name: "tag-outline-symbolic").tap do |image|
        image.valign = :center
      end
    end

    def name_label
      @name_label ||= Gtk::Label.new.tap do |label_widget|
        label_widget.valign = :center
        label_widget.ellipsize = :end
      end
    end

    def count_label
      @count_label ||= Gtk::Label.new.tap do |label_widget|
        label_widget.hexpand = true
        label_widget.halign = :end
        label_widget.add_css_class("dim-label")
      end
    end

    def count_revealer
      @count_revealer ||= Gtk::Revealer.new.tap do |revealer|
        revealer.transition_type = :crossfade
        revealer.hexpand = true
        revealer.halign = :end
      end
    end

    def buttons_box = @buttons_box ||= Gtk::Box.new(:horizontal, 6)

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.icon_name = "view-more-symbolic"
        button.valign = :center
        button.halign = :center
        button.add_css_class("flat")
        button.add_css_class("dim-label")
      end
    end

    # A LoadingButton is a suggested-action button by default, which is right
    # for a dialog's submit and wrong for a chevron at the end of a row.
    def open_button
      @open_button ||= LoadingButton.new(icon: "go-next-symbolic") { open }.tap do |loading|
        loading.button.remove_css_class("suggested-action")
        loading.button.add_css_class("flat")
        loading.button.add_css_class("dim-label")
        loading.button.valign = :center
      end
    end
  end
end
