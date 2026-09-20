# frozen_string_literal: true

module Planify
  module Services
    # src/Services/Api.vala. Checks the upstream release feed and reports a
    # newer version than the one running, once, at startup.
    module Api
      RELEASES_URL = "https://api.github.com/repos/alainm23/planify/releases/latest"

      module_function

      def check(&found)
        Http.async("GET", RELEASES_URL, headers: { "Accept" => "application/vnd.github+json" }) do |response|
          if response.ok?
            release_from(response.json).then do |release|
              if newer?(release)
                found.call(release)
              end
            end
          else
            LogService.debug("Api", "release check failed: #{response.message}")
          end
        end
      end

      def release_from(payload)
        {
          version: payload["tag_name"].to_s.delete_prefix("v"),
          summary: summarize(payload["body"].to_s),
          url:     payload["html_url"].to_s,
        }
      end

      # Release notes are long; the popup wants the first paragraph.
      def summarize(body)
        body.lines.map(&:strip).reject(&:empty?)
            .reject { |line| line.start_with?("#", "-", "*") }
            .first.to_s[0, 200]
      end

      # Only a version strictly newer than this build, and only one the user
      # has not already dismissed.
      def newer?(release)
        !release[:version].empty? &&
          compare(release[:version], Planify::VERSION).positive? &&
          release[:version] != Settings.get_string("dismissed-update-version")
      end

      def compare(left, right)
        parts(left) <=> parts(right)
      end

      def parts(version) = version.to_s.split(".").map(&:to_i)

      def dismiss(version)
        Settings.set_string("dismissed-update-version", version.to_s)
      end
    end
  end
end
