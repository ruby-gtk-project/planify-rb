# frozen_string_literal: true

module Planify
  # core/Widgets/PinButton.vala. A flat pin icon that tints when the task it
  # is attached to is pinned, and fires a callback on click rather than
  # writing anything itself — the caller decides what "pinned" means for the
  # item it owns.
  class PinButton
    def initialize(&on_click)
      @on_click = on_click
    end

    def build
      @build ||= button.tap do |b|
        b.child = pinned_image
        b.signal_connect("clicked") { @on_click&.call }
      end
    end

    def update_from_item(item) = update_request(item.pinned?)

    def update_request(pinned)
      if pinned
        pinned_image.add_css_class("pinboard-color")
      else
        pinned_image.remove_css_class("pinboard-color")
      end
    end

    def reset
      pinned_image.css_classes = []
    end

    def icon_size=(value)
      pinned_image.pixel_size = value
    end

    def no_padding=(value)
      if value
        button.add_css_class("no-padding")
      else
        button.remove_css_class("no-padding")
      end
    end

    def button
      @button ||= Gtk::Button.new.tap do |b|
        b.add_css_class("flat")
        b.valign = :center
        b.halign = :center
        b.tooltip_text = _("Pin")
      end
    end

    def pinned_image = @pinned_image ||= Gtk::Image.new(icon_name: "pin-symbolic")
  end
end
