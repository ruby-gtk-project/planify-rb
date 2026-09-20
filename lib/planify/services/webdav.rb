# frozen_string_literal: true

require "rexml/document"

module Planify
  module Services
    # The WebDAV half of core/Services/CalDAV: PROPFIND and REPORT, and
    # enough of a multistatus reader to pull hrefs and properties out of the
    # replies. Namespaces are ignored on lookup, because servers disagree
    # about prefixes far more than they disagree about element names.
    module WebDAV
      Resource = Struct.new(:href, :props, :status) do
        def ok? = status.nil? || status.include?("200")

        def prop(name) = props[name.downcase]
      end

      module_function

      def credentials(source) = [source["username"].to_s, source["password"].to_s]

      def request(source, method, url, body: nil, headers: {}, &callback)
        Http.async(
          method,
          absolute(source, url),
          body:       body,
          headers:    { "Content-Type" => "application/xml; charset=utf-8" }.merge(headers),
          auth:       credentials(source),
          ignore_ssl: source["ignore_ssl"] == true,
          &callback
        )
      end

      def propfind(source, url, xml, depth = "0", &callback)
        request(
          source,
          "PROPFIND",
          url,
          body:    xml,
          headers: { "Depth" => depth },
        ) do |response|
          callback.call(response, response.ok? ? resources(response.body) : [])
        end
      end

      def report(source, url, xml, depth = "1", &callback)
        request(
          source,
          "REPORT",
          url,
          body:    xml,
          headers: { "Depth" => depth },
        ) do |response|
          callback.call(response, response.ok? ? resources(response.body) : [])
        end
      end

      # A server may answer with a path, a scheme-relative URL or an absolute
      # one; all three have to end up absolute against the account's server.
      def absolute(source, url)
        if url.to_s.empty?
          source.server_url
        elsif url.to_s.start_with?("http://", "https://")
          url.to_s
        else
          URI.join(source.server_url, url.to_s).to_s
        end
      rescue URI::Error
        source.server_url
      end

      # --- multistatus parsing --------------------------------------------

      def resources(body)
        document(body).then do |doc|
          if doc.nil?
            []
          else
            each_element(doc.root, "response").flat_map { |node| response_resources(node) }
          end
        end
      end

      def document(body)
        REXML::Document.new(body.to_s)
      rescue REXML::ParseException => error
        LogService.warn("WebDAV", "unparseable reply: #{error.message}")
        nil
      end

      # One <response> can carry several <propstat> blocks, one per status.
      def response_resources(node)
        text_of(node, "href").then do |href|
          each_element(node, "propstat").map do |propstat|
            Resource.new(href, collect_props(propstat), text_of(propstat, "status"))
          end.then { |found| found.empty? ? [Resource.new(href, {}, nil)] : found }
        end
      end

      def collect_props(propstat)
        {}.tap do |props|
          each_element(propstat, "prop").each do |prop|
            prop.elements.each { |element| props[local_name(element).downcase] = element }
          end
        end
      end

      def local_name(element) = element.name.to_s.split(":").last.to_s

      # Depth-first search by local name, so a d:href and a D:href both match.
      # XPath is avoided deliberately: the prefix a server chose is not
      # something to match on, and half of them omit the namespace entirely.
      def each_element(node, name) = descend(node, name)

      def descend(node, name)
        [].tap do |found|
          walk(node) do |element|
            if local_name(element).casecmp?(name)
              found << element
            end
          end
        end
      end

      def walk(node, &block)
        node.elements.each do |element|
          block.call(element)
          walk(element, &block)
        end
      end

      def text_of(node, name)
        descend(node, name).first&.text.to_s.strip
      end

      def href_in(element)
        descend(element, "href").first&.text.to_s.strip
      end
    end
  end
end
