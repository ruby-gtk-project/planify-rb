# frozen_string_literal: true

module Planify
  module Dialogs
    # src/Dialogs/Preferences/PreferencesWindow.vala. The dialog itself only
    # assembles the pages; each page is its own class under Pages.
    class Preferences
      def present(parent)
        dialog.tap do |d|
          pages.each { |page| d.add(page) }
          d.present(parent)
        end
      end

      def pages
        @pages ||= [
          general.page,
          sidebar.page,
          appearance.page,
          accounts.page,
          calendar.page,
          backups.page,
          about.page,
        ]
      end

      def general = @general ||= Pages::General.new(dialog)

      def sidebar = @sidebar ||= Pages::SidebarPage.new

      def appearance = @appearance ||= Pages::Appearance.new

      def accounts = @accounts ||= Pages::Accounts.new(dialog)

      def calendar = @calendar ||= Pages::CalendarEvents.new

      def backups = @backups ||= Pages::Backups.new(dialog)

      def about = @about ||= Pages::Donate.new(dialog)

      def dialog
        @dialog ||= Adwaita::PreferencesDialog.new.tap do |d|
          d.title = _("Preferences")
          d.search_enabled = true
        end
      end
    end
  end
end
