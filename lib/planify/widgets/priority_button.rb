# frozen_string_literal: true

module Planify
  # core/Widgets/PriorityButton.vala. A flat flag icon with its own popover
  # of the four Todoist priorities, coloured to match whichever one is set.
  # Reports a change through a callback, the way DateTimePicker and
  # PriorityPicker do, rather than through a GObject signal.
  class PriorityButton
    LEVELS = [Item::PRIORITY_1, Item::PRIORITY_2, Item::PRIORITY_3, Item::PRIORITY_4].freeze

    def initialize(&on_change)
      @on_change = on_change
    end

    def build
      @build ||= button.tap do |b|
        b.child = priority_image
        b.popover = popover

        popover.child = menu_box

        menu_box.tap do |box|
          priority_items.each { |item| box.append(item.build) }
        end

        reset
      end
    end

    def priority_items
      @priority_items ||= LEVELS.each_with_index.map do |level, index|
        ContextMenu::MenuItem.new(
          Item.new(priority: level).priority_text,
          icon: "flag-outline-thick-symbolic",
        ) { select(level) }.tap { |item| item.build.add_css_class("priority-#{index + 1}-button") }
      end
    end

    def select(level)
      popover.popdown
      set_priority(level)
      @on_change&.call(level)
    end

    def update_from_item(item) = set_priority(item.priority.to_i)

    def set_priority(priority)
      sample = Item.new(priority: priority)
      button.tooltip_text = sample.priority_text
      if priority == Item::PRIORITY_4
        priority_image.css_classes = []
      else
        priority_image.css_classes = ["priority-#{LEVELS.index(priority) + 1}-icon"]
      end
      tint(sample.priority_color)
    end

    def reset
      priority_image.icon_name = "flag-outline-thick-symbolic"
      priority_image.css_classes = []
      tint(Item.new(priority: Item::PRIORITY_4).priority_color)
    end

    def tint(hex)
      Gtk::CssProvider.new.tap do |provider|
        provider.load(data: "image { color: #{hex}; }")
        priority_image.style_context.add_provider(provider, Gtk::StyleProvider::PRIORITY_APPLICATION)
      end
    end

    def button
      @button ||= Gtk::MenuButton.new.tap do |b|
        b.add_css_class("flat")
        b.valign = :center
        b.halign = :center
        b.tooltip_text = _("Set The Priority")
      end
    end

    def priority_image = @priority_image ||= Gtk::Image.new(icon_name: "flag-outline-thick-symbolic")

    def popover = @popover ||= Gtk::Popover.new.tap { |p| p.has_arrow = false }

    def menu_box
      @menu_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.margin_top = 3
        box.margin_bottom = 3
      end
    end
  end
end
