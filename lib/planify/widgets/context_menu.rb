# frozen_string_literal: true

module Planify
  # core/Widgets/ContextMenu. Planify builds its popovers out of these rather
  # than out of Gio::Menu, because the rows carry colour swatches, switches,
  # check marks and live subtitles that a menu model cannot express.
  module ContextMenu
    # A plain activatable row: icon, label, optional secondary text.
    class MenuItem
      def initialize(title, icon: nil, &on_activate)
        @title = title
        @icon = icon
        @on_activate = on_activate
      end

      attr_reader :title, :icon

      def build
        @build ||= button.tap do |b|
          b.child = box

          box.tap do |content|
            unless icon.nil?
              content.append(image)
            end
            content.append(label)
            content.append(secondary_label)
          end

          b.signal_connect("clicked") { @on_activate&.call }
        end
      end

      def secondary=(text)
        secondary_label.label = text.to_s
        secondary_label.visible = !text.to_s.empty?
      end

      def title=(text)
        @title = text
        label.label = text.to_s
      end

      def sensitive=(value)
        button.sensitive = value
      end

      def destructive!
        button.add_css_class("destructive")
        image&.add_css_class("destructive")
      end

      def button
        @button ||= Gtk::Button.new.tap do |b|
          b.add_css_class("flat")
          b.add_css_class("menu-item")
        end
      end

      def box
        @box ||= Gtk::Box.new(:horizontal, 12).tap do |b|
          b.margin_start = 3
          b.margin_end = 3
        end
      end

      def image
        unless icon.nil?
          @image ||= Gtk::Image.new(icon_name: icon).tap { |i| i.pixel_size = 16 }
        end
      end

      def label
        @label ||= Gtk::Label.new(title).tap do |l|
          l.xalign = 0
          l.hexpand = true
        end
      end

      def secondary_label
        @secondary_label ||= Gtk::Label.new("").tap do |l|
          l.add_css_class("dim-label")
          l.add_css_class("caption")
          l.visible = false
        end
      end
    end

    # A row whose trailing widget is a switch.
    class MenuSwitch
      def initialize(title, active: false, icon: nil, &on_toggle)
        @title = title
        @icon = icon
        @active = active
        @on_toggle = on_toggle
      end

      attr_reader :title, :icon

      def build
        @build ||= box.tap do |b|
          unless icon.nil?
            b.append(image)
          end
          b.append(label)
          b.append(switch)

          switch.signal_connect("notify::active") { @on_toggle&.call(switch.active?) }
          b.add_controller(gesture)
          gesture.signal_connect("released") { switch.active = !switch.active? }
        end
      end

      def active? = switch.active?

      def active=(value)
        switch.active = value
      end

      def box
        @box ||= Gtk::Box.new(:horizontal, 12).tap do |b|
          b.margin_start = 6
          b.margin_end = 6
          b.margin_top = 6
          b.margin_bottom = 6
        end
      end

      def image
        unless icon.nil?
          @image ||= Gtk::Image.new(icon_name: icon)
        end
      end

      def label
        @label ||= Gtk::Label.new(title).tap do |l|
          l.xalign = 0
          l.hexpand = true
        end
      end

      def switch
        @switch ||= Gtk::Switch.new.tap do |s|
          s.valign = :center
          s.active = @active
        end
      end

      def gesture = @gesture ||= Gtk::GestureClick.new
    end

    # A row that expands into a list of choices, the current one ticked.
    class MenuPicker
      def initialize(title, options, selected = 0, &on_select)
        @title = title
        @options = options
        @selected = selected
        @on_select = on_select
        @rows = []
      end

      attr_reader :title, :options, :selected

      def build
        @build ||= expander.tap do |row|
          row.title = title
          row.subtitle = options[selected].to_s

          options.each_with_index do |option, index|
            option_row(option, index).tap do |child|
              @rows << child
              row.add_row(child)
            end
          end
        end
      end

      def selected=(index)
        @selected = index
        expander.subtitle = options[index].to_s
        @rows.each_with_index { |row, i| tick(row).visible = i == index }
      end

      def option_row(option, index)
        Adwaita::ActionRow.new.tap do |row|
          row.title = option.to_s
          row.activatable = true
          row.add_suffix(
            Gtk::Image.new(icon_name: "check-plain-symbolic").tap do |check|
                        check.visible = index == @selected
                        @ticks ||= {}
                        @ticks[row] = check
                      end,
          )
          row.signal_connect("activated") do
            self.selected = index
            @on_select&.call(index)
          end
        end
      end

      def tick(row) = @ticks.fetch(row)

      def expander = @expander ||= Adwaita::ExpanderRow.new
    end

    # Several options, any number of them ticked — the filter pickers use it.
    class MenuCheckPicker
      def initialize(title, options, selected = [], &on_change)
        @title = title
        @options = options
        @selected = selected.dup
        @on_change = on_change
        @checks = {}
      end

      attr_reader :title, :options, :selected

      def build
        @build ||= expander.tap do |row|
          row.title = title
          refresh_subtitle

          options.each_with_index do |option, index|
            row.add_row(option_row(option, index))
          end
        end
      end

      def option_row(option, index)
        Adwaita::ActionRow.new.tap do |row|
          row.title = option.to_s
          row.activatable = true
          row.add_suffix(check_for(index))
          row.signal_connect("activated") { toggle(index) }
        end
      end

      def check_for(index)
        Gtk::CheckButton.new.tap do |check|
          check.active = @selected.include?(index)
          check.sensitive = false
          check.valign = :center
          @checks[index] = check
        end
      end

      def toggle(index)
        if @selected.include?(index)
          @selected.delete(index)
        else
          @selected << index
        end

        @checks[index].active = @selected.include?(index)
        refresh_subtitle
        @on_change&.call(@selected)
      end

      def refresh_subtitle
        if @selected.empty?
          expander.subtitle = _("None")
        else
          expander.subtitle = @selected.sort.map { |i| options[i] }.join(", ")
        end
      end

      def expander = @expander ||= Adwaita::ExpanderRow.new
    end

    # A hairline between groups of rows.
    class MenuSeparator
      def build
        @build ||= Gtk::Separator.new(:horizontal).tap do |separator|
          separator.margin_top = 3
          separator.margin_bottom = 3
        end
      end
    end

    # The popover these rows live in. `add` takes any of the classes above.
    class Menu
      def initialize(width: 250)
        @width = width
      end

      def build
        @build ||= popover.tap do |p|
          p.child = box
        end
      end

      def add(*entries)
        entries.each { |entry| box.append(entry.respond_to?(:build) ? entry.build : entry) }
        self
      end

      def popup = popover.popup

      def popdown = popover.popdown

      def popover
        @popover ||= Gtk::Popover.new.tap do |p|
          p.has_arrow = false
          p.width_request = @width
        end
      end

      def box
        @box ||= Gtk::Box.new(:vertical, 0).tap do |b|
          b.margin_start = 6
          b.margin_end = 6
          b.margin_top = 6
          b.margin_bottom = 6
        end
      end
    end
  end
end
