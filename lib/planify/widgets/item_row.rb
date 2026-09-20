# frozen_string_literal: true

module Planify
  # Layouts/ItemRow.vala. A row is a checkbox, the content, an optional
  # description preview, and a strip of chips for the due date, labels and
  # subtask progress. Activating it opens the task in the detail sidebar.
  class ItemRow
    def initialize(window, item, depth: 0)
      @window = window
      @item = item
      @depth = depth
      @subrows = {}
    end

    attr_reader :window, :item, :depth

    def build
      @build ||= row.tap do |r|
        r.child = outer_box

        outer_box.tap do |outer|
          outer.append(main_box)
          outer.append(subitems_revealer)

          main_box.tap do |box|
            box.append(check_button)
            box.append(text_box)
            box.append(actions_box)


            check_button.signal_connect("toggled") { toggle_checked }

            text_box.tap do |text|
              text.append(content_label)
              text.append(description_label)
              text.append(chips_box)

              chips_box.tap do |chips|
                chips.append(due_label)
                chips.append(deadline_label)
                chips.append(subtasks_label)
                chips.append(labels_box)
                chips.append(recurring_icon)
              end
            end

            box.append(priority_icon)

            actions_box.tap do |actions|
              actions.append(pin_button)
              actions.append(menu_button)

              pin_button.signal_connect("clicked") { toggle_pinned }
              menu_button.menu_model = context_menu
            end
          end

          subitems_revealer.child = subitems_box
        end

        r.add_controller(click_gesture)
        click_gesture.signal_connect("released") { window.show_item(item) }

        # Upstream reveals a row's buttons only under the pointer; leaving them
        # on turns a list of tasks into a wall of icons.
        r.signal_connect("state-flags-changed") do
          r.state_flags.then do |flags|
            actions_box.visible = flags.prelight? || flags.selected? || item.pinned?
          end
        end

        register_actions
        refresh
      end
    end

    def store = Store.instance

    # --- state ----------------------------------------------------------

    def refresh
      check_button.active = item.checked?
      content_label.label = item.content.to_s
      if item.checked?
        content_label.add_css_class("dim-label")
      end
      unless item.checked?
        content_label.remove_css_class("dim-label")
      end
      apply_strikethrough

      description_label.label = item.description.to_s.strip.lines.first.to_s.strip
      description_label.visible =
        Settings.get_boolean("description-preview") && !description_label.label.empty?

      refresh_due
      refresh_deadline
      refresh_labels
      refresh_subtasks
      refresh_priority

      recurring_icon.visible = item.recurring?
      if item.pinned?
        pin_button.icon_name = "pin-symbolic"
      else
        pin_button.icon_name = "pin-symbolic"
      end
      if item.checked?
        row.add_css_class("complete-animation")
      end
    end

    def apply_strikethrough
      if item.checked? && Settings.get_boolean("underline-completed-tasks")
        content_label.attributes = strikethrough_attributes
      else
        content_label.attributes = Pango::AttrList.new
      end
    end

    def strikethrough_attributes
      Pango::AttrList.new.tap do |attributes|
        attributes.insert(Pango::AttrStrikethrough.new(true))
      end
    end

    def refresh_due
      item.due_date.then do |due|
        due_label.visible = !due.nil?

        unless due.nil?
          due_label.label = Datetime.relative(due)
          due_label.remove_css_class("error")
          due_label.remove_css_class("success")
          if Datetime.overdue?(due)
            due_label.add_css_class("error")
          end
          if Datetime.today?(due)
            due_label.add_css_class("success")
          end
        end
      end
    end

    def refresh_deadline
      item.deadline.then do |deadline|
        deadline_label.visible = !deadline.nil?
        unless deadline.nil?
          deadline_label.label = _("Deadline: %s") % Datetime.relative(deadline)
        end
      end
    end

    def refresh_labels
      while labels_box.first_child
        labels_box.remove(labels_box.first_child)
      end

      item.label_objects.each { |label| labels_box.append(label_chip(label)) }
      labels_box.visible = !item.label_objects.empty?
    end

    def label_chip(label)
      Gtk::Label.new(label.name).tap do |chip|
        chip.add_css_class("caption")
        chip.add_css_class("label-chip")
        Gtk::CssProvider.new.tap do |provider|
          provider.load(data: "label { color: #{Palette.hex(label.color)}; }")
          chip.style_context.add_provider(provider, Gtk::StyleProvider::PRIORITY_APPLICATION)
        end
      end
    end

    def refresh_subtasks
      item.subitems.then do |subitems|
        subtasks_label.visible = !subitems.empty?
        subtasks_label.label = "%d/%d" % [subitems.count(&:checked?), subitems.size]
        rebuild_subitems(subitems)
      end
    end

    def rebuild_subitems(subitems)
      while subitems_box.first_child
        subitems_box.remove(subitems_box.first_child)
      end

      subitems.each do |subitem|
        ItemRow.new(window, subitem, depth: depth + 1).build.then { |sub| subitems_box.append(sub) }
      end

      subitems_revealer.reveal_child = !subitems.empty? && !item.collapsed?
    end

    def refresh_priority
      priority_icon.visible = item.priority.to_i != Item::PRIORITY_4
      priority_icon.icon_name = item.priority_icon
      priority_icon.tooltip_text = item.priority_text

      Gtk::CssProvider.new.tap do |provider|
        provider.load(data: "image { color: #{item.priority_color}; }")
        priority_icon.style_context.add_provider(provider, Gtk::StyleProvider::PRIORITY_APPLICATION)
      end
    end

    # --- actions --------------------------------------------------------

    def toggle_checked
      unless check_button.active? == item.checked?
        store.complete_item(item, check_button.active?)
      end
    end

    def toggle_pinned
      if item.pinned?
        item.pinned = 0
      else
        item.pinned = 1
      end
      store.update_item(item)
    end

    ROW_ACTIONS = {
      "edit"      => :edit,
      "duplicate" => :duplicate,
      "pin"       => :toggle_pinned,
      "move"      => :move,
      "delete"    => :delete,
    }.freeze

    def register_actions
      Gio::SimpleActionGroup.new.tap do |group|
        ROW_ACTIONS.each do |name, method|
          Gio::SimpleAction.new(name).tap do |action|
            action.signal_connect("activate") { public_send(method) }
            group.add_action(action)
          end
        end

        row.insert_action_group("item", group)
      end
    end

    def context_menu
      @context_menu ||= Gio::Menu.new.tap do |menu|
        Gio::Menu.new.tap do |section|
          section.append(_("Edit"), "item.edit")
          section.append(_("Duplicate"), "item.duplicate")
          section.append(_("Pin"), "item.pin")
          menu.append_section(nil, section)
        end

        Gio::Menu.new.tap do |section|
          section.append(_("Move"), "item.move")
          section.append(_("Delete Task"), "item.delete")
          menu.append_section(nil, section)
        end
      end
    end

    def edit = window.show_item(item)

    def duplicate
      Item.new(**item.to_row.except(:id)).tap do |copy|
        copy.content = _("%s (copy)") % item.content
        copy.child_order = store.next_child_order(item.project_id, item.section_id)
        store.insert_item(copy)
      end
    end

    def move
      Dialogs::ProjectDialog.move(window, item).present(window.window)
    end

    def delete
      store.trash_item(item)
      window.toast_with_undo(_("Task deleted")) { store.restore_item(item) }
    end

    # --- widgets --------------------------------------------------------

    def row
      @row ||= Gtk::ListBoxRow.new.tap do |r|
        r.add_css_class("item-row")
        r.margin_start = depth * 24
      end
    end

    def outer_box = @outer_box ||= Gtk::Box.new(:vertical, 0)

    def main_box
      @main_box ||= Gtk::Box.new(:horizontal, 9).tap do |box|
        box.margin_start = 9
        box.margin_end = 9
        box.margin_top = 6
        box.margin_bottom = 6
      end
    end

    def check_button
      @check_button ||= Gtk::CheckButton.new.tap do |check|
        check.valign = :start
        check.tooltip_text = _("Complete")
      end
    end

    def text_box
      @text_box ||= Gtk::Box.new(:vertical, 3).tap do |box|
        box.hexpand = true
      end
    end

    def content_label
      @content_label ||= Gtk::Label.new("").tap do |label|
        label.xalign = 0
        label.wrap = true
        label.wrap_mode = :word_char
      end
    end

    def description_label
      @description_label ||= Gtk::Label.new("").tap do |label|
        label.xalign = 0
        label.ellipsize = :end
        label.add_css_class("dim-label")
        label.add_css_class("caption")
      end
    end

    def chips_box = @chips_box ||= Gtk::Box.new(:horizontal, 6)

    def due_label
      @due_label ||= Gtk::Label.new("").tap do |label|
        label.add_css_class("caption")
        label.visible = false
      end
    end

    def deadline_label
      @deadline_label ||= Gtk::Label.new("").tap do |label|
        label.add_css_class("caption")
        label.add_css_class("dim-label")
        label.visible = false
      end
    end

    def subtasks_label
      @subtasks_label ||= Gtk::Label.new("").tap do |label|
        label.add_css_class("caption")
        label.add_css_class("dim-label")
        label.visible = false
      end
    end

    def labels_box = @labels_box ||= Gtk::Box.new(:horizontal, 6)

    def recurring_icon
      @recurring_icon ||= Gtk::Image.new(icon_name: "update-symbolic").tap do |image|
        image.pixel_size = 12
        image.visible = false
        image.tooltip_text = _("Repeats")
      end
    end

    def actions_box
      @actions_box ||= Gtk::Box.new(:horizontal, 3).tap do |box|
        box.valign = :start
        box.visible = false
      end
    end

    def pin_button
      @pin_button ||= Gtk::Button.new(icon_name: "pin-symbolic").tap do |button|
        button.add_css_class("flat")
        button.tooltip_text = _("Pin")
      end
    end

    def priority_icon
      @priority_icon ||= Gtk::Image.new(icon_name: "flag-outline-thick-symbolic").tap do |image|
        image.visible = false
        image.valign = :start
      end
    end

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.icon_name = "view-more-symbolic"
        button.add_css_class("flat")
        button.tooltip_text = _("Task Menu")
      end
    end

    def subitems_revealer
      @subitems_revealer ||= Gtk::Revealer.new.tap do |revealer|
        revealer.transition_type = :slide_down
      end
    end

    def subitems_box = @subitems_box ||= Gtk::Box.new(:vertical, 0)

    def click_gesture
      @click_gesture ||= Gtk::GestureClick.new.tap do |gesture|
        gesture.button = Gdk::BUTTON_PRIMARY
      end
    end
  end
end
