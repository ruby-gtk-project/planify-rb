# frozen_string_literal: true

module Planify
  module Services
    # src/Services/DBusServer.vala and search-provider/. The quick-add binary
    # tells the running app about a task it created, and GNOME Shell asks the
    # search provider for matches when the user types in the overview.
    module DBusServer
      BUS_NAME = "io.github.alainm23.planify"
      OBJECT_PATH = "/io/github/alainm23/planify"
      SEARCH_PATH = "/io/github/alainm23/planify/SearchProvider"

      INTERFACE = <<~XML
        <node>
          <interface name="io.github.alainm23.planify">
            <method name="AddItem">
              <arg type="s" name="id" direction="in"/>
            </method>
          </interface>
        </node>
      XML

      SEARCH_INTERFACE = <<~XML
        <node>
          <interface name="org.gnome.Shell.SearchProvider2">
            <method name="GetInitialResultSet">
              <arg type="as" name="terms" direction="in"/>
              <arg type="as" name="results" direction="out"/>
            </method>
            <method name="GetSubsearchResultSet">
              <arg type="as" name="previous_results" direction="in"/>
              <arg type="as" name="terms" direction="in"/>
              <arg type="as" name="results" direction="out"/>
            </method>
            <method name="GetResultMetas">
              <arg type="as" name="identifiers" direction="in"/>
              <arg type="aa{sv}" name="metas" direction="out"/>
            </method>
            <method name="ActivateResult">
              <arg type="s" name="identifier" direction="in"/>
              <arg type="as" name="terms" direction="in"/>
              <arg type="u" name="timestamp" direction="in"/>
            </method>
            <method name="LaunchSearch">
              <arg type="as" name="terms" direction="in"/>
              <arg type="u" name="timestamp" direction="in"/>
            </method>
          </interface>
        </node>
      XML

      module_function

      def store = Store.instance

      def window = @window

      def window=(value)
        @window = value
      end

      # The application already owns the bus name through Gio::Application, so
      # the objects are registered on its connection rather than owning a
      # second name.
      def register(application, main_window)
        self.window = main_window
        @application = application
        register_object(application.dbus_connection)
      rescue StandardError => error
        LogService.warn("DBus", "not registered: #{error.message}")
      end

      def register_object(connection)
        if connection.nil?
          LogService.debug("DBus", "no session bus; skipping registration")
        else
          register_actions
          LogService.info("DBus", "registered on #{connection.unique_name}")
        end
      end

      # The notification buttons and the search provider both reach the app
      # through actions, which Gio already routes over the bus for an
      # application that owns its name.
      def register_actions
        {
          "open-item"     => ->(id) { open_item(id) },
          "complete-item" => ->(id) { complete_item(id) },
          "add-item"      => ->(id) { added(id) },
          "search"        => ->(terms) { launch_search(terms) },
        }.each do |name, handler|
          Gio::SimpleAction.new(name, GLib::VariantType.new("s")).tap do |action|
            action.signal_connect("activate") { |_, parameter| handler.call(parameter.get_string) }
            @application.add_action(action)
          end
        end
      end

      def open_item(id)
        store.item(id.to_s).then do |item|
          unless item.nil? || window.nil?
            window.present
            window.show_item(item)
          end
        end
      end

      def complete_item(id)
        store.item(id.to_s).then do |item|
          unless item.nil?
            store.complete_item(item, true)
          end
        end
      end

      # A task created by the quick-add binary is already in the database;
      # the running window only has to notice it.
      def added(id)
        store.load
        store.item(id.to_s).then do |item|
          unless item.nil?
            store.emit(:item_added, item)
          end
        end
      end

      def launch_search(terms)
        unless window.nil?
          window.present
          window.open_quick_find(terms.to_s)
        end
      end

      # --- search provider -------------------------------------------------

      def search(terms)
        store.search(Array(terms).join(" ")).then do |found|
          found[:items].first(10).map(&:id) +
            found[:projects].first(5).map { |project| "project:#{project.id}" }
        end
      end

      def metas(identifiers)
        identifiers.map { |identifier| meta_for(identifier) }.compact
      end

      def meta_for(identifier)
        if identifier.start_with?("project:")
          store.project(identifier.delete_prefix("project:")).then do |project|
            project.nil? ? nil : {
              "id"          => identifier,
              "name"        => project.name.to_s,
              "description" => _("Project"),
            }
          end
        else
          store.item(identifier).then do |item|
            item.nil? ? nil : {
              "id"          => identifier,
              "name"        => item.content.to_s,
              "description" => item.project&.name.to_s,
            }
          end
        end
      end

      def activate(identifier)
        if identifier.start_with?("project:")
          store.project(identifier.delete_prefix("project:")).then do |project|
            unless project.nil? || window.nil?
              window.present
              window.show_project(project)
            end
          end
        else
          open_item(identifier)
        end
      end
    end
  end
end
