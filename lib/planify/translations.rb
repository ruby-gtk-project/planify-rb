# frozen_string_literal: true

module Planify
  # The .mo files sit beside the sources once installed and are absent in the
  # checkout, where gettext falls through to the msgids in the source.
  module Translations
    DOMAIN = "io.github.alainm23.planify"

    def self.install
      GetText.bindtextdomain(DOMAIN, path: File.join(Paths.data, "locale"))
    end
  end
end

Planify::Translations.install
