# frozen_string_literal: true

module Planify
  # core/Widgets/ColorPickerRow.vala: the Todoist palette as a grid of
  # swatches. The selected key is read back with `color`.
  class ColorPicker
    def initialize(color = "blue")
      @color = color
      @swatches = {}
    end

    attr_reader :color

    def build
      @build ||= flowbox.tap do |box|
        Palette.keys.each do |key|
          swatch(key).tap do |button|
            @swatches[key] = button
            box.append(button)
          end
        end

        box.signal_connect("child-activated") do |_, child|
          @color = @swatches.key(child.child)
          refresh
        end
      end
    end

    def color=(key)
      @color = key
      refresh
    end

    def refresh
      @swatches.each do |key, button|
        if key == @color
          button.child.icon_name = "check-plain-symbolic"
        else
          button.child.icon_name = ""
        end
      end
    end

    def swatch(key)
      Gtk::Button.new.tap do |button|
        button.add_css_class("circular")
        button.tooltip_text = Palette.name(key)
        button.width_request = 28
        button.height_request = 28
        button.child = Gtk::Image.new(icon_name: "")
        apply_color(button, key)
        button.signal_connect("clicked") do
          @color = key
          refresh
        end
      end
    end

    # Per-widget CSS is how upstream paints these; a provider per colour is
    # cheap enough at twenty colours.
    def apply_color(button, key)
      Gtk::CssProvider.new.tap do |provider|
        provider.load(data: "button { background: #{Palette.hex(key)}; color: #fff; }")
        button.style_context.add_provider(provider, Gtk::StyleProvider::PRIORITY_APPLICATION)
      end
    end

    def flowbox
      @flowbox ||= Gtk::FlowBox.new.tap do |box|
        box.max_children_per_line = 10
        box.min_children_per_line = 5
        box.selection_mode = :none
        box.homogeneous = true
        box.row_spacing = 6
        box.column_spacing = 6
        box.margin_top = 6
        box.margin_bottom = 6
      end
    end
  end
end
