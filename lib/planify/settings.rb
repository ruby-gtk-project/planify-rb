# frozen_string_literal: true

module Planify
  # Planify's own GSettings schema, unchanged — the keys and their defaults are
  # already in data/io.github.alainm23.planify.gschema.xml, so the port reads
  # and writes the same settings the Vala build does.
  module Settings
    SCHEMA_ID = "io.github.alainm23.planify"

    module_function

    def settings = @settings ||= Gio::Settings.new(SCHEMA_ID)

    def get_string(key) = settings.get_string(key)

    def set_string(key, value) = settings.set_string(key, value)

    def get_boolean(key) = settings.get_boolean(key)

    def set_boolean(key, value) = settings.set_boolean(key, value)

    def get_int(key) = settings.get_int(key)

    def set_int(key, value) = settings.set_int(key, value)

    def get_enum(key) = settings.get_enum(key)

    def set_enum(key, value) = settings.set_enum(key, value)

    def changed(key, &block) = settings.signal_connect("changed::#{key}") { block.call }

    def clock_format_12h?
      if get_enum("clock-format").zero?
        Time.now.strftime("%p") != ""
      else
        get_enum("clock-format") == 1
      end
    end

    def new_task_position_start? = get_enum("new-tasks-position").zero?

    def default_priority
      # The setting is an index: 0 is P1 through 3 is P4, while the stored
      # priority runs the other way (4 is P1).
      4 - get_enum("default-priority")
    end

    def home_view = get_string("home-view")

    def home_view=(value)
      set_string("home-view", value)
    end
  end
end
