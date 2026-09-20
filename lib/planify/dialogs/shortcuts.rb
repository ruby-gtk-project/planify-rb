# frozen_string_literal: true

module Planify
  module Dialogs
    # The shortcuts window. Its contents come from ActionManager, so it cannot
    # drift from the accelerators the application actually installs.
    class Shortcuts
      def present(parent)
        dialog.tap do |d|
          d.child = scrolled
          scrolled.child = page

          Services::ActionManager::GROUPS.each do |(title, actions)|
            page.add(group(title.call, actions))
          end

          d.present(parent)
        end
      end

      def group(title, actions)
        Adwaita::PreferencesGroup.new.tap do |g|
          g.title = title
          actions.each { |action| g.add(shortcut_row(action)) }
        end
      end

      def shortcut_row(action)
        Adwaita::ActionRow.new.tap do |row|
          row.title = Services::ActionManager.title_for(action)
          row.add_suffix(accel_label(action))
        end
      end

      def accel_label(action)
        Gtk::ShortcutLabel.new(Services::ActionManager.accel_for(action)).tap do |label|
          label.valign = :center
        end
      end

      def dialog
        @dialog ||= Adwaita::Dialog.new.tap do |d|
          d.title = _("Keyboard Shortcuts")
          d.content_width = 480
          d.content_height = 600
        end
      end

      def scrolled
        @scrolled ||= Gtk::ScrolledWindow.new.tap do |scroll|
          scroll.hscrollbar_policy = :never
          scroll.vexpand = true
        end
      end

      def page
        @page ||= Adwaita::PreferencesPage.new.tap { |p| p.title = _("Keyboard Shortcuts") }
      end
    end
  end
end
