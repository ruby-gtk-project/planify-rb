# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "securerandom"
require "time"
require "uri"
require "base64"
require "digest"

require "gtk4"
require "adwaita"
require "sqlite3"
require "gettext"
require "cgi"

module Planify
  APP_ID = "io.github.alainm23.planify"
  VERSION = "4.20.0"
  WEBSITE = "https://github.com/alainm23/planify"
  ISSUES = "https://github.com/alainm23/planify/issues"

  include GetText

  # A test run drives the real window, but it must not reach the network, own
  # a bus name, or write automatic backups into the user's data directory.
  # PLANIFY_TEST turns those off and nothing else, so what is under test is
  # still the code that ships.
  def self.test_mode? = ENV.key?("PLANIFY_TEST")
end

require_relative "planify/paths"
require_relative "planify/translations"

require_relative "planify/palette"
require_relative "planify/datetime"
require_relative "planify/recurrency"
require_relative "planify/settings"
require_relative "planify/theme"
require_relative "planify/models"
require_relative "planify/database"
require_relative "planify/store"
require_relative "planify/seed"

require_relative "planify/services/log_service"
require_relative "planify/services/gi"
require_relative "planify/services/http"
require_relative "planify/services/event_bus"
require_relative "planify/services/sync_queue"
require_relative "planify/services/ical"
require_relative "planify/services/webdav"
require_relative "planify/services/todoist"
require_relative "planify/services/caldav"
require_relative "planify/services/deck"
require_relative "planify/services/calendar_events"
require_relative "planify/services/notification"
require_relative "planify/services/time_monitor"
require_relative "planify/services/backup_manager"
require_relative "planify/services/export_service"
require_relative "planify/services/productivity"
require_relative "planify/services/api"
require_relative "planify/services/migrate_from_planner"
require_relative "planify/services/action_manager"
require_relative "planify/services/dbus_server"


require_relative "planify/markdown"

require_relative "planify/widgets/small"
require_relative "planify/widgets/context_menu"
require_relative "planify/widgets/markdown_editor"
require_relative "planify/widgets/emoji_picker"
require_relative "planify/widgets/color_picker"
require_relative "planify/widgets/repeat_config"
require_relative "planify/widgets/date_time_picker"
require_relative "planify/widgets/reminder_picker"
require_relative "planify/widgets/project_picker"
require_relative "planify/widgets/attachments"
require_relative "planify/widgets/filter_flow_box"
require_relative "planify/widgets/misc"
require_relative "planify/widgets/label_picker"
require_relative "planify/widgets/priority_picker"
require_relative "planify/widgets/item_row"
require_relative "planify/widgets/section_row"
require_relative "planify/widgets/project_row"
require_relative "planify/widgets/item_detail"
require_relative "planify/widgets/quick_add"
require_relative "planify/widgets/sidebar_widgets"
require_relative "planify/widgets/section_board"

require_relative "planify/views/sorting"
require_relative "planify/views/base_view"
require_relative "planify/views/filter_view"
require_relative "planify/views/project_view"
require_relative "planify/views/labels_view"
require_relative "planify/views/today_view"
require_relative "planify/views/scheduled_view"

require_relative "planify/dialogs/project_dialog"
require_relative "planify/dialogs/section_dialog"
require_relative "planify/dialogs/label_dialog"
require_relative "planify/dialogs/quick_find"
require_relative "planify/dialogs/manage"
require_relative "planify/dialogs/productivity_report"
require_relative "planify/dialogs/date_picker_dialog"
require_relative "planify/dialogs/preferences_pages"
require_relative "planify/dialogs/accounts_page"
require_relative "planify/dialogs/donate_page"
require_relative "planify/dialogs/preferences"
require_relative "planify/dialogs/shortcuts"

require_relative "planify/sidebar"
require_relative "planify/main_window"
require_relative "planify/cli"
require_relative "planify/application"
require_relative "planify/quick_add_application"
