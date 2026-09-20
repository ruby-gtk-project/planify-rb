# frozen_string_literal: true

module Planify
  module Dialogs
    # The shortcuts window, listing the accelerators Application registers.
    class Shortcuts
      GROUPS = {
        -> { _("General") }    => [
          [-> { _("Open Quick Find") }, "<Control>f"],
          [-> { _("Preferences") }, "<Control>comma"],
          [-> { _("Keyboard Shortcuts") }, "<Control>question"],
          [-> { _("Quit") }, "<Control>q"],
        ],
        -> { _("Tasks") }      => [
          [-> { _("New Task") }, "<Control>n"],
          [-> { _("New Project") }, "<Control><Shift>n"],
          [-> { _("Sync") }, "<Control>s"],
        ],
        -> { _("Navigation") } => [
          [-> { _("Inbox") }, "<Control>1"],
          [-> { _("Today") }, "<Control>2"],
          [-> { _("Scheduled") }, "<Control>3"],
          [-> { _("Labels") }, "<Control>4"],
          [-> { _("Pinboard") }, "<Control>5"],
          [-> { _("Toggle Sidebar") }, "F9"],
        ],
      }.freeze

      def present(parent)
        dialog.tap do |d|
          d.child = page

          GROUPS.each do |title, shortcuts|
            page.add(group(title.call, shortcuts))
          end

          d.present(parent)
        end
      end

      def group(title, shortcuts)
        Adwaita::PreferencesGroup.new.tap do |g|
          g.title = title
          shortcuts.each { |(label, accel)| g.add(shortcut_row(label.call, accel)) }
        end
      end

      def shortcut_row(label, accel)
        Adwaita::ActionRow.new.tap do |row|
          row.title = label
          row.add_suffix(Gtk::ShortcutLabel.new(accel).tap { |s| s.valign = :center })
        end
      end

      def dialog
        @dialog ||= Adwaita::Dialog.new.tap do |d|
          d.title = _("Keyboard Shortcuts")
          d.content_width = 480
          d.content_height = 600
        end
      end

      def page
        @page ||= Adwaita::PreferencesPage.new.tap do |p|
          p.title = _("Keyboard Shortcuts")
        end
      end
    end
  end
end
