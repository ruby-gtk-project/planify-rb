# frozen_string_literal: true

require "gobject-introspection"

module Planify
  module Services
    # Some typelibs carry names that are not legal Ruby constants — ICalGLib
    # has an enum value "8BIT" and another starting with a digit — and the
    # stock loader aborts the whole namespace on the first one. Skipping just
    # those entries leaves everything else usable, which is what libecal needs
    # to be reachable at all.
    class TolerantLoader < GObjectIntrospection::Loader
      def load_info(info)
        super
      rescue NameError => error
        skipped << [info.respond_to?(:name) ? info.name : info.class.to_s, error.message]
        nil
      end

      def skipped = @skipped ||= []
    end

    module GI
      module_function

      # Loads a namespace into a module of the same name, once. Returns false
      # rather than raising when the typelib is not installed, because every
      # namespace loaded this way backs an optional feature.
      def load(name)
        loaded.fetch(name) do
          loaded[name] = attempt(name)
        end
      end

      def loaded = @loaded ||= {}

      def attempt(name)
        unless Object.const_defined?(name)
          Object.const_set(name, Module.new)
        end

        TolerantLoader.new(Object.const_get(name)).tap do |loader|
          loader.load(name)
          unless loader.skipped.empty?
            LogService.debug("GI", "#{name}: skipped #{loader.skipped.map(&:first).join(', ')}")
          end
        end

        true
      rescue StandardError, LoadError => error
        LogService.info("GI", "#{name} unavailable: #{error.message}")
        false
      end
    end
  end
end
