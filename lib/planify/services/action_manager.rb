# frozen_string_literal: true

module Planify
  module Services
    # src/Services/ActionManager.vala. The accelerator table, kept in one
    # place so the shortcuts window and the application agree on it by
    # construction rather than by being edited together.
    module ActionManager
      ACCELS = {
        "app.quit"             => ["<Control>q", "<Control>w"],
        "app.preferences"      => ["<Control>comma"],
        "app.shortcuts"        => ["<Control>question", "F1"],
        "win.quick-find"       => ["<Control>f"],
        "win.new-item"         => ["<Control>n", "a"],
        "win.new-item-paste"   => ["<Control><Shift>v"],
        "win.new-project"      => ["<Control><Shift>n"],
        "win.new-section"      => ["<Control><Shift>s"],
        "win.sync"             => ["<Control>s"],
        "win.go-home"          => ["<Control>h"],
        "win.go-inbox"         => ["<Control>1"],
        "win.go-today"         => ["<Control>2"],
        "win.go-scheduled"     => ["<Control>3"],
        "win.go-labels"        => ["<Control>4"],
        "win.go-pinboard"      => ["<Control>5"],
        "win.go-completed"     => ["<Control>6"],
        "win.next-project"     => ["<Control>Page_Down"],
        "win.previous-project" => ["<Control>Page_Up"],
        "win.toggle-sidebar"   => ["F9"],
        "win.toggle-details"   => ["F10"],
        "win.manage-projects"  => ["<Control><Shift>p"],
        "win.completed-tasks"  => ["<Control><Shift>c"],
        "win.productivity"     => ["<Control><Shift>r"],
      }.freeze

      # What the shortcuts window shows, grouped and in reading order.
      GROUPS = [
        [-> { _("General") }, %w[
          win.quick-find app.preferences app.shortcuts win.sync app.quit
        ]
],
        [-> { _("Tasks and Projects") }, %w[
          win.new-item win.new-item-paste win.new-project win.new-section
          win.completed-tasks win.manage-projects win.productivity
        ]
],
        [-> { _("Navigation") }, %w[
          win.go-home win.go-inbox win.go-today win.go-scheduled win.go-labels
          win.go-pinboard win.go-completed win.next-project win.previous-project
          win.toggle-sidebar win.toggle-details
        ]
],
      ].freeze

      TITLES = {
        "app.quit"             => -> { _("Quit") },
        "app.preferences"      => -> { _("Preferences") },
        "app.shortcuts"        => -> { _("Keyboard Shortcuts") },
        "win.quick-find"       => -> { _("Open Quick Find") },
        "win.new-item"         => -> { _("New Task") },
        "win.new-item-paste"   => -> { _("New Tasks From the Clipboard") },
        "win.new-project"      => -> { _("New Project") },
        "win.new-section"      => -> { _("New Section") },
        "win.sync"             => -> { _("Sync") },
        "win.go-home"          => -> { _("Home") },
        "win.go-inbox"         => -> { _("Inbox") },
        "win.go-today"         => -> { _("Today") },
        "win.go-scheduled"     => -> { _("Scheduled") },
        "win.go-labels"        => -> { _("Labels") },
        "win.go-pinboard"      => -> { _("Pinboard") },
        "win.go-completed"     => -> { _("Completed") },
        "win.next-project"     => -> { _("Next Project") },
        "win.previous-project" => -> { _("Previous Project") },
        "win.toggle-sidebar"   => -> { _("Toggle Sidebar") },
        "win.toggle-details"   => -> { _("Toggle Task Details") },
        "win.manage-projects"  => -> { _("Manage Projects") },
        "win.completed-tasks"  => -> { _("Completed Tasks") },
        "win.productivity"     => -> { _("Productivity") },
      }.freeze

      module_function

      # "a" alone is a shortcut only when nothing has focus that wants it, so
      # the single-key accelerators are filtered out of the global table and
      # handled by a key controller on the window instead.
      def global_accels
        ACCELS.transform_values { |accels| accels.reject { |accel| accel.length == 1 } }
              .reject { |_, accels| accels.empty? }
      end

      def single_key_accels
        ACCELS.filter_map do |action, accels|
          accels.find { |accel| accel.length == 1 }.then do |accel|
            unless accel.nil?
              [accel, action]
            end
          end
        end.to_h
      end

      def install(app)
        global_accels.each { |action, accels| app.set_accels_for_action(action, accels) }
      end

      def title_for(action) = TITLES.fetch(action, -> { action }).call

      def accel_for(action) = ACCELS.fetch(action, []).first.to_s
    end
  end
end
