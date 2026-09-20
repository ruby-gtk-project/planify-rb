# frozen_string_literal: true

module Planify
  # src/MainWindow.vala. Two nested overlay split views: the sidebar on the
  # start edge, the task detail pane on the end edge, and the view stack in
  # between. Views are cached by key so going back to a project keeps its
  # scroll position and expanded sections, which is what the upstream view
  # cache is for.
  class MainWindow
    def initialize(app)
      @app = app
      @views = {}
    end

    attr_reader :app, :window

    def build
      @window ||= Adwaita::ApplicationWindow.new(app).tap do |win|
        win.title = "Planify"
        win.icon_name = APP_ID
        win.set_default_size(Settings.get_int("window-width"), Settings.get_int("window-height"))
        win.set_size_request(360, 294)
        win.content = toast_overlay
        if Settings.get_boolean("window-maximized")
          win.maximize
        end
        win.add_breakpoint(narrow_breakpoint)

        toast_overlay.tap do |overlay|
          overlay.child = split_view

          split_view.tap do |sv|
            sv.sidebar = sidebar_toolbar
            sv.content = detail_split_view

            sidebar_toolbar.tap do |toolbar|
              toolbar.add_top_bar(sidebar_header)
              toolbar.content = sidebar.build

              sidebar_header.tap do |header|
                header.title_widget = sidebar_title
                header.pack_start(search_button)
                header.pack_end(menu_button)

                search_button.signal_connect("clicked") { open_quick_find }
              end
            end

            detail_split_view.tap do |dsv|
              dsv.content = views_stack
              dsv.sidebar = item_detail.build
            end
          end
        end

        win.signal_connect("close-request") do
          remember_geometry
          false
        end

        register_actions(win)

        item_detail.on_close = -> { detail_split_view.show_sidebar = false }
      end

      open_database
      @window
    end

    def present = window.present

    def toast(message)
      toast_overlay.add_toast(Adwaita::Toast.new(message))
    end

    # An undoable action: the toast carries the button that puts it back.
    def toast_with_undo(message, &undo)
      Adwaita::Toast.new(message).tap do |t|
        t.button_label = _("Undo")
        t.timeout = 3
        t.signal_connect("button-clicked") { undo.call }
        toast_overlay.add_toast(t)
      end
    end

    # --- startup --------------------------------------------------------

    def open_database
      if !store.database.healthy?
        views_stack.visible_child = database_error_page
      else
        store.load
        first_run
        sidebar.init
        go_homepage
        start_services
      end
    end

    def store = Store.instance

    # A Planner-era database is imported rather than left behind; only a
    # genuinely empty install gets the tutorial.
    def first_run
      if store.empty?
        if Services::MigrateFromPlanner.pending?
          Services::MigrateFromPlanner.migrate
          toast(_("Your tasks were imported from Planner."))
        else
          Seed.install(store)
        end
      end
    end

    def start_services
      Services::Notification.init(app)
      Services::TimeMonitor.init
      Services::BackupManager.init_auto_backup
      Services::Productivity.watch
      Services::DBusServer.register(app, self)
      check_for_updates
      sync_on_startup
    end

    def check_for_updates
      Services::Api.check do |release|
        new_version_popup.release = release
        sidebar.show_update(new_version_popup.build)
      end
    end

    # Accounts set to sync do so once at startup, and then on their own timer.
    def sync_on_startup
      store.synced_sources.select(&:sync_server?).each do |source|
        store.sync_source(source) { |_, _| nil }
      end
    end

    def new_version_popup
      @new_version_popup ||= NewVersionPopup.new do |version|
        Services::Api.dismiss(version)
        sidebar.hide_update
      end
    end

    HOME_VIEWS = {
      "inbox"     => -> { { key: "inbox" } },
      "today"     => -> { { key: "today" } },
      "scheduled" => -> { { key: "scheduled" } },
      "labels"    => -> { { key: "labels" } },
      "pinboard"  => -> { { key: "pinboard" } },
    }.freeze

    def go_homepage
      Settings.home_view.then do |view|
        if view.start_with?("project-")
          store.project(view.delete_prefix("project-")).then do |project|
            project.nil? ? show_filter("inbox") : show_project(project)
          end
        elsif HOME_VIEWS.key?(view)
          show_filter(view)
        else
          show_filter("inbox")
        end
      end
    end

    # --- navigation -----------------------------------------------------

    FILTER_VIEWS = {
      "labels"    => ->(window) { Views::LabelsView.new(window) },
      "today"     => ->(window) { Views::TodayView.new(window) },
      "scheduled" => ->(window) { Views::ScheduledView.new(window) },
    }.freeze

    # Today and Scheduled have enough structure of their own — sections,
    # overdue handling, calendar events — that they are their own views
    # rather than another FilterView configuration.
    def show_filter(key)
      FILTER_VIEWS.fetch(key, nil).then do |builder|
        if builder.nil?
          show_view("filter-#{key}") { Views::FilterView.new(self, key) }
        else
          show_view(view_key(key)) { builder.call(self) }
        end
      end
    end

    def view_key(key)
      if key == "labels"
        "labels"
      else
        "filter-#{key}"
      end
    end

    def show_project(project)
      show_view("project-#{project.id}") { Views::ProjectView.new(self, project) }
    end

    def show_label(label)
      show_view("label-#{label.id}") { Views::FilterView.new(self, "label", label: label) }
    end

    def show_view(key)
      @views[key] ||= yield.tap { |view| views_stack.add_named(view.build, key) }
      views_stack.visible_child_name = key
      sidebar.select(key)
      @views[key].refresh
      @views[key]
    end

    # A deleted or archived project must not leave its view behind.
    def drop_view(key)
      @views.delete(key).then do |view|
        unless view.nil?
          store.unsubscribe(view)
          views_stack.remove(view.root)
        end
      end
    end

    def show_item(item)
      item_detail.item = item
      detail_split_view.show_sidebar = true
    end

    def open_quick_find
      Dialogs::QuickFind.new(self).present(window)
    end

    def new_item
      QuickAdd.new(self).present(window)
    end

    def new_project
      Dialogs::ProjectDialog.new(self).present(window)
    end

    # --- actions --------------------------------------------------------

    WINDOW_ACTIONS = {
      "quick-find"     => :open_quick_find,
      "new-item"       => :new_item,
      "new-project"    => :new_project,
      "go-inbox"       => :go_inbox,
      "go-today"       => :go_today,
      "go-scheduled"   => :go_scheduled,
      "go-labels"      => :go_labels,
      "go-pinboard"    => :go_pinboard,
      "toggle-sidebar" => :toggle_sidebar,
      "sync"           => :sync,
    }.freeze

    # Takes the window rather than reading the memo: this runs from inside the
    # tap that creates it, before the assignment has happened.
    def register_actions(win)
      WINDOW_ACTIONS.each do |name, method|
        Gio::SimpleAction.new(name).tap do |action|
          action.signal_connect("activate") { public_send(method) }
          win.add_action(action)
        end
      end
    end

    def go_inbox = show_filter("inbox")

    def go_today = show_filter("today")

    def go_scheduled = show_filter("scheduled")

    def go_labels = show_filter("labels")

    def go_pinboard = show_filter("pinboard")

    def toggle_sidebar
      split_view.show_sidebar = !split_view.show_sidebar?
    end

    # Todoist, Nextcloud and CalDAV synchronisation are not ported; the action
    # stays so the keyboard shortcut and menu item behave predictably.
    def sync
      toast(_("Synchronization with third-party services is not available in this build"))
    end

    def remember_geometry
      Settings.set_int("window-width", window.default_width)
      Settings.set_int("window-height", window.default_height)
      Settings.set_boolean("window-maximized", window.maximized?)
    end

    # --- widgets --------------------------------------------------------

    def toast_overlay = @toast_overlay ||= Adwaita::ToastOverlay.new

    def split_view
      @split_view ||= Adwaita::OverlaySplitView.new.tap do |sv|
        sv.min_sidebar_width = Settings.get_int("pane-position")
        sv.max_sidebar_width = 380
        sv.sidebar_width_fraction = 0.25
      end
    end

    def detail_split_view
      @detail_split_view ||= Adwaita::OverlaySplitView.new.tap do |sv|
        sv.sidebar_position = Gtk::PackType::END
        sv.min_sidebar_width = 360
        sv.max_sidebar_width = 360
        sv.collapsed = !Settings.get_boolean("always-show-details-sidebar")
        sv.show_sidebar = Settings.get_boolean("always-show-details-sidebar")
      end
    end

    def narrow_breakpoint
      @narrow_breakpoint ||=
        Adwaita::Breakpoint.new(Adwaita::BreakpointCondition.parse("max-width: 675sp")).tap do |bp|
          bp.add_setter(split_view, "collapsed", true)
        end
    end

    def sidebar = @sidebar ||= Sidebar.new(self)

    def sidebar_toolbar
      @sidebar_toolbar ||= Adwaita::ToolbarView.new.tap do |toolbar|
        toolbar.top_bar_style = Adwaita::ToolbarStyle::FLAT
      end
    end

    def sidebar_header
      @sidebar_header ||= Adwaita::HeaderBar.new.tap do |header|
        header.add_css_class("flat")
        header.hexpand = true
      end
    end

    def sidebar_title
      @sidebar_title ||= Gtk::Label.new("Planify").tap do |label|
        label.add_css_class("title")
      end
    end

    def search_button
      @search_button ||= Gtk::Button.new(icon_name: "edit-find-symbolic").tap do |button|
        button.add_css_class("flat")
        button.tooltip_text = _("Open Quick Find")
      end
    end

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.icon_name = "open-menu-symbolic"
        button.add_css_class("flat")
        button.tooltip_text = _("Main Menu")
        button.menu_model = main_menu
      end
    end

    def main_menu
      @main_menu ||= Gio::Menu.new.tap do |menu|
        Gio::Menu.new.tap do |section|
          section.append(_("Preferences"), "app.preferences")
          section.append(_("Keyboard Shortcuts"), "app.shortcuts")
          menu.append_section(nil, section)
        end

        Gio::Menu.new.tap do |section|
          section.append(_("Sync"), "win.sync")
          menu.append_section(nil, section)
        end

        Gio::Menu.new.tap do |section|
          section.append(_("About Planify"), "app.about")
          section.append(_("Quit"), "app.quit")
          menu.append_section(nil, section)
        end
      end
    end

    def views_stack
      @views_stack ||= Gtk::Stack.new.tap do |stack|
        stack.hexpand = true
        stack.vexpand = true
        stack.transition_type = Gtk::StackTransitionType::CROSSFADE
        stack.add_named(database_error_page, "database-error")
      end
    end

    def item_detail = @item_detail ||= ItemDetail.new(self)

    def database_error_page
      @database_error_page ||= Adwaita::StatusPage.new.tap do |page|
        page.icon_name = "dialog-warning-symbolic"
        page.title = _("Database Error")
        page.description = _(
          "The database file appears to be corrupt. Restore a backup " \
                                       "from Preferences 🡒 Backups, or move the file aside and " \
                                       "restart Planify.",
        )
      end
    end
  end
end
