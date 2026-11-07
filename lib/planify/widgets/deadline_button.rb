# frozen_string_literal: true

module Planify
  # core/Widgets/DeadlineButton.vala. A flat icon button carrying a popover
  # of quick deadline suggestions, a calendar, and a delete button, same as
  # upstream's plain BUTTON variant (the detail-row and card variants are
  # what ItemDetail already builds inline).
  class DeadlineButton
    SUGGESTIONS = [
      [-> { _("Tomorrow") }, 1],
      [-> { _("In 3 days") }, 3],
      [-> { _("Next week") }, 7],
      [-> { _("In 2 weeks") }, 14],
    ].freeze

    def initialize(&on_date_selected)
      @on_date_selected = on_date_selected
      @deadline = nil
    end

    attr_reader :deadline

    def build
      @build ||= main_revealer.tap do |r|
        r.child = button

        button.tap do |b|
          b.child = deadline_icon
          b.popover = popover
        end

        popover.child = scrolled
        scrolled.child = content_box

        content_box.tap do |box|
          box.append(suggested_box)
          box.append(calendar)
          box.append(delete_revealer)

          suggestion_buttons.each { |btn| suggested_box.append(btn) }
          delete_revealer.child = delete_button

          calendar.signal_connect("day-selected") do
            pick(DateTimePicker.calendar_time(calendar))
          end

          delete_button.signal_connect("clicked") { pick(nil) }
        end
      end
    end

    def datetime=(value)
      @deadline = value
      delete_revealer.reveal_child = !value.nil?
      if value.nil?
        calendar.select_day(DateTimePicker.glib_datetime(Time.now))
        update_selection(nil)
      else
        calendar.select_day(DateTimePicker.glib_datetime(value))
        update_selection(value)
      end
    end

    def reveal_content=(value)
      main_revealer.reveal_child = value
    end

    def pick(date)
      self.datetime = date
      popover.popdown
      @on_date_selected&.call(date)
    end

    def update_selection(date)
      suggestion_buttons.each_with_index do |btn, index|
        target = Datetime.strip_time(Time.now + (SUGGESTIONS[index][1] * 86_400))
        if !date.nil? && Datetime.same_day?(date, target)
          btn.add_css_class("suggested-button-selected")
        else
          btn.remove_css_class("suggested-button-selected")
        end
      end
    end

    def suggestion_buttons
      @suggestion_buttons ||= SUGGESTIONS.map do |title, offset|
        build_suggestion(title.call, offset)
      end
    end

    def build_suggestion(title, offset)
      Gtk::Button.new.tap do |btn|
        btn.add_css_class("suggestion-chip")
        btn.tooltip_text = Datetime.relative(Time.now + (offset * 86_400))
        btn.child = Gtk::Box.new(:horizontal, 6).tap do |box|
          box.margin_start = 9
          box.margin_end = 9
          box.margin_top = 6
          box.margin_bottom = 6
          box.append(Gtk::Label.new(title))
        end
        btn.signal_connect("clicked") { pick(Datetime.strip_time(Time.now + (offset * 86_400))) }
      end
    end

    def main_revealer
      @main_revealer ||= Gtk::Revealer.new.tap do |r|
        r.transition_type = :slide_left
        r.reveal_child = true
      end
    end

    def button
      @button ||= Gtk::MenuButton.new.tap do |b|
        b.add_css_class("flat")
        b.valign = :center
        b.tooltip_text = _("The latest date to complete this task")
      end
    end

    def deadline_icon = @deadline_icon ||= Gtk::Image.new(icon_name: "delay-long-small-symbolic")

    def popover
      @popover ||= Gtk::Popover.new.tap do |p|
        p.has_arrow = false
        p.add_css_class("popover-contents")
      end
    end

    def scrolled
      @scrolled ||= Gtk::ScrolledWindow.new.tap do |s|
        s.hscrollbar_policy = :never
        s.vscrollbar_policy = :automatic
        s.propagate_natural_height = true
        s.max_content_height = 425
      end
    end

    def content_box
      @content_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.margin_start = 12
        box.margin_end = 12
        box.margin_top = 12
      end
    end

    def suggested_box
      @suggested_box ||= Gtk::Box.new(:horizontal, 6).tap do |box|
        box.margin_bottom = 6
      end
    end

    def calendar = @calendar ||= Gtk::Calendar.new

    def delete_button
      @delete_button ||= Gtk::Button.new(label: _("Delete")).tap do |b|
        b.margin_top = 12
        b.margin_bottom = 12
        b.add_css_class("destructive-action")
      end
    end

    def delete_revealer
      @delete_revealer ||= Gtk::Revealer.new.tap do |r|
        r.transition_type = :slide_down
        r.reveal_child = false
      end
    end
  end
end
