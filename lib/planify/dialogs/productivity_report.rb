# frozen_string_literal: true

module Planify
  module Dialogs
    # src/Dialogs/ProductivityReport. Counts against goals, the streak, a
    # year-long heat map, and where the completed work went.
    class ProductivityReport
      def present(parent)
        dialog.tap do |d|
          d.child = toolbar

          toolbar.tap do |view|
            view.add_top_bar(header)
            view.content = scrolled

            header.title_widget = Adwaita::WindowTitle.new(_("Productivity"), "")

            scrolled.child = clamp
            clamp.child = content_box

            content_box.append(cards_box)
            content_box.append(goals_group)
            content_box.append(heatmap_group)
            content_box.append(projects_group)

            cards_box.append(today_card.build)
            cards_box.append(week_card.build)
            cards_box.append(streak_card.build)

            goals_group.add(daily_row)
            goals_group.add(weekly_row)
            goals_group.add(dynamic_row)

            heatmap_group.add(heatmap_row)
            heatmap_row.child = heat_map.build

            wire_goals
          end

          refresh
          d.present(parent)
        end
      end

      def stats = Services::Productivity.stats

      def refresh
        stats.then do |current|
          today_card.value = current[:completed_today]
          today_card.subtitle = goal_text(current[:completed_today], current[:daily_goal])
          week_card.value = current[:completed_week]
          week_card.subtitle = goal_text(current[:completed_week], current[:weekly_goal])
          streak_card.value = current[:streak]
          streak_card.subtitle = n_("day", "days", current[:streak])
        end

        heat_map.data = Services::Productivity.heatmap
        reload_projects
      end

      def goal_text(done, goal)
        if goal.positive?
          _("of %d") % goal
        else
          ""
        end
      end

      def wire_goals
        daily_row.value = Settings.get_int("daily-task-goal")
        weekly_row.value = Settings.get_int("weekly-task-goal")
        dynamic_row.active = Settings.get_boolean("use-dynamic-goal")

        daily_row.signal_connect("notify::value") do
          Settings.set_int("daily-task-goal", daily_row.value.to_i)
          refresh
        end

        weekly_row.signal_connect("notify::value") do
          Settings.set_int("weekly-task-goal", weekly_row.value.to_i)
          refresh
        end

        dynamic_row.signal_connect("notify::active") do
          Settings.set_boolean("use-dynamic-goal", dynamic_row.active?)
          refresh_goal_sensitivity
          refresh
        end

        refresh_goal_sensitivity
      end

      # A dynamic goal is computed from what was actually due, so the manual
      # numbers have nothing to say while it is on.
      def refresh_goal_sensitivity
        Settings.get_boolean("use-dynamic-goal").then do |dynamic|
          daily_row.sensitive = !dynamic
          weekly_row.sensitive = !dynamic
        end
      end

      def reload_projects
        @project_rows ||= []
        @project_rows.each { |row| projects_group.remove(row) }

        Services::Productivity.per_project.first(10).then do |ranked|
          @project_rows = ranked.map { |(name, count)| project_row(name, count) }
          @project_rows.each { |row| projects_group.add(row) }
          projects_group.visible = !@project_rows.empty?
        end
      end

      def project_row(name, count)
        Adwaita::ActionRow.new.tap do |row|
          row.title = name
          row.add_suffix(
            Gtk::Label.new(count.to_s).tap do |label|
                        label.add_css_class("dim-label")
                        label.valign = :center
                      end,
          )
        end
      end

      def dialog
        @dialog ||= Adwaita::Dialog.new.tap do |d|
          d.title = _("Productivity")
          d.content_width = 620
          d.content_height = 640
        end
      end

      def toolbar = @toolbar ||= Adwaita::ToolbarView.new

      def header = @header ||= Adwaita::HeaderBar.new

      def scrolled
        @scrolled ||= Gtk::ScrolledWindow.new.tap do |scroll|
          scroll.hscrollbar_policy = :never
          scroll.vexpand = true
        end
      end

      def clamp
        @clamp ||= Adwaita::Clamp.new.tap do |c|
          c.maximum_size = 640
          c.margin_start = 12
          c.margin_end = 12
          c.margin_top = 12
          c.margin_bottom = 12
        end
      end

      def content_box = @content_box ||= Gtk::Box.new(:vertical, 18)

      def cards_box
        @cards_box ||= Gtk::Box.new(:horizontal, 0).tap { |b| b.homogeneous = true }
      end

      def today_card = @today_card ||= StatCard.new(_("Completed Today"), 0)

      def week_card = @week_card ||= StatCard.new(_("Completed This Week"), 0)

      def streak_card = @streak_card ||= StatCard.new(_("Streak"), 0)

      def goals_group
        @goals_group ||= Adwaita::PreferencesGroup.new.tap { |g| g.title = _("Goals") }
      end

      def daily_row
        @daily_row ||= Adwaita::SpinRow.new(
          Gtk::Adjustment.new(
            0,
            0,
            200,
            1,
            5,
            0,
          ),
          1,
          0,
        ).tap { |row| row.title = _("Daily Goal") }
      end

      def weekly_row
        @weekly_row ||= Adwaita::SpinRow.new(
          Gtk::Adjustment.new(
            0,
            0,
            1000,
            1,
            5,
            0,
          ),
          1,
          0,
        ).tap { |row| row.title = _("Weekly Goal") }
      end

      def dynamic_row
        @dynamic_row ||= Adwaita::SwitchRow.new.tap do |row|
          row.title = _("Dynamic Goal")
          row.subtitle = _("Use however many tasks were actually due")
        end
      end

      def heatmap_group
        @heatmap_group ||= Adwaita::PreferencesGroup.new.tap do |g|
          g.title = _("The Last Year")
        end
      end

      def heatmap_row
        @heatmap_row ||= Adwaita::PreferencesRow.new.tap do |row|
          row.activatable = false
        end
      end

      def heat_map = @heat_map ||= HeatMap.new

      def projects_group
        @projects_group ||= Adwaita::PreferencesGroup.new.tap do |g|
          g.title = _("Completed By Project")
          g.visible = false
        end
      end
    end

    # src/Dialogs/ItemChangeHistory.vala, as a dialog of its own for when the
    # detail pane's short list is not enough.
    class ItemChangeHistory
      def initialize(item)
        @item = item
      end

      attr_reader :item

      def present(parent)
        dialog.tap do |d|
          d.child = toolbar

          toolbar.tap do |view|
            view.add_top_bar(header)
            view.content = scrolled
            header.title_widget = Adwaita::WindowTitle.new(_("Activity"), item.content.to_s)
            scrolled.child = page
            page.add(group)
          end

          reload
          d.present(parent)
        end
      end

      def reload
        Store.instance.events_for_item(item.id).then do |events|
          events.each { |event| group.add(ItemChangeHistoryRow.new(event).build) }
          if events.empty?
            group.description = _("Nothing recorded yet")
          else
            group.description = nil
          end
        end
      end

      def dialog
        @dialog ||= Adwaita::Dialog.new.tap do |d|
          d.title = _("Activity")
          d.content_width = 480
          d.content_height = 560
        end
      end

      def toolbar = @toolbar ||= Adwaita::ToolbarView.new

      def header = @header ||= Adwaita::HeaderBar.new

      def scrolled
        @scrolled ||= Gtk::ScrolledWindow.new.tap do |scroll|
          scroll.hscrollbar_policy = :never
          scroll.vexpand = true
        end
      end

      def page = @page ||= Adwaita::PreferencesPage.new

      def group = @group ||= Adwaita::PreferencesGroup.new
    end

    # src/Dialogs/ErrorDialog.vala: what a failed sync or a corrupt database
    # shows, with the log tail attached so a report is actionable.
    class ErrorDialog
      def initialize(title, message)
        @title = title
        @message = message
      end

      def present(parent)
        dialog.tap do |d|
          d.child = toolbar

          toolbar.tap do |view|
            view.add_top_bar(header)
            view.content = box

            box.append(status_page)
            box.append(log_expander)

            log_expander.add_row(log_row)
            log_row.child = log_view_scrolled
            log_view_scrolled.child = log_view
            log_view.buffer.text = Services::LogService.tail(100)

            header.pack_end(copy_button)
            copy_button.signal_connect("clicked") { copy }
          end

          d.present(parent)
        end
      end

      def copy
        Gdk::Display.default.clipboard.set(Services::LogService.tail(100))
      end

      def dialog
        @dialog ||= Adwaita::Dialog.new.tap do |d|
          d.title = @title
          d.content_width = 560
          d.content_height = 520
        end
      end

      def toolbar = @toolbar ||= Adwaita::ToolbarView.new

      def header = @header ||= Adwaita::HeaderBar.new

      def copy_button
        @copy_button ||= Gtk::Button.new(icon_name: "clipboard-symbolic").tap do |button|
          button.add_css_class("flat")
          button.tooltip_text = _("Copy the Log")
        end
      end

      def box
        @box ||= Gtk::Box.new(:vertical, 12).tap do |b|
          b.margin_start = 12
          b.margin_end = 12
          b.margin_bottom = 12
        end
      end

      def status_page
        @status_page ||= Adwaita::StatusPage.new.tap do |p|
          p.icon_name = "dialog-warning-symbolic"
          p.title = @title
          p.description = @message
        end
      end

      def log_expander
        @log_expander ||= Adwaita::ExpanderRow.new.tap do |row|
          row.title = _("Recent Log")
          row.add_css_class("card")
        end
      end

      def log_row
        @log_row ||= Adwaita::PreferencesRow.new.tap { |row| row.activatable = false }
      end

      def log_view_scrolled
        @log_view_scrolled ||= Gtk::ScrolledWindow.new.tap do |scroll|
          scroll.height_request = 200
        end
      end

      def log_view
        @log_view ||= Gtk::TextView.new.tap do |view|
          view.editable = false
          view.monospace = true
          view.top_margin = 6
          view.bottom_margin = 6
          view.left_margin = 6
          view.right_margin = 6
        end
      end
    end
  end
end
