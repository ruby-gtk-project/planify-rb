# frozen_string_literal: true

module Planify
  # src/Widgets/TranslationRow.vala. The preferences row that asks for help
  # with translations, and says how far along the user's own language already
  # is. The percentage fills in with a short animation the first time the row
  # becomes visible, so it reads as a measurement rather than as decoration.
  #
  # Upstream reads the installed .mo header and divides by a string count
  # baked in at build time. The catalogues themselves ship with this port, so
  # the count is taken from the .po for the user's language instead: every
  # msgid is in there, and the ones with a non-empty msgstr are the done ones.
  class TranslationRow
    # How long the fill takes, and how many steps it takes to get there.
    ANIMATION_MS = 1000
    ANIMATION_STEPS = 30

    def initialize
      @percent = 0.0
      @language_name = ""
      @animated = false
    end

    attr_reader :percent, :language_name

    def build
      @build ||= row.tap do |r|
        r.child = main_box

        main_box.tap do |box|
          box.append(icon)
          box.append(text_box)

          text_box.tap do |text|
            text.append(title_label)
            text.append(subtitle_label)
            text.append(level_bar)
          end
        end

        load_translation_data
      end
    end

    # --- content ----------------------------------------------------------

    # English needs no translating, a language with a catalogue gets its
    # progress, and one without gets the invitation to start it.
    def load_translation_data
      if english?
        show_generic
      else
        metric.then do |found|
          if found.nil?
            show_missing
          else
            show_progress(found)
          end
        end
      end
    end

    def show_generic
      self.title = _("Translations")
      self.subtitle = _("Help make Planify available worldwide")
      level_bar.visible = false
    end

    def show_missing
      self.title = _("Start a new translation")
      self.subtitle = _("<b>%s</b> is not available yet. Be the first to translate it!") %
                      display_language
      level_bar.visible = false
    end

    def show_progress(found)
      self.title = _("Help improve translations")
      @language_name = display_language
      @percent = found
      level_bar.visible = true
      prepare_subtitle(0.0)
    end

    def prepare_subtitle(value)
      self.subtitle = _("<b>%s</b> is %.0f%% complete. You can help finish it!") %
                      [language_name, value]
      level_bar.value = value / 100.0
    end

    # The fill runs once, when the page the row sits on is first shown; a row
    # scrolled past twice should not animate twice.
    def trigger_animation
      unless @animated || percent.zero?
        @animated = true
        step = 0
        GLib::Timeout.add(ANIMATION_MS / ANIMATION_STEPS) do
          step += 1
          prepare_subtitle(percent * step / ANIMATION_STEPS)
          step < ANIMATION_STEPS
        end
      end
    end

    def animated? = @animated == true

    # --- the catalogue ----------------------------------------------------

    # Most specific first — pt_BR before pt — which is the order gettext
    # itself looks a catalogue up in.
    def languages
      ENV.values_at("LC_ALL", "LC_MESSAGES", "LANG")
        .compact
        .flat_map { |value| value.split(":") }
        .map { |value| value.split(".").first.to_s }
        .reject { |value| value.empty? || %w[C POSIX].include?(value) }
        .flat_map { |value| [value, value.split("_").first] }
        .compact
        .uniq
    end

    def english? = languages.any? { |code| code.to_s.start_with?("en") }

    # Upstream runs the language code through ICU for a localised language
    # name; nothing in the Ruby stack here does that, so the code itself is
    # what the row names.
    def display_language = languages.first.to_s

    # Returns the percentage of msgids with a translation, or nil when there
    # is no catalogue for the language at all.
    def metric
      catalogue.then do |path|
        if path.nil?
          nil
        else
          count_entries(path).then do |(total, translated)|
            if total.zero?
              nil
            else
              translated * 100.0 / total
            end
          end
        end
      end
    end

    def catalogue
      languages.map { |code| File.join(Paths.po, "#{code}.po") }
        .find { |path| File.file?(path) }
    end

    # A .po file is blank-line separated entries. The first is the catalogue
    # header, which nobody translates, and an entry made only of comments is
    # an obsolete string msgmerge kept around — neither is a string in the
    # app. Everything else counts, and counts as done when it has a non-empty
    # msgstr that is not marked fuzzy.
    def count_entries(path)
      entries(path).then { |found| [found.size, found.count { |block| translated?(block) }] }
    rescue StandardError
      [0, 0]
    end

    def entries(path)
      File.read(path)
        .split(/\n[ \t]*\n+/)
        .drop(1)
        .map(&:strip)
        .reject { |block| block.empty? || block.lines.all? { |line| line.start_with?("#") } }
    end

    def translated?(block) = !fuzzy?(block) && !msgstr_of(block).empty?

    def fuzzy?(block)
      block.lines.any? { |line| line.start_with?("#,") && line.include?("fuzzy") }
    end

    # Joins the quoted parts of every msgstr in the entry. A plural entry has
    # one per form, and one filled-in form is enough to call it done.
    def msgstr_of(block)
      collecting = false

      String.new.tap do |value|
        block.each_line do |line|
          line.strip.then do |stripped|
            if stripped.start_with?("msgstr")
              collecting = true
              value << quoted(stripped)
            elsif stripped.start_with?("msgid")
              collecting = false
            elsif collecting && stripped.start_with?('"')
              value << quoted(stripped)
            end
          end
        end
      end
    end

    def quoted(line) = line[/"(.*)"[^"]*\z/, 1].to_s

    # --- properties -------------------------------------------------------

    def title=(value)
      title_label.label = value.to_s
    end

    def subtitle=(value)
      subtitle_label.label = value.to_s
    end

    def icon_name=(value)
      icon.icon_name = value
    end

    # --- widgets ----------------------------------------------------------

    def row
      @row ||= Adwaita::PreferencesRow.new.tap do |r|
        r.activatable = false
      end
    end

    def main_box
      @main_box ||= Gtk::Box.new(:horizontal, 12).tap do |box|
        box.margin_start = 12
        box.margin_end = 12
        box.margin_top = 8
        box.margin_bottom = 8
      end
    end

    def icon
      @icon ||= Gtk::Image.new(icon_name: "language-symbolic").tap do |image|
        image.pixel_size = 16
        image.valign = :center
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

    def level_bar
      @level_bar ||= Gtk::LevelBar.new.tap do |bar|
        bar.hexpand = true
        bar.margin_top = 6
        bar.min_value = 0.0
        bar.max_value = 1.0
      end
    end
  end
end
