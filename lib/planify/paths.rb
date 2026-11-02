# frozen_string_literal: true

module Planify
  # lib/ and data/ stay siblings, in the checkout and once installed, so the
  # stylesheet and icons are always found next to the code that loads them.
  module Paths
    def self.root = @root ||= File.expand_path("../..", __dir__)

    def self.data = @data ||= File.join(root, "data")

    def self.resources = @resources ||= File.join(data, "resources")

    # The translation catalogues ship beside lib/ and data/, and are read at
    # runtime to work out how complete the user's own language is.
    def self.po = @po ||= File.join(root, "po")

    def self.user_data
      @user_data ||= File.join(
        ENV.fetch("XDG_DATA_HOME", File.join(Dir.home, ".local", "share")),
        "io.github.alainm23.planify",
      )
    end

    def self.database = @database ||= File.join(user_data, "database.db")

    def self.backups = @backups ||= File.join(user_data, "backups")
  end
end
