# frozen_string_literal: true

module Planify
  # src/App.vala: the application object, its actions, the stylesheet and the
  # icon search path. Adwaita::Application is broken in the Ruby bindings, so
  # the application is a Gtk one and only the window is Adwaita's.
  class Application
    def build
      app.tap do |a|
        a.signal_connect("startup") do
          load_stylesheet
          register_icons
          Theme.update
          Theme.watch
          register_actions
        end

        a.signal_connect("activate") do
          main_window.build
          main_window.present
        end
      end
    end

    def run(argv = []) = app.run(argv)

    def app = @app ||= Gtk::Application.new(APP_ID, :default_flags)

    def main_window = @main_window ||= MainWindow.new(app)

    def load_stylesheet
      Gtk::StyleContext.add_provider_for_display(
        Gdk::Display.default,
        css_provider,
        Gtk::StyleProvider::PRIORITY_APPLICATION,
      )
    end

    # Planify ships its stylesheet as several files that its gresource
    # concatenates; loading them in the same order keeps the cascade intact.
    def css_provider
      @css_provider ||= Gtk::CssProvider.new.tap do |provider|
        provider.load(data: stylesheet)
      end
    end

    def stylesheet
      %w[variables typography animations calendar sidebar stylesheet]
        .filter_map { |name| File.join(Paths.resources, "stylesheet", "#{name}.css") }
        .select { |path| File.exist?(path) }
        .map { |path| File.read(path) }
        .join("\n")
    end

    # Planify's ~90 symbolic icons live in its gresource under
    # icons/scalable/actions, which is the layout Gtk::IconTheme expects on a
    # resource path. A flat directory of SVGs is not, which is why the bundle
    # is registered rather than the source directory.
    def register_icons
      register_resources

      Gtk::IconTheme.get_for_display(Gdk::Display.default).tap do |theme|
        theme.add_resource_path("/io/github/alainm23/planify/")
        theme.add_search_path(File.join(Paths.data, "icons"))
      end
    end

    def register_resources
      File.join(Paths.data, "planify.gresource").then do |path|
        if File.exist?(path)
          Gio::Resource.load(path).tap(&:_register)
        end
      end
    end

    APP_ACTIONS = {
      "quit"        => :quit,
      "preferences" => :show_preferences,
      "shortcuts"   => :show_shortcuts,
      "about"       => :show_about,
    }.freeze

    def register_actions
      APP_ACTIONS.each do |name, method|
        Gio::SimpleAction.new(name).tap do |action|
          action.signal_connect("activate") { public_send(method) }
          app.add_action(action)
        end
      end

      Services::ActionManager.install(app)
    end

    def quit = app.quit

    def show_preferences
      Dialogs::Preferences.new.present(main_window.window)
    end

    def show_shortcuts
      Dialogs::Shortcuts.new.present(main_window.window)
    end

    def show_about
      Adwaita::AboutDialog.new.tap do |about|
        about.application_name = "Planify"
        about.application_icon = APP_ID
        about.version = VERSION
        about.developer_name = "Alain M."
        about.website = WEBSITE
        about.issue_url = ISSUES
        about.license_type = Gtk::License::GPL_3_0
        about.comments = _("Forget about forgetting things")
        about.present(main_window.window)
      end
    end
  end
end
