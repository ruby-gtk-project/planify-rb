# frozen_string_literal: true

require "goa-rb"

module Planify
  module Services
    # core/Services/GOA.vala. Finds GNOME Online Accounts the user has
    # already set up (Nextcloud, ownCloud, plain WebDAV) that carry a
    # calendar, so the accounts dialog can offer one as a CalDAV source
    # without the user retyping a server URL by hand.
    module GOA
      DetectedAccount = Struct.new(
        :id,
        :provider_type,
        :display_name,
        :identity,
        :server_uri,
        :accept_ssl_errors,
        keyword_init: true,
      ) do
        def nextcloud? = %w[nextcloud owncloud].include?(provider_type)

        def username
          identity.to_s.rindex("@").then do |at|
            if at.nil?
              identity.to_s
            else
              local_part(at).then { |local| host_matches?(at) ? local : identity.to_s }
            end
          end
        end

        def local_part(at) = identity.to_s[0...at]

        def host_matches?(at)
          host_part = identity.to_s[(at + 1)..]
          server_host.then { |host| !host.empty? && host_part.to_s.start_with?(host) }
        end

        def server_host
          URI.parse(server_uri.to_s).host.to_s
        rescue URI::InvalidURIError, StandardError
          ""
        end
      end

      SUPPORTED_PROVIDERS = %w[nextcloud owncloud webdav].freeze

      module_function

      # Attempted once; a missing GOA daemon is normal and simply leaves the
      # feature off for the rest of the session.
      def client
        if !@tried_init
          @tried_init = true
          @client = connect
        end
        @client
      end

      def connect
        ::Goa::Client.new(nil)
      rescue StandardError => error
        LogService.info("GOA", "GNOME Online Accounts not available: #{error.message}")
        nil
      end

      def available? = !client.nil?

      def list_caldav_accounts
        if client.nil?
          []
        else
          client.accounts.filter_map { |object| detect(object) }
        end
      end

      def detect(object)
        account(object).then do |acct|
          if acct.nil? || acct.calendar_disabled?
            nil
          else
            detect_from_calendar(object, acct)
          end
        end
      end

      def account(object)
        object.account
      rescue StandardError
        nil
      end

      def detect_from_calendar(object, acct)
        if !SUPPORTED_PROVIDERS.include?(acct.provider_type.to_s)
          nil
        else
          calendar(object).then do |cal|
            if cal.nil? || cal.uri.to_s.empty?
              nil
            else
              DetectedAccount.new(
                id:                acct.id.to_s,
                provider_type:     acct.provider_type.to_s,
                display_name:      acct.provider_name.to_s,
                identity:          acct.presentation_identity.to_s,
                server_uri:        normalize_server_uri(cal.uri.to_s),
                accept_ssl_errors: cal.accept_ssl_errors?,
              )
            end
          end
        end
      end

      def calendar(object)
        object.calendar
      rescue StandardError
        nil
      end

      # Trims a CalDAV calendar's own collection path (dav/calendars/... or
      # remote.php/dav/...) off the account's URI, leaving the plain server
      # root a WebDAV source expects.
      def normalize_server_uri(raw)
        uri = URI.parse(raw)
        if uri.host.to_s.empty?
          raw
        else
          build_server_uri(uri)
        end
      rescue URI::InvalidURIError, StandardError
        raw
      end

      def build_server_uri(uri)
        "#{uri.scheme}://#{uri.host}#{port_suffix(uri)}#{path_suffix(uri)}"
      end

      def port_suffix(uri)
        default_port = (uri.scheme == "https" && uri.port == 443) ||
          (uri.scheme == "http" && uri.port == 80)
        if uri.port.nil? || default_port
          ""
        else
          ":#{uri.port}"
        end
      end

      def path_suffix(uri)
        uri.path.to_s.then do |path|
          if path.empty? || path == "/" || path.start_with?("/remote.php") || path.start_with?("/dav")
            ""
          else
            path.delete_suffix("/")
          end
        end
      end
    end
  end
end
