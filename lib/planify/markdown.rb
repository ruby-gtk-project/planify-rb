# frozen_string_literal: true

module Planify
  # core/Utils/MarkdownProcessor.vala. Task descriptions are stored as plain
  # Markdown; this turns them into Pango markup for display, and drives the
  # live styling in the editor. Patterns and their order are upstream's —
  # order matters, because the longest delimiter has to win.
  module Markdown
    RULES = [
      {
        name:    :code,
        pattern: /`([^`\n]+?)`/,
        markup:  ->(m) { "<tt>#{escape(m[1])}</tt>" },
      },
      {
        name:    :link,
        pattern: /\[([^\]]+)\]\(([^)\s]+)\)/,
        markup:  ->(m) { "<a href=\"#{escape(m[2])}\">#{escape(m[1])}</a>" },
      },
      {
        name:    :italic_bold_underline,
        pattern: /\*\*\*_([^*_\n]+?)_\*\*\*/,
        markup:  ->(m) { "<i><b><u>#{escape(m[1])}</u></b></i>" },
      },
      {
        name:    :bold_underline,
        pattern: /\*\*_([^*_\n]+?)_\*\*/,
        markup:  ->(m) { "<b><u>#{escape(m[1])}</u></b>" },
      },
      {
        name:    :italic_underline,
        pattern: /\*_([^*_\n]+?)_\*/,
        markup:  ->(m) { "<i><u>#{escape(m[1])}</u></i>" },
      },
      {
        name:    :italic_bold,
        pattern: /(?<!\*)\*\*\*([^*\n]+?)\*\*\*(?!\*)/,
        markup:  ->(m) { "<i><b>#{escape(m[1])}</b></i>" },
      },
      {
        name:    :bold,
        pattern: /(?<!\*)\*\*([^*\n]+?)\*\*(?!\*)/,
        markup:  ->(m) { "<b>#{escape(m[1])}</b>" },
      },
      {
        name:    :italic,
        pattern: /(?<!\*)\*([^*\n]+?)\*(?!\*)/,
        markup:  ->(m) { "<i>#{escape(m[1])}</i>" },
      },
      {
        name:    :underline,
        pattern: /_([^_\n]+?)_/,
        markup:  ->(m) { "<u>#{escape(m[1])}</u>" },
      },
      {
        name:    :url,
        pattern: %r{(?<!\]\()(https?://[a-zA-Z0-9][a-zA-Z0-9.-]*\.[a-zA-Z]{2,}(?:/[^\s]*)?)},
        markup:  ->(m) { "<a href=\"#{escape(m[1])}\">#{escape(m[1])}</a>" },
      },
      {
        name:    :mailto,
        pattern: /(?<![\w.@])([a-zA-Z0-9][a-zA-Z0-9._%-]*[a-zA-Z0-9]@[a-zA-Z0-9][a-zA-Z0-9.-]*\.[a-zA-Z]{2,})/,
        markup:  ->(m) { "<a href=\"mailto:#{escape(m[1])}\">#{escape(m[1])}</a>" },
      },
    ].freeze

    HEADING = /^(\#{1,6})\s+(.*)$/
    BULLET = /^(\s*)[-*+]\s+(.*)$/
    CHECKBOX = /^(\s*)[-*+]\s+\[([ xX])\]\s+(.*)$/
    NUMBERED = /^(\s*)(\d+)\.\s+(.*)$/
    QUOTE = /^>\s?(.*)$/

    HEADING_SIZES = %w[xx-large x-large large medium small x-small].freeze

    module_function

    def escape(text) = GLib::Markup.escape_text(text.to_s)

    # Pango has no block layout, so headings become sized spans, bullets get a
    # real bullet character, and checkboxes a box glyph. That is as far as it
    # goes — this is a one-line-per-line renderer, not a Markdown engine.
    def to_markup(text)
      text.to_s.lines.map { |line| line_markup(line.chomp) }.join("\n")
    end

    def line_markup(line)
      if (match = line.match(CHECKBOX))
        "#{match[1]}#{match[2].strip.empty? ? '☐' : '☑'} #{inline(match[3])}"
      elsif (match = line.match(HEADING))
        heading_markup(match)
      elsif (match = line.match(BULLET))
        "#{match[1]}• #{inline(match[2])}"
      elsif (match = line.match(NUMBERED))
        "#{match[1]}#{match[2]}. #{inline(match[3])}"
      elsif (match = line.match(QUOTE))
        "<i>│ #{inline(match[1])}</i>"
      else
        inline(line)
      end
    end

    def heading_markup(match)
      HEADING_SIZES[match[1].length - 1].then do |size|
        "<span size=\"#{size}\" weight=\"bold\">#{inline(match[2])}</span>"
      end
    end

    # One pass, longest match first at each position, so `**_x_**` is not
    # eaten by the plain bold rule before the combined one sees it.
    def inline(text)
      "".dup.tap do |out|
        rest = text.to_s
        until rest.empty?
          earliest(rest).then do |(rule, match)|
            if rule.nil?
              out << escape(rest)
              rest = ""
            else
              out << escape(match.pre_match)
              out << rule[:markup].call(match)
              rest = match.post_match
            end
          end
        end
      end
    end

    def earliest(text)
      RULES.filter_map { |rule| text.match(rule[:pattern])&.then { |m| [rule, m] } }
           .min_by { |(_, match)| match.begin(0) }
           .then { |found| found.nil? ? [nil, nil] : found }
    end

    # --- editing helpers --------------------------------------------------

    WRAPPERS = {
      bold:      "**",
      italic:    "*",
      underline: "_",
      code:      "`",
      strike:    "~~",
    }.freeze

    # Wrapping a selection toggles: a run already wrapped in the delimiter is
    # unwrapped rather than double-wrapped.
    def wrap(text, style)
      WRAPPERS.fetch(style).then do |marker|
        if text.start_with?(marker) && text.end_with?(marker) && text.length > marker.length * 2
          text[marker.length...-marker.length]
        else
          "#{marker}#{text}#{marker}"
        end
      end
    end

    def toggle_checkbox(line)
      if (match = line.match(CHECKBOX))
        "#{match[1]}- [#{match[2].strip.empty? ? 'x' : ' '}] #{match[3]}"
      elsif (match = line.match(BULLET))
        "#{match[1]}- [ ] #{match[2]}"
      else
        "- [ ] #{line}"
      end
    end

    # Pressing Return inside a list continues it; on an empty item it ends it.
    def continuation(line)
      if (match = line.match(CHECKBOX))
        match[3].strip.empty? ? "" : "#{match[1]}- [ ] "
      elsif (match = line.match(NUMBERED))
        match[3].strip.empty? ? "" : "#{match[1]}#{match[2].to_i + 1}. "
      elsif (match = line.match(BULLET))
        match[2].strip.empty? ? "" : "#{match[1]}- "
      else
        ""
      end
    end

    def strip(text)
      text.to_s.lines.map { |line| strip_line(line.chomp) }.join("\n")
    end

    def strip_line(line)
      RULES.reduce(line) do |stripped, rule|
        stripped.gsub(rule[:pattern]) { |_| Regexp.last_match(1).to_s }
      end.sub(HEADING, '\2').sub(CHECKBOX, '\1\3').sub(BULLET, '\1\2')
    end

    # The list preview shows the first non-empty line with its syntax removed.
    def preview(text)
      strip(text.to_s).lines.map(&:strip).find { |line| !line.empty? }.to_s
    end
  end
end
