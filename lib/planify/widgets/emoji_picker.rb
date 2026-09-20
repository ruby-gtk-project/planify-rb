# frozen_string_literal: true

module Planify
  # The emoji button a project uses when its icon style is "emoji". GTK's own
  # EmojiChooser supplies the grid, so this is only the button that holds the
  # current pick.
  class EmojiPicker
    def initialize(emoji = "🚀️")
      @emoji = emoji
    end

    attr_reader :emoji

    def build
      @build ||= button.tap do |b|
        b.popover = chooser

        chooser.signal_connect("emoji-picked") do |_, picked|
          @emoji = picked
          label.label = picked
        end
      end
    end

    def emoji=(value)
      @emoji = value
      label.label = value
    end

    def button
      @button ||= Gtk::MenuButton.new.tap do |b|
        b.add_css_class("flat")
        b.child = label
        b.width_request = 36
        b.height_request = 36
      end
    end

    def label = @label ||= Gtk::Label.new(@emoji)

    def chooser = @chooser ||= Gtk::EmojiChooser.new
  end
end
