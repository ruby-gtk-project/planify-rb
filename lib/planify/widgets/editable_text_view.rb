# frozen_string_literal: true

module Planify
  # src/Widgets/EditableTextView.vala. The note field on a project or a task:
  # a TextView that reads as plain text until it is clicked into, abbreviates
  # itself behind a Show more button when the window is narrow, and drops focus
  # on its own after a few idle seconds so the type-anywhere keys come back.
  class EditableTextView
    # Upstream's constructor default; the dialogs pass their own.
    MAX_CHARS = 100

    # How long an untouched editor keeps the focus before giving it up.
    IDLE_SECONDS = 6

    def initialize(placeholder = "", max_chars: MAX_CHARS, &on_change)
      @placeholder = placeholder.to_s
      @max_chars = max_chars
      @on_change = on_change
      @text = ""
      @expanded = false
      @editing = false
      @updating = false
      @timeout_id = nil
    end

    attr_reader :placeholder, :max_chars, :text

    def build
      @build ||= bin.tap do |b|
        b.child = box

        box.tap do |content|
          content.append(text_view.build)
          content.append(show_more_button)

          text_view.build.add_controller(focus_controller)

          focus_controller.tap do |controller|
            controller.signal_connect("enter") { start_editing }
            controller.signal_connect("leave") { stop_editing }
          end

          text_view.on_change do |value|
            unless @updating
              @text = value
              @on_change&.call(value)
              reset_timeout
            end
          end

          show_more_button.signal_connect("clicked") { toggle_expanded }
        end

        Services::EventBus.on(:mobile_mode_changed, owner: self) { update_display }

        update_display
      end
    end

    def on_focus_changed(&block)
      @on_focus_changed = block
    end

    def editing? = @editing == true

    def text=(value)
      @text = value.to_s
      unless editing?
        update_display
      end
    end

    def editable=(value)
      text_view.editable = value
    end

    # Puts the cursor in the view, which is how the detail pane opens straight
    # into the note after the user asks to edit it.
    def edit!
      @on_focus_changed&.call(true)
      text_view.grab_focus
    end

    # --- display ----------------------------------------------------------

    def toggle_expanded
      @expanded = !@expanded
      update_display
    end

    # While editing, the whole note is always shown — truncating under the
    # cursor would eat what is being typed.
    def update_display
      @updating = true

      if full_text?
        show_full
      elsif @expanded
        show_expanded
      else
        show_truncated
      end

      @updating = false
    end

    def full_text?
      editing? || !Services::EventBus.mobile_mode? || text.length <= max_chars
    end

    def show_full
      text_view.text = text
      show_more_button.visible = false
    end

    def show_expanded
      text_view.text = text
      show_more_button.label = _("Show less")
      show_more_button.visible = true
    end

    def show_truncated
      text_view.text = "#{text[0, max_chars].strip}…"
      show_more_button.label = _("Show more")
      show_more_button.visible = true
    end

    # --- focus and the idle timeout ---------------------------------------

    def start_editing
      @editing = true
      @on_focus_changed&.call(true)
      update_display
      start_timeout
    end

    def stop_editing
      @editing = false
      @on_focus_changed&.call(false)
      update_display
      stop_timeout
    end

    def start_timeout
      stop_timeout
      @timeout_id = GLib::Timeout.add_seconds(IDLE_SECONDS) do
        if editing?
          text_view.build.root&.set_focus(nil)
        end
        @timeout_id = nil
        false
      end
    end

    def stop_timeout
      unless @timeout_id.nil?
        GLib::Source.remove(@timeout_id)
        @timeout_id = nil
      end
    end

    def reset_timeout
      if editing?
        start_timeout
      end
    end

    # --- widgets ----------------------------------------------------------

    def bin = @bin ||= Adwaita::Bin.new

    def box = @box ||= Gtk::Box.new(:vertical, 6)

    # The placeholder is the TextView's own, so an empty note still shows the
    # prompt rather than a blank strip of nothing.
    def text_view = @text_view ||= TextView.new(placeholder: placeholder)

    def focus_controller = @focus_controller ||= Gtk::EventControllerFocus.new

    def show_more_button
      @show_more_button ||= Gtk::Button.new(label: _("Show more")).tap do |button|
        button.add_css_class("flat")
        button.add_css_class("caption")
        button.halign = :center
        button.visible = false
      end
    end
  end
end
