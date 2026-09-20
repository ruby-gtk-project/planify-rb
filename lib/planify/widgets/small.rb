# frozen_string_literal: true

module Planify
  # The small reusable pieces from core/Widgets: the progress ring, the
  # project icon, the button that shows a spinner while work is in flight,
  # and the label chips a task row carries.

  # core/Widgets/CircularProgressBar.vala.
  class CircularProgressBar
    def initialize(size: 16, line_width: 2)
      @size = size
      @line_width = line_width
      @percentage = 0.0
      @color = "blue"
    end

    attr_reader :percentage, :color

    def build
      @build ||= area.tap do |a|
        a.set_draw_func { |_, context, width, height| draw(context, width, height) }
      end
    end

    def percentage=(value)
      @percentage = value.to_f.clamp(0.0, 1.0)
      area.queue_draw
    end

    def color=(value)
      @color = value
      area.queue_draw
    end

    # A dimmed full ring under a solid arc, starting at twelve o'clock.
    def draw(context, width, height)
      Palette.rgba(color).then do |rgba|
        radius = ([width, height].min / 2.0) - @line_width
        centre_x = width / 2.0
        centre_y = height / 2.0

        context.set_line_width(@line_width)
        context.set_source_rgba(
          rgba.red,
          rgba.green,
          rgba.blue,
          0.3,
        )
        context.arc(
          centre_x,
          centre_y,
          radius,
          0,
          2 * Math::PI,
        )
        context.stroke

        unless percentage.zero?
          context.set_source_rgba(
            rgba.red,
            rgba.green,
            rgba.blue,
            1.0,
          )
          context.arc(

            centre_x,

            centre_y,

            radius,

            -Math::PI / 2,
            (-Math::PI / 2) + (2 * Math::PI * percentage),
          )
          context.stroke
        end
      end
    end

    def area
      @area ||= Gtk::DrawingArea.new.tap do |a|
        a.set_size_request(@size, @size)
        a.valign = :center
        a.halign = :center
      end
    end
  end

  # core/Widgets/IconColorProject.vala: the emoji or the progress ring,
  # whichever the project's icon style says.
  class IconColorProject
    def initialize(project, size: 16)
      @project = project
      @size = size
    end

    attr_reader :project

    def build
      @build ||= stack.tap do |s|
        s.add_named(emoji_label, "emoji")
        s.add_named(progress.build, "progress")
        refresh
      end
    end

    def project=(value)
      @project = value
      refresh
    end

    def refresh
      if project.emoji?
        stack.visible_child_name = "emoji"
      else
        stack.visible_child_name = "progress"
      end
      emoji_label.label = project.emoji.to_s
      progress.color = project.color.to_s
      progress.percentage = project.percentage
    end

    def stack
      @stack ||= Gtk::Stack.new.tap do |s|
        s.width_request = @size
        s.height_request = @size
        s.valign = :center
      end
    end

    def emoji_label = @emoji_label ||= Gtk::Label.new("")

    def progress = @progress ||= CircularProgressBar.new(size: @size)
  end

  # core/Widgets/LoadingButton.vala: a button that swaps its content for a
  # spinner while an operation is in flight, keeping its size.
  class LoadingButton
    def initialize(label = "", icon: nil, &on_click)
      @label_text = label
      @icon = icon
      @on_click = on_click
    end

    def build
      @build ||= button.tap do |b|
        b.child = stack

        stack.tap do |s|
          s.add_named(content, "content")
          s.add_named(spinner, "loading")
          s.visible_child_name = "content"
        end

        b.signal_connect("clicked") { @on_click&.call }
      end
    end

    def loading = stack.visible_child_name == "loading"

    def loading=(value)
      if value
        stack.visible_child_name = "loading"
      else
        stack.visible_child_name = "content"
      end
      button.sensitive = !value
      value ? spinner.start : spinner.stop
    end

    def label=(text)
      @label_text = text
      label_widget.label = text.to_s
    end

    def button
      @button ||= Gtk::Button.new.tap do |b|
        b.add_css_class("suggested-action")
      end
    end

    def stack = @stack ||= Gtk::Stack.new

    def content
      @content ||= Gtk::Box.new(:horizontal, 6).tap do |box|
        box.halign = :center
        unless @icon.nil?
          box.append(Gtk::Image.new(icon_name: @icon))
        end
        box.append(label_widget)
      end
    end

    def label_widget = @label_widget ||= Gtk::Label.new(@label_text)

    def spinner
      @spinner ||= Gtk::Spinner.new.tap do |s|
        s.halign = :center
        s.valign = :center
      end
    end
  end

  # core/Widgets/ItemLabels.vala and ItemLabelChild.vala: the coloured chips a
  # task row shows for its labels.
  class ItemLabels
    def initialize(compact: false, &on_remove)
      @compact = compact
      @on_remove = on_remove
    end

    def build
      @build ||= box
    end

    def labels=(labels)
      while box.first_child
        box.remove(box.first_child)
      end

      labels.each { |label| box.append(chip(label)) }
      box.visible = !labels.empty?
    end

    # A chip tints itself with the label's colour at low alpha, which is how
    # upstream keeps twenty distinct labels legible next to body text.
    def chip(label)
      Gtk::Box.new(:horizontal, 3).tap do |chip|
        chip.add_css_class("label-chip")
        chip.append(Gtk::Label.new(label.name.to_s).tap { |l| l.add_css_class("caption") })
        unless @on_remove.nil?
          chip.append(remove_button(label))
        end
        tint(chip, label.color)
      end
    end

    def remove_button(label)
      Gtk::Button.new(icon_name: "window-close-symbolic").tap do |button|
        button.add_css_class("flat")
        button.add_css_class("circular")
        button.signal_connect("clicked") { @on_remove.call(label) }
      end
    end

    def tint(widget, color)
      Palette.rgba(color).then do |rgba|
        "rgba(%d, %d, %d, 0.18)" % [rgba.red * 255, rgba.green * 255, rgba.blue * 255]
          .then do |background|
          Gtk::CssProvider.new.tap do |provider|
            provider.load(
              data: "box { background: #{background}; color: #{Palette.hex(color)}; " \
                    "border-radius: 6px; padding: 1px 6px; }",
            )
            widget.style_context.add_provider(provider, Gtk::StyleProvider::PRIORITY_APPLICATION)
          end
        end
      end
    end

    def box
      @box ||= Gtk::Box.new(:horizontal, 3).tap do |b|
        b.visible = false
      end
    end
  end

  # src/Widgets/LabelsSummary.vala: "Work, Home +2" when the chips would not
  # fit, which is what the compact item row uses.
  class LabelsSummary
    MAX = 2

    def build
      @build ||= label
    end

    def labels=(labels)
      if labels.empty?
        label.label = ""
        label.visible = false
      else
        label.label = summary(labels)
        label.visible = true
      end
    end

    def summary(labels)
      labels.first(MAX).map(&:name).join(", ").then do |shown|
        if labels.size > MAX
          "#{shown} +#{labels.size - MAX}"
        else
          shown
        end
      end
    end

    def label
      @label ||= Gtk::Label.new("").tap do |l|
        l.add_css_class("caption")
        l.add_css_class("dim-label")
        l.ellipsize = :end
        l.visible = false
      end
    end
  end

  # src/Widgets/ScrolledWindow.vala: a scroller with no horizontal bar and the
  # overshoot styling Planify uses throughout.
  class ScrolledWindow
    def self.new_with(child)
      Gtk::ScrolledWindow.new.tap do |scroll|
        scroll.hscrollbar_policy = :never
        scroll.hexpand = true
        scroll.vexpand = true
        scroll.child = child
      end
    end
  end

  # src/Widgets/ErrorView.vala: what a view shows when the thing behind it
  # failed rather than being empty.
  class ErrorView
    def initialize(title, description, action_label = nil, &on_action)
      @title = title
      @description = description
      @action_label = action_label
      @on_action = on_action
    end

    def build
      @build ||= page.tap do |p|
        p.title = @title
        p.description = @description
        unless @action_label.nil?
          p.child = button
        end
      end
    end

    def description=(text)
      page.description = text.to_s
    end

    def page
      @page ||= Adwaita::StatusPage.new.tap do |p|
        p.icon_name = "dialog-warning-symbolic"
      end
    end

    def button
      @button ||= Gtk::Button.new(label: @action_label).tap do |b|
        b.add_css_class("pill")
        b.add_css_class("suggested-action")
        b.halign = :center
        b.signal_connect("clicked") { @on_action&.call }
      end
    end
  end
end
