# frozen_string_literal: true

module Planify
  # core/Widgets/StatusButton.vala. A card-style menu button offering the two
  # states a task can be in — To Do or Complete — and reporting the choice
  # through a callback rather than through a GObject signal, the way the
  # other reusable buttons here do.
  class StatusButton
    def initialize(&on_change)
      @on_change = on_change
    end

    def build
      @build ||= button.tap do |b|
        b.child = card_grid
        b.popover = popover

        card_grid.tap do |grid|
          grid.attach(status_image, 0, 0, 1, 2)
          grid.attach(title_label, 1, 0, 1, 1)
          grid.attach(value_label, 1, 1, 1, 1)
        end

        popover.child = menu_box

        menu_box.tap do |box|
          box.append(todo_item.build)
          box.append(complete_item.build)
        end
      end
    end

    def todo_item
      @todo_item ||= ContextMenu::MenuItem.new(_("To Do"), icon: "check-round-outline-symbolic") do
        popover.popdown
        set_status(false)
        @on_change&.call(false)
      end
    end

    def complete_item
      @complete_item ||= ContextMenu::MenuItem.new(_("Complete"), icon: "check-round-outline-symbolic") do
        popover.popdown
        set_status(true)
        @on_change&.call(true)
      end.tap { |item| item.build.add_css_class("completed-color") }
    end

    def update_from_item(item) = set_status(item.checked?)

    def set_status(active)
      if active
        status_image.add_css_class("completed-image-color")
        value_label.label = _("Complete")
      else
        status_image.remove_css_class("completed-image-color")
        value_label.label = _("To Do")
      end
    end

    def button
      @button ||= Gtk::MenuButton.new.tap do |b|
        b.css_classes = ["flat", "card", "activatable", "menu-button-no-padding"]
        b.hexpand = true
        b.tooltip_text = _("Set The Status")
      end
    end

    def popover = @popover ||= Gtk::Popover.new.tap { |p| p.has_arrow = false }

    def menu_box
      @menu_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.margin_top = 3
        box.margin_bottom = 3
      end
    end

    def status_image = @status_image ||= Gtk::Image.new(icon_name: "check-round-outline-symbolic")

    def title_label
      @title_label ||= Gtk::Label.new(_("Status")).tap do |label|
        label.halign = :start
        label.css_classes = ["title-4", "caption", "font-bold"]
      end
    end

    def value_label
      @value_label ||= Gtk::Label.new(_("To Do")).tap do |label|
        label.xalign = 0
        label.halign = :start
        label.add_css_class("caption")
      end
    end

    def card_grid
      @card_grid ||= Gtk::Grid.new.tap do |grid|
        grid.column_spacing = 12
        grid.margin_start = 12
        grid.margin_end = 6
        grid.margin_top = 6
        grid.margin_bottom = 6
        grid.vexpand = true
        grid.hexpand = true
      end
    end
  end
end
