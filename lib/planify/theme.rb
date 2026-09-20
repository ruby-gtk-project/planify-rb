# frozen_string_literal: true

module Planify
  # Util.update_theme / update_font_scale. The shipped variables.css holds only
  # the light palette; upstream overrides those @define-colors at runtime for
  # each appearance, which is what actually makes the dark themes work. Doing
  # the same here is why the stylesheet can be loaded unmodified.
  module Theme
    DEFAULT_ACCENT = "#3584e4"

    # "appearance" is an enum: 0 Light, 1 Dark, 2 Dark Blue.
    PALETTES = {
      light:     {
        "window_bg_color"   => "#f9f9f9",
        "popover_bg_color"  => "#ffffff",
        "sidebar_bg_color"  => "#f3f4f6",
        "item_border_color" => "#dcdfe3",
        "upcoming_bg_color" => "#f0f1f3",
        "upcoming_fg_color" => "#2d2e32",
        "selected_color"    => "#dbeafe",
        "card_bg_color"     => "#ffffff",
      },
      dark:      {
        "window_bg_color"   => "#181818",
        "popover_bg_color"  => "#202020",
        "sidebar_bg_color"  => "#1f1f1f",
        "item_border_color" => "#3a3a3a",
        "upcoming_bg_color" => "#2d2d2d",
        "upcoming_fg_color" => "#f0f0f0",
        "selected_color"    => "#2e3a46",
        "card_bg_color"     => "#222222",
      },
      dark_blue: {
        "window_bg_color"   => "#0C0D12",
        "popover_bg_color"  => "#16171D",
        "sidebar_bg_color"  => "#14151a",
        "item_border_color" => "#2d2f35",
        "upcoming_bg_color" => "#2a2d34",
        "upcoming_fg_color" => "#e6e9ef",
        "selected_color"    => "#2a303a",
        "card_bg_color"     => "#1E2026",
      },
    }.freeze

    module_function

    def update
      apply(variables_css, :variables)
      apply(font_scale_css, :font_scale)
      Adwaita::StyleManager.default.color_scheme = color_scheme
    end

    def dark?
      if Settings.get_boolean("system-appearance")
        Adwaita::StyleManager.default.dark?
      else
        Settings.get_boolean("dark-mode")
      end
    end

    def color_scheme
      if dark?
        Adwaita::ColorScheme::FORCE_DARK
      else
        Adwaita::ColorScheme::FORCE_LIGHT
      end
    end

    def palette
      if !dark?
        PALETTES.fetch(:light)
      elsif Settings.get_enum("appearance") == 1
        PALETTES.fetch(:dark)
      else
        PALETTES.fetch(:dark_blue)
      end
    end

    def variables_css
      palette.merge(
        "accent_color"    => accent_color,
        "accent_bg_color" => accent_color,
      ).map { |name, value| "@define-color #{name} #{value};" }.join("\n")
    end

    # The system accent is only honoured when the desktop actually publishes
    # one; otherwise Planify's own blue stands in.
    def accent_color
      if Settings.get_boolean("use-system-accent")
        system_accent
      else
        DEFAULT_ACCENT
      end
    end

    # Only honoured when the desktop actually publishes an accent; without
    # that check a session with no accent support paints everything in
    # whatever libadwaita happens to report.
    def system_accent
      Adwaita::StyleManager.default.then do |manager|
        if manager.respond_to?(:system_supports_accent_colors?) &&
           manager.system_supports_accent_colors?
          rgba_to_hex(manager.accent_color_rgba)
        else
          DEFAULT_ACCENT
        end
      end
    rescue StandardError
      DEFAULT_ACCENT
    end

    def rgba_to_hex(rgba)
      format(

        "#%02x%02x%02x",

        (rgba.red * 255).to_i,

        (rgba.green * 255).to_i,
        (rgba.blue * 255).to_i,
      )
    end

    def font_scale_css
      (Settings.settings.get_double("font-scale") * 100).round.then do |scale|
        "popover, window { font-size: #{scale}%; }"
      end
    end

    # One provider per purpose, replaced in place, so switching themes does not
    # stack a new provider on the display each time.
    def providers = @providers ||= {}

    def apply(css, key)
      providers[key] ||= Gtk::CssProvider.new.tap do |provider|
        Gtk::StyleContext.add_provider_for_display(
          Gdk::Display.default,
          provider,
          Gtk::StyleProvider::PRIORITY_APPLICATION + 1,
        )
      end

      providers.fetch(key).load(data: css)
    end

    # Planify repaints when any of these move.
    WATCHED = %w[appearance dark-mode system-appearance use-system-accent font-scale].freeze

    def watch
      WATCHED.each { |key| Settings.changed(key) { update } }
      Adwaita::StyleManager.default.signal_connect("notify::dark") { update }
    end
  end
end
