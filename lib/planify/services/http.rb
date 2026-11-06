# frozen_string_literal: true

require "soup3"

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
        build(
          method,
          url,
          body,
          headers,
          auth,
          ignore_ssl,
        ).then do |msg|
          session.send_and_read(msg, nil).then do |bytes|
            Response.new(
              msg.status_code,
              bytes.to_s,
              response_headers(msg),
              nil,
            )
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

      # A fresh session per request, the way a fresh Net::HTTP was used
      # before.
      def session
        Soup::Session.new.tap do |s|
          s.timeout = 60
          s.idle_timeout = 20
        end
      end

      def build(method, url, body, headers, auth, ignore_ssl)
        Soup::Message.new(method, url).tap do |msg|
          headers.each { |name, value| msg.request_headers.append(name.to_s, value.to_s) }
          unless auth.nil?
            msg.request_headers.append("Authorization", basic_auth(auth[0], auth[1]))
          end
          unless body.nil?
            msg.set_request_body_from_bytes(
              headers.fetch("Content-Type", "application/octet-stream"),
              GLib::Bytes.new(body),
            )
          end
          # Nextcloud on a self-signed certificate is common enough that
          # Planify offers the switch per source. In libsoup3 the certificate
          # signal lives on the message, not the session.
          if ignore_ssl
            msg.signal_connect("accept-certificate") { |*_args| true }
          end
        end
      end

      def basic_auth(user, pass)
        "Basic #{Base64.strict_encode64("#{user}:#{pass}")}"
      end

      def response_headers(msg)
        {}.tap do |hash|
          msg.response_headers.each { |name, value| hash[name] = value }
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
