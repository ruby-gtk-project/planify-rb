# frozen_string_literal: true

module Planify
  # The Todoist palette Planify ships with. Ported from Util.get_colors; the
  # ids are Todoist's and are what the sync backends exchange, so they stay
  # even though nothing local reads them.
  module Palette
    DEFAULT = "#1e63ec"

    PALETTE = {
      "berry_red"   => [30, "Berry Red", "#c42d78"],
      "red"         => [31, "Red", "#e23d3d"],
      "orange"      => [32, "Orange", "#ff8a2a"],
      "yellow"      => [33, "Yellow", "#f5c400"],
      "olive_green" => [34, "Olive Green", "#9cab3a"],
      "lime_green"  => [35, "Lime Green", "#70c741"],
      "green"       => [36, "Green", "#27983a"],
      "mint_green"  => [37, "Mint Green", "#55cbb0"],
      "teal"        => [38, "Teal", "#1492b2"],
      "sky_blue"    => [39, "Sky Blue", "#139ef7"],
      "light_blue"  => [40, "Light Blue", "#7fb9e8"],
      "blue"        => [41, "Blue", "#3c6dff"],
      "grape"       => [42, "Grape", "#7b44e6"],
      "violet"      => [43, "Violet", "#a02adb"],
      "lavender"    => [44, "Lavender", "#d89ae8"],
      "magenta"     => [45, "Magenta", "#d6458d"],
      "salmon"      => [46, "Salmon", "#f77c70"],
      "charcoal"    => [47, "Charcoal", "#666666"],
      "grey"        => [48, "Grey", "#a0a0a0"],
      "taupe"       => [49, "Taupe", "#b99780"],
    }.freeze

    # Anything that is not a palette key is passed through when GDK can parse
    # it, so a CalDAV colour that arrived as a raw hex string still renders.
    # The Ruby binding raises on an unparseable value rather than returning
    # false, which is what makes the rescue the branch that matters.
    def self.hex(key)
      if key.nil? || key.to_s.empty?
        DEFAULT
      elsif PALETTE.key?(key)
        PALETTE.fetch(key)[2]
      else
        begin
          Gdk::RGBA.parse(key)
          key
        rescue ArgumentError
          DEFAULT
        end
      end
    end

    def self.name(key) = PALETTE.fetch(key, [nil, key, nil])[1]

    def self.keys = PALETTE.keys

    def self.random = PALETTE.keys.sample

    def self.rgba(key) = Gdk::RGBA.parse(hex(key))
  end
end
