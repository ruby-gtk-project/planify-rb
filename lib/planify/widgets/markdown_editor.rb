# frozen_string_literal: true

module Planify
  # core/Widgets/MarkdownEditor.vala. A TextView that styles Markdown as it is
  # typed rather than rendering it: the source stays editable and the
  # delimiters stay visible, dimmed, which is what makes the editor usable
  # without a preview pane.
  class MarkdownEditor
    def initialize(&on_change)
      @on_change = on_change
      @applying = false
    end

    attr_reader :on_change

    def build
      @build ||= box.tap do |b|
        b.append(scrolled)
        b.append(toolbar_revealer)

        scrolled.child = text_view

        text_view.tap do |view|
          view.add_controller(focus_controller)
          view.add_controller(key_controller)
        end

        buffer.signal_connect("changed") { changed }

        focus_controller.signal_connect("enter") { toolbar_revealer.reveal_child = true }
        focus_controller.signal_connect("leave") { toolbar_revealer.reveal_child = false }

        key_controller.signal_connect("key-pressed") do |_, keyval, _, state|
          on_key(keyval, state)
        end

        toolbar_revealer.child = toolbar

        toolbar.tap do |bar|
          TOOLS.each do |tool|
            bar.append(tool_button(tool))
          end
        end

        register_tags
      end
    end

    def text = buffer.text

    def text=(value)
      unless value.to_s == buffer.text
        @applying = true
        buffer.text = value.to_s
        @applying = false
        restyle
      end
    end

    def changed
      unless @applying
        restyle
        on_change&.call(buffer.text)
      end
    end

    # --- styling ----------------------------------------------------------

    TAGS = {
      "bold"      => { weight: Pango::Weight::BOLD },
      "italic"    => { style: Pango::Style::ITALIC },
      "underline" => { underline: Pango::Underline::SINGLE },
      "code"      => { family: "monospace" },
      "link"      => { underline: Pango::Underline::SINGLE },
      "marker"    => {},
      "heading"   => { weight: Pango::Weight::BOLD, scale: 1.3 },
      "quote"     => { style: Pango::Style::ITALIC },
    }.freeze

    def register_tags
      TAGS.each do |name, properties|
        buffer.create_tag(name, **properties)
      end

      # The delimiters stay on screen but recede, so the text reads as styled
      # without the syntax disappearing out from under the cursor.
      buffer.tag_table.lookup("marker").tap do |tag|
        tag.foreground_rgba = Gdk::RGBA.parse("#888888")
      end

      buffer.tag_table.lookup("link").tap do |tag|
        tag.foreground_rgba = Gdk::RGBA.parse(Theme::DEFAULT_ACCENT)
      end
    end

    def restyle
      if Settings.get_boolean("enable-markdown-formatting")
        clear_tags
        buffer.text.then { |text| style_blocks(text); style_inline(text) }
      end
    end

    def clear_tags
      buffer.remove_all_tags(buffer.start_iter, buffer.end_iter)
    end

    def style_blocks(text)
      offset = 0

      text.lines.each do |line|
        line.chomp.then do |stripped|
          apply_block(stripped, offset)
          offset += line.length
        end
      end
    end

    def apply_block(line, offset)
      if (match = line.match(Markdown::HEADING))
        apply("heading", offset, offset + line.length)
        apply("marker", offset, offset + match[1].length)
      elsif line.match?(Markdown::QUOTE)
        apply("quote", offset, offset + line.length)
      end
    end

    # Character offsets, not byte offsets: GtkTextBuffer counts characters and
    # a description with an emoji in it would otherwise style the wrong run.
    def style_inline(text)
      Markdown::RULES.each do |rule|
        text.to_enum(:scan, rule[:pattern]).each do
          Regexp.last_match.then { |match| apply_inline(rule, match, text) }
        end
      end
    end

    INLINE_TAGS = {
      code:                  "code",
      link:                  "link",
      url:                   "link",
      mailto:                "link",
      bold:                  "bold",
      italic:                "italic",
      underline:             "underline",
      italic_bold:           "bold",
      bold_underline:        "bold",
      italic_underline:      "italic",
      italic_bold_underline: "bold",
    }.freeze

    def apply_inline(rule, match, text)
      INLINE_TAGS.fetch(rule[:name], nil).then do |tag|
        unless tag.nil?
          char_offset(text, match.begin(0)).then do |start|
            char_offset(text, match.end(0)).then do |finish|
              apply(tag, start, finish)
              mark_delimiters(
                match,
                text,
                start,
                finish,
              )
            end
          end
        end
      end
    end

    def mark_delimiters(match, text, start, finish)
      char_offset(text, match.begin(1)).then do |inner_start|
        char_offset(text, match.end(1)).then do |inner_end|
          apply("marker", start, inner_start)
          apply("marker", inner_end, finish)
        end
      end
    end

    def char_offset(text, byte_index) = text.byteslice(0, byte_index).to_s.length

    def apply(tag, start, finish)
      buffer.apply_tag(
        buffer.tag_table.lookup(tag),
        buffer.get_iter_at(offset: start),
        buffer.get_iter_at(offset: finish),
      )
    end

    # --- toolbar ----------------------------------------------------------

    TOOLS = [
      {
        style: :bold,
        icon:  "format-text-bold-symbolic",
        label: -> { _("Bold") },
        accel: Gdk::Keyval::KEY_b,
      },
      {
        style: :italic,
        icon:  "format-text-italic-symbolic",
        label: -> { _("Italic") },
        accel: Gdk::Keyval::KEY_i,
      },
      {
        style: :underline,
        icon:  "format-text-underline-symbolic",
        label: -> { _("Underline") },
        accel: Gdk::Keyval::KEY_u,
      },
      {
        style: :strike,
        icon:  "format-text-strikethrough-symbolic",
        label: -> { _("Strikethrough") },
        accel: nil,
      },
      { style: :code, icon: "code-symbolic", label: -> { _("Code") }, accel: nil },
    ].freeze

    def tool_button(tool)
      Gtk::Button.new(icon_name: tool[:icon]).tap do |button|
        button.add_css_class("flat")
        button.tooltip_text = tool[:label].call
        button.signal_connect("clicked") { apply_style(tool[:style]) }
      end
    end

    def apply_style(style)
      selection.then do |(start, finish)|
        buffer.get_text(start, finish, false).then do |selected|
          buffer.begin_user_action
          buffer.delete(start, finish)
          buffer.insert(start, Markdown.wrap(selected, style))
          buffer.end_user_action
        end
      end
    end

    def selection
      buffer.selection_bounds.then do |bounds|
        if bounds.is_a?(Array) && bounds.length >= 2
          bounds.last(2)
        else
          [buffer.get_iter_at(offset: buffer.cursor_position),
           buffer.get_iter_at(offset: buffer.cursor_position),
]
        end
      end
    end

    # Ctrl+B/I/U, and Return continuing a list.
    def on_key(keyval, state)
      if state.control_mask?
        TOOLS.find { |tool| tool[:accel] == keyval }.then do |tool|
          if tool.nil?
            false
          else
            apply_style(tool[:style])
            true
          end
        end
      elsif keyval == Gdk::Keyval::KEY_Return
        continue_list
      else
        false
      end
    end

    def continue_list
      current_line.then do |line|
        Markdown.continuation(line).then do |prefix|
          if prefix.empty?
            false
          else
            buffer.insert_at_cursor("\n#{prefix}")
            true
          end
        end
      end
    end

    def current_line
      buffer.get_iter_at(offset: buffer.cursor_position).then do |cursor|
        buffer.get_iter_at(line: cursor.line).then do |start|
          buffer.get_text(start, cursor, false)
        end
      end
    end

    # --- widgets ----------------------------------------------------------

    def box = @box ||= Gtk::Box.new(:vertical, 0)

    def scrolled
      @scrolled ||= Gtk::ScrolledWindow.new.tap do |scroll|
        scroll.hscrollbar_policy = :never
        scroll.vexpand = true
        scroll.height_request = 120
        scroll.add_css_class("card")
      end
    end

    def buffer = @buffer ||= Gtk::TextBuffer.new

    def text_view
      @text_view ||= Gtk::TextView.new(buffer).tap do |view|
        view.wrap_mode = :word_char
        view.top_margin = 9
        view.bottom_margin = 9
        view.left_margin = 9
        view.right_margin = 9
        view.add_css_class("markdown-editor")
      end
    end

    def toolbar_revealer
      @toolbar_revealer ||= Gtk::Revealer.new.tap do |revealer|
        revealer.transition_type = :slide_down
      end
    end

    def toolbar
      @toolbar ||= Gtk::Box.new(:horizontal, 3).tap do |bar|
        bar.margin_top = 3
        bar.add_css_class("toolbar")
      end
    end

    def focus_controller = @focus_controller ||= Gtk::EventControllerFocus.new

    def key_controller = @key_controller ||= Gtk::EventControllerKey.new
  end
end
