# frozen_string_literal: true

module Planify
  # core/Widgets/TextView.vala. A Gtk::TextView with a placeholder, which
  # GtkTextView itself has none of: the placeholder text is written into the
  # buffer at half opacity whenever the view is unfocused and empty, and taken
  # straight back out the moment the view gains focus.
  #
  # Upstream also toggles the window's type-anywhere accelerator around focus
  # so typing in a note does not open quick-add; this port never installs that
  # accelerator, so the enter and leave callbacks are all that is left of it.
  class TextView
    def initialize(placeholder: "", &on_change)
      @placeholder = placeholder.to_s
      @on_change = on_change
      @showing_placeholder = false
      @updating = false
    end

    attr_reader :placeholder

    def build
      @build ||= text_view.tap do |view|
        view.add_controller(focus_controller)

        focus_controller.tap do |controller|
          controller.signal_connect("enter") { handle_focus_in }
          controller.signal_connect("leave") { handle_focus_out }
        end

        buffer.signal_connect("changed") { handle_changed }

        update_placeholder_visibility
      end
    end

    def on_change(&block)
      @on_change = block
    end

    def on_enter(&block)
      @on_enter = block
    end

    def on_leave(&block)
      @on_leave = block
    end

    # --- text -------------------------------------------------------------

    # The placeholder lives in the buffer, so it has to be filtered out of
    # every read or it would be saved as if the user had typed it.
    def text
      if showing_placeholder?
        ""
      else
        buffer.text.strip
      end
    end

    def text=(value)
      without_notifying do
        buffer.text = value.to_s
        @showing_placeholder = false
        text_view.opacity = 1
      end
      update_placeholder_visibility
    end

    def placeholder_text=(value)
      @placeholder = value.to_s
      update_placeholder_visibility
    end

    def editable=(value)
      text_view.editable = value
    end

    def showing_placeholder? = @showing_placeholder == true

    def focused? = text_view.has_focus?

    def grab_focus = text_view.grab_focus

    def buffer = text_view.buffer

    # --- focus ------------------------------------------------------------

    def handle_focus_in
      if showing_placeholder?
        without_notifying do
          buffer.text = ""
          text_view.opacity = 1
          @showing_placeholder = false
        end
      end
      @on_enter&.call
    end

    def handle_focus_out
      update_placeholder_visibility
      @on_leave&.call
    end

    def handle_changed
      unless @updating
        @on_change&.call(text)
      end
    end

    def update_placeholder_visibility
      if show_placeholder?
        without_notifying do
          @showing_placeholder = true
          buffer.text = placeholder
          text_view.opacity = 0.5
        end
      elsif showing_placeholder? && focused?
        without_notifying do
          buffer.text = ""
          text_view.opacity = 1
          @showing_placeholder = false
        end
      end
    end

    def show_placeholder?
      !focused? && buffer.text.strip.empty? && !placeholder.empty?
    end

    # Writing the placeholder into the buffer fires `changed` just like a
    # keystroke would, so the change callback is muted while it happens.
    def without_notifying
      @updating = true
      yield
      @updating = false
    end

    # --- widgets ----------------------------------------------------------

    def text_view
      @text_view ||= Gtk::TextView.new.tap do |view|
        view.wrap_mode = :word_char
        view.accepts_tab = false
        view.add_css_class("flat")
      end
    end

    def focus_controller = @focus_controller ||= Gtk::EventControllerFocus.new
  end
end
