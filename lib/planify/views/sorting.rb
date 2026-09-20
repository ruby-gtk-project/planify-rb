# frozen_string_literal: true

module Planify
  module Views
    # The sort and group options every task view offers, and the filter chips
    # that narrow one. Upstream repeats this menu in Today, Scheduled, Filter
    # and Project; here it is one module they all mix in.
    module Sorting
      SORTS = [
        ["manual", -> { _("Custom Order") }, ->(item) { item.child_order.to_i }],
        ["name", -> { _("Alphabetically") }, ->(item) { item.content.to_s.downcase }],
        ["due", -> { _("Due Date") }, ->(item) { item.due_date.to_i }],
        ["added", -> { _("Date Added") }, ->(item) { item.added_at.to_s }],
        ["updated", -> { _("Date Modified") }, ->(item) { item.updated_at.to_s }],
        ["priority", -> { _("Priority") }, ->(item) { -item.priority.to_i }],
      ].freeze

      GROUPS = [
        ["none", -> { _("No Grouping") }],
        ["project", -> { _("Project") }],
        ["priority", -> { _("Priority") }],
        ["due", -> { _("Due Date") }],
        ["label", -> { _("Label") }],
      ].freeze

      def sort_key = "#{settings_prefix}-sort-order"

      def ascending_key = "#{settings_prefix}-sort-ascending"

      # Each view remembers its own order where the schema has a key for it;
      # a view without one keeps the choice for the session only.
      def settings_prefix = "all-items"

      def session = @session ||= {}

      def sort_mode
        if Settings.key?(sort_key)
          Settings.get_string(sort_key)
        else
          session.fetch(:sort, SORTS.first.first)
        end
      end

      def sort_mode=(index)
        SORTS[index.to_i]&.first.to_s.then do |key|
          if Settings.key?(sort_key)
            Settings.set_string(sort_key, key)
          else
            session[:sort] = key
          end
        end
      end

      def ascending?
        if Settings.key?(ascending_key)
          Settings.get_boolean(ascending_key)
        else
          session.fetch(:ascending, true)
        end
      end

      def ascending=(value)
        if Settings.key?(ascending_key)
          Settings.set_boolean(ascending_key, value)
        else
          session[:ascending] = value
        end
      end

      # An unrecognised stored value — an older build's, or "project", which
      # is a grouping rather than a sort — leaves the order as the store gave
      # it rather than raising.
      def apply_sort(items)
        SORTS.find { |(key, _, _)| key == sort_mode }.then do |(_, _, extractor)|
          if extractor.nil?
            items
          else
            items.sort_by { |item| extractor.call(item) }.then do |sorted|
              ascending? ? sorted : sorted.reverse
            end
          end
        end
      end

      # Grouping returns [heading, items] pairs; "none" is one unnamed group,
      # so every view can render the same shape.
      def apply_grouping(items, mode = group_mode)
        case mode
        when "project"  then group_by(items) { |item| item.project&.name.to_s }
        when "priority" then group_by(items, &:priority_text)
        when "due"      then group_by(items) { |item| Datetime.date_word(item.due_date) }
        when "label"    then group_by_label(items)
        else [[nil, items]]
        end
      end

      def group_mode = @group_mode ||= "none"

      def group_mode=(value)
        @group_mode = value
      end

      def group_by(items, &key)
        items.group_by(&key).map { |heading, group| [heading.to_s, group] }
             .sort_by { |(heading, _)| heading }
      end

      # A task with several labels appears under each of them, and one with
      # none gets its own group rather than vanishing.
      def group_by_label(items)
        Hash.new { |hash, key| hash[key] = [] }.tap do |groups|
          items.each do |item|
            if item.label_objects.empty?
              groups[_("No Label")] << item
            else
              item.label_objects.each { |label| groups[label.name.to_s] << item }
            end
          end
        end.sort_by { |(heading, _)| heading }
      end

      # --- the shared view menu --------------------------------------------

      def sort_menu_model
        Gio::Menu.new.tap do |menu|
          Gio::Menu.new.tap do |section|
            SORTS.each_with_index do |(_, title, _), index|
              section.append(title.call, "view.sort(#{index})")
            end
            menu.append_section(_("Sort By"), section)
          end

          Gio::Menu.new.tap do |section|
            GROUPS.each_with_index do |(_, title), index|
              section.append(title.call, "view.group(#{index})")
            end
            menu.append_section(_("Group By"), section)
          end

          Gio::Menu.new.tap do |section|
            section.append(_("Reverse Order"), "view.reverse")
            section.append(_("Show Completed Tasks"), "view.show-completed")
            menu.append_section(nil, section)
          end
        end
      end

      def register_sort_actions(widget)
        Gio::SimpleActionGroup.new.tap do |group|
          group.add_action(sort_action)
          group.add_action(group_action)
          group.add_action(reverse_action)
          group.add_action(show_completed_action)
          widget.insert_action_group("view", group)
        end
      end

      def sort_action
        Gio::SimpleAction.new("sort", GLib::VariantType.new("i")).tap do |action|
          action.signal_connect("activate") do |_, parameter|
            self.sort_mode = parameter.get_int32
            refresh
          end
        end
      end

      def group_action
        Gio::SimpleAction.new("group", GLib::VariantType.new("i")).tap do |action|
          action.signal_connect("activate") do |_, parameter|
            self.group_mode = GROUPS[parameter.get_int32][0]
            refresh
          end
        end
      end

      def reverse_action
        Gio::SimpleAction.new("reverse").tap do |action|
          action.signal_connect("activate") do
            self.ascending = !ascending?
            refresh
          end
        end
      end

      def show_completed_action
        Gio::SimpleAction.new("show-completed").tap do |action|
          action.signal_connect("activate") { toggle_completed }
        end
      end

      # Only the project view has a per-project setting for this; elsewhere it
      # is a per-view flag that lives for the session.
      def toggle_completed
        @show_completed = !show_completed?
        refresh
      end

      def show_completed? = @show_completed == true
    end
  end
end
