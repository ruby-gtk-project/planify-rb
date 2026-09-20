# frozen_string_literal: true

module Planify
  module Dialogs
    module Pages
      # src/Dialogs/Preferences/Pages/Sidebar.vala. Which filters appear in
      # the sidebar and in what order — the setting the default leaves at four
      # of the six, so without this page the other two are unreachable except
      # by keyboard.
      class SidebarPage
        include Bindings

        KEY = "views-order-visible"

        def page
          @page ||= Adwaita::PreferencesPage.new.tap do |p|
            p.title = _("Sidebar")
            p.icon_name = "dock-left-symbolic"
            p.add(layout_group)
            p.add(filters_group)

            layout_group.add(list_view_row)
            layout_group.add(count_row)

            reload
          end
        end

        def layout_group
          @layout_group ||= Adwaita::PreferencesGroup.new.tap { |g| g.title = _("Layout") }
        end

        def list_view_row
          @list_view_row ||= bind_switch(
            switch_row(_("Filters as a List"), _("Show the filters as rows instead of tiles")),
            "filters-list-view",
          )
        end

        def count_row
          @count_row ||= bind_switch(switch_row(_("Show Task Count")), "show-tasks-count")
        end

        def filters_group
          @filters_group ||= Adwaita::PreferencesGroup.new.tap do |g|
            g.title = _("Filters")
            g.description = _(
              "Turn a filter off to hide it, and use the arrows to " \
                                            "reorder the ones that are on.",
            )
          end
        end

        def visible = Settings.settings.get_strv(KEY).to_a

        def visible=(keys)
          Settings.settings.set_strv(KEY, keys)
          reload
        end

        # Visible filters first, in their stored order, then the hidden ones —
        # so the list reads as the sidebar does.
        def ordered
          visible.filter_map { |key| FilterFlowBox::FILTERS.find { |f| f[:key] == key } } +
            FilterFlowBox::FILTERS.reject { |filter| visible.include?(filter[:key]) }
        end

        def reload
          @rows ||= []
          @rows.each { |row| filters_group.remove(row) }
          @rows = ordered.map { |filter| filter_row(filter) }
          @rows.each { |row| filters_group.add(row) }
        end

        def filter_row(filter)
          Adwaita::ActionRow.new.tap do |row|
            row.title = filter[:title].call
            row.add_prefix(Gtk::Image.new(icon_name: filter[:icon]))
            row.add_suffix(move_button(filter, -1, "go-up-symbolic"))
            row.add_suffix(move_button(filter, 1, "go-down-symbolic"))
            row.add_suffix(visible_switch(filter))
          end
        end

        def move_button(filter, direction, icon)
          Gtk::Button.new(icon_name: icon).tap do |button|
            button.add_css_class("flat")
            button.valign = :center
            button.sensitive = visible.include?(filter[:key])
            button.signal_connect("clicked") { move(filter, direction) }
          end
        end

        # Only the visible ones have an order to move within.
        def move(filter, direction)
          visible.then do |keys|
            keys.index(filter[:key]).then do |index|
              target = index.to_i + direction

              if !index.nil? && target.between?(0, keys.size - 1)
                keys.dup.tap do |moved|
                  moved[index], moved[target] = moved[target], moved[index]
                  self.visible = moved
                end
              end
            end
          end
        end

        def visible_switch(filter)
          Gtk::Switch.new.tap do |switch|
            switch.valign = :center
            switch.active = visible.include?(filter[:key])
            switch.signal_connect("notify::active") { toggle(filter, switch.active?) }
          end
        end

        def toggle(filter, on)
          if on
            self.visible = visible + [filter[:key]]
          else
            self.visible = visible - [filter[:key]]
          end
        end
      end
    end
  end
end
