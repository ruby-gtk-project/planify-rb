# frozen_string_literal: true

module Planify
  # quick-add/. The quick-add dialog as an application of its own: one task,
  # then it exits. It writes to the same database and tells a running window
  # over the bus, so the task appears there without a restart.
  class QuickAddApplication
    APP_ID = "io.github.alainm23.planify.quickadd"

    def build
      app.tap do |a|
        a.signal_connect("startup") do
          Theme.update
          register_icons
        end

        a.signal_connect("activate") do
          store.load
          window.present
          quick_add.present(window)
        end
      end
    end

    def run(argv = []) = app.run(argv)

    def store = @store ||= Store.instance

    def app = @app ||= Gtk::Application.new(APP_ID, :default_flags)

    # The dialog needs a parent to present into, and the parent is never
    # shown: a hidden window is what makes the dialog the whole of the UI.
    def window
      @window ||= Adwaita::ApplicationWindow.new(app).tap do |win|
        win.title = _("Add To-Do")
        win.set_default_size(1, 1)
        win.content = Adwaita::Bin.new
      end
    end

    def quick_add
      @quick_add ||= QuickAdd.new(shim).tap do |dialog|
        dialog.on_finish = -> { app.quit }
      end
    end

    # QuickAdd talks to a MainWindow; here there is none, so a small stand-in
    # answers the three things it actually uses.
    def shim = @shim ||= Shim.new(self)

    class Shim
      def initialize(application)
        @application = application
      end

      attr_reader :application

      def window = application.window

      def toast(message)
        Services::LogService.info("QuickAdd", message.to_s)
      end

      def toast_with_undo(message, &_undo) = toast(message)

      def show_item(_item) = nil
    end

    def register_icons
      File.join(Paths.data, "planify.gresource").then do |path|
        if File.exist?(path)
          Gio::Resource.load(path).tap(&:_register)
        end
      end

      Gtk::IconTheme.get_for_display(Gdk::Display.default).tap do |theme|
        theme.add_resource_path("/io/github/alainm23/planify/")
        theme.add_search_path(File.join(Paths.data, "icons"))
      end
    end
  end
end
