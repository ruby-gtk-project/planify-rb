# frozen_string_literal: true

require "net/http"
require "openssl"

module Planify
  module Services
    # What libsoup's send_and_read_async gives upstream: a request that does
    # not block the main loop. A worker thread does the socket work and the
    # callback is handed back on the GLib main loop, so callers can touch
    # widgets from it exactly as they would from a Soup callback.
    module Http
      Response = Struct.new(
        :status,
        :body,
        :headers,
        :error,
      ) do
        def ok? = error.nil? && status.between?(200, 299)

        def json
          begin
            JSON.parse(body.to_s)
          rescue JSON::ParserError
            {}
          end
        end

        def message
          if error
            error
          else
            "HTTP #{status}"
          end
        end
      end

      module_function

      # Blocking. Only the background thread and the tests call this directly.
      def request(method, url, body: nil, headers: {}, auth: nil, ignore_ssl: false)
        uri = URI.parse(url)
        build(
          method,
          uri,
          body,
          headers,
          auth,
        ).then do |message|
          transport(uri, ignore_ssl).start do |http|
            http.request(message).then do |response|
              Response.new(
                response.code.to_i,
                response.body,
                response.to_hash,
                nil,
              )
            end
          end
        end
      rescue StandardError => error
        LogService.error("Http", "#{method} #{url}: #{error.class}: #{error.message}")
        Response.new(
          0,
          nil,
          {},
          error.message,
        )
      end

      def transport(uri, ignore_ssl)
        Net::HTTP.new(uri.host, uri.port).tap do |http|
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = 20
          http.read_timeout = 60
          # Nextcloud on a self-signed certificate is common enough that
          # Planify offers the switch per source.
          if ignore_ssl
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE
          end
        end
      end

      METHODS = {
        "GET"        => Net::HTTP::Get,
        "POST"       => Net::HTTP::Post,
        "PUT"        => Net::HTTP::Put,
        "DELETE"     => Net::HTTP::Delete,
        "PROPFIND"   => nil,
        "REPORT"     => nil,
        "MKCOL"      => nil,
        "MKCALENDAR" => nil,
      }.freeze

      def build(method, uri, body, headers, auth)
        message_class(method).new(uri).tap do |message|
          headers.each { |name, value| message[name] = value }
          unless auth.nil?
            message.basic_auth(auth[0], auth[1])
          end
          unless body.nil?
            message.body = body
          end
        end
      end

      # CalDAV needs verbs Net::HTTP has no class for; GenericRequest carries
      # an arbitrary method, and a request with a body must say so.
      def message_class(method)
        METHODS.fetch(method, nil).then do |known|
          if known.nil?
            Class.new(Net::HTTPRequest) do
              const_set(:METHOD, method)
              const_set(:REQUEST_HAS_BODY, true)
              const_set(:RESPONSE_HAS_BODY, true)
            end
          else
            known
          end
        end
      end

      # Runs the request off the main loop and calls back on it.
      def async(method, url, **options, &callback)
        Thread.new do
          request(method, url, **options).then do |response|
            GLib::Idle.add do
              callback&.call(response)
              false
            end
          end
        end
      end
    end
  end
end
