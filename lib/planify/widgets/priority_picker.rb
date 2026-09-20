# frozen_string_literal: true

module Planify
  # The four Todoist priorities as a menu button, coloured like the flag in a
  # task row.
  class PriorityPicker
    LEVELS = [Item::PRIORITY_1, Item::PRIORITY_2, Item::PRIORITY_3, Item::PRIORITY_4].freeze

    def initialize(priority = Item::PRIORITY_4, &on_change)
      @priority = priority
      @on_change = on_change
    end

    attr_reader :priority

    def build
      @build ||= button.tap do |b|
        b.popover = popover

        popover.child = listbox

        listbox.tap do |list|
          LEVELS.each { |level| list.append(priority_row(level)) }

          list.signal_connect("row-activated") do |_, row|
            self.priority = LEVELS[row.index]
            popover.popdown
            @on_change&.call(@priority)
          end
        end
      end
    end

    def priority=(value)
      @priority = value
      icon.icon_name = sample_item.priority_icon
      button.tooltip_text = sample_item.priority_text
      apply_color
    end

    def sample_item = Item.new(priority: @priority)

    def apply_color
      Gtk::CssProvider.new.tap do |provider|
        provider.load(data: "image { color: #{sample_item.priority_color}; }")
        icon.style_context.add_provider(provider, Gtk::StyleProvider::PRIORITY_APPLICATION)
      end
    end

    def priority_row(level)
      Gtk::ListBoxRow.new.tap do |row|
        row.child = Gtk::Box.new(:horizontal, 9).tap do |box|
          box.margin_start = 9
          box.margin_end = 9
          box.margin_top = 3
          box.margin_bottom = 3
          box.append(Gtk::Image.new(icon_name: "flag-outline-thick-symbolic"))
          box.append(Gtk::Label.new(Item.new(priority: level).priority_text))
        end
      end
    end

    def button
      @button ||= Gtk::MenuButton.new.tap do |b|
        b.add_css_class("flat")
        b.child = icon
        b.tooltip_text = _("Priority")
      end
    end

    def icon = @icon ||= Gtk::Image.new(icon_name: "flag-outline-thick-symbolic")

    def popover = @popover ||= Gtk::Popover.new

    def listbox
      @listbox ||= Gtk::ListBox.new.tap do |list|
        list.selection_mode = :none
        list.add_css_class("menu-listbox")
      end
    end
  end
end
