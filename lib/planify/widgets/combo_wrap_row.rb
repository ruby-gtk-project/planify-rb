# frozen_string_literal: true

module Planify
  # src/Widgets/ComboWrapRow.vala. A preferences row that lays its options out
  # as a wrapping strip of small buttons instead of hiding them in a dropdown,
  # for the short either-or settings where seeing every choice at once is the
  # point. The selected button carries the accent class.
  #
  # Upstream uses Adw.WrapBox; the Ruby bindings have no binding for it, so a
  # Gtk::FlowBox in a single row-per-line arrangement does the wrapping.
  class ComboWrapRow
    def initialize(title = "", subtitle: "", options: [], selected: 0, &on_change)
      @title = title.to_s
      @subtitle = subtitle.to_s
      @options = options
      @selected = selected
      @on_change = on_change
      @buttons = []
    end

    attr_reader :title, :subtitle, :options, :selected

    def build
      @build ||= row.tap do |r|
        r.child = main_box

        main_box.tap do |box|
          box.append(text_box)
          box.append(wrap_box)

          text_box.tap do |text|
            text.append(title_label)
            text.append(subtitle_label)
          end
        end

        self.title = title
        self.subtitle = subtitle
        self.options = options
      end
    end

    def title=(value)
      @title = value.to_s
      title_label.label = @title
    end

    def subtitle=(value)
      @subtitle = value.to_s
      subtitle_label.label = @subtitle
    end

    # Replaces the whole strip, so a row whose choices depend on other state
    # can be refilled rather than rebuilt.
    def options=(values)
      @options = values.to_a
      @buttons = []

      while wrap_box.first_child
        wrap_box.remove(wrap_box.first_child)
      end

      @options.each_with_index do |option, index|
        option_button(option, index).tap do |button|
          @buttons << button
          wrap_box.append(button)
        end
      end

      apply_selection
    end

    def selected=(index)
      @selected = index.to_i
      apply_selection
    end

    def apply_selection
      @buttons.each_with_index do |button, index|
        if index == @selected
          button.add_css_class("color-primary")
        else
          button.remove_css_class("color-primary")
        end
      end
    end

    def pick(index)
      unless index == @selected
        self.selected = index
        @on_change&.call(index)
      end
    end

    def option_button(option, index)
      Gtk::Button.new(label: option.to_s).tap do |button|
        button.add_css_class("tiny-button")
        button.add_css_class("caption")
        button.signal_connect("clicked") { pick(index) }
      end
    end

    # --- widgets ----------------------------------------------------------

    def row
      @row ||= Adwaita::PreferencesRow.new.tap do |r|
        r.activatable = false
      end
    end

    def main_box
      @main_box ||= Gtk::Box.new(:vertical, 12).tap do |box|
        box.margin_start = 12
        box.margin_end = 12
        box.margin_top = 8
        box.margin_bottom = 8
      end
    end

    def text_box
      @text_box ||= Gtk::Box.new(:vertical, 3).tap do |box|
        box.hexpand = true
        box.valign = :center
      end
    end

    def title_label
      @title_label ||= Gtk::Label.new.tap do |label|
        label.hexpand = true
        label.xalign = 0
        label.wrap = true
      end
    end

    def subtitle_label
      @subtitle_label ||= Gtk::Label.new.tap do |label|
        label.hexpand = true
        label.xalign = 0
        label.wrap = true
        label.use_markup = true
        label.add_css_class("dim-label")
        label.add_css_class("caption")
      end
    end

    # One line's worth of buttons at a time, wrapping onto the next line when
    # the row runs out of width — what Adw.WrapBox does for upstream.
    def wrap_box
      @wrap_box ||= Gtk::FlowBox.new.tap do |box|
        box.orientation = :horizontal
        box.selection_mode = :none
        box.homogeneous = false
        box.min_children_per_line = 1
        box.max_children_per_line = 6
        box.row_spacing = 6
        box.column_spacing = 6
        box.halign = :start
      end
    end
  end
end
