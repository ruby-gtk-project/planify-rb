# frozen_string_literal: true

module Planify
  module Views
    # src/Views/Filter.vala plus Today, Scheduled, Pinboard and the label
    # filter — one view class, because upstream's separate view classes differ
    # only in which items they select and what they are called.
    class FilterView < BaseView
      FILTERS = {
        "inbox"      => {
          title:       -> { _("Inbox") },
          icon:        "mailbox-symbolic",
          items:       ->(store) { store.inbox_project.then { |p| p.nil? ? [] : store.items_by_project(p.id).reject { |i| i.checked? || !i.parent_id.to_s.empty? } } },
          empty:       -> { _("Your inbox is empty") },
          description: -> { _("Add a task here and file it away later.") },
        },
        "today"      => {
          title:       -> { _("Today") },
          icon:        "star-outline-thick-symbolic",
          items:       ->(store) { store.today_items },
          empty:       -> { _("Nothing due today") },
          description: -> { _("Enjoy the rest of your day.") },
        },
        "scheduled"  => {
          title:       -> { _("Scheduled") },
          icon:        "month-symbolic",
          items:       ->(store) { store.scheduled_items },
          empty:       -> { _("Nothing scheduled") },
          description: -> { _("Tasks with a future due date show up here.") },
        },
        "pinboard"   => {
          title:       -> { _("Pinboard") },
          icon:        "pin-symbolic",
          items:       ->(store) { store.pinboard_items },
          empty:       -> { _("No pinned tasks") },
          description: -> { _("Pin a task to keep it close at hand.") },
        },
        "completed"  => {
          title:       -> { _("Completed") },
          icon:        "check-round-outline-symbolic",
          items:       ->(store) { store.completed_items },
          empty:       -> { _("Nothing completed yet") },
          description: -> { _("Completed tasks are collected here.") },
        },
        "anytime"    => {
          title:       -> { _("Anytime") },
          icon:        "grid-large-symbolic",
          items:       ->(store) { store.anytime_items },
          empty:       -> { _("No undated tasks") },
          description: -> { _("Tasks without a due date show up here.") },
        },
        "repeating"  => {
          title:       -> { _("Repeating") },
          icon:        "arrow-circular-top-right-symbolic",
          items:       ->(store) { store.repeating_items },
          empty:       -> { _("No repeating tasks") },
          description: -> { _("Tasks that repeat on a schedule show up here.") },
        },
        "unlabeled"  => {
          title:       -> { _("Unlabeled") },
          icon:        "tag-outline-remove-symbolic",
          items:       ->(store) { store.unlabeled_items },
          empty:       -> { _("Everything is labeled") },
          description: -> { _("Tasks without a label show up here.") },
        },
        "tomorrow"   => {
          title:       -> { _("Tomorrow") },
          icon:        "month-symbolic",
          items:       ->(store) { store.tomorrow_items },
          empty:       -> { _("Nothing due tomorrow") },
          description: -> { _("Tasks due tomorrow show up here.") },
        },
        "all"        => {
          title:       -> { _("All Tasks") },
          icon:        "list-symbolic",
          items:       ->(store) { store.all_items },
          empty:       -> { _("Nothing to do") },
          description: -> { _("Every task that is not yet done shows up here.") },
        },
        "priority-1" => {
          title:       -> { _("Priority 1") },
          icon:        "flag-outline-thick-symbolic",
          items:       ->(store) { store.priority_items(Item::PRIORITY_1) },
          empty:       -> { _("Nothing is Priority 1") },
          description: -> { _("Your highest-priority tasks show up here.") },
        },
        "priority-2" => {
          title:       -> { _("Priority 2") },
          icon:        "flag-outline-thick-symbolic",
          items:       ->(store) { store.priority_items(Item::PRIORITY_2) },
          empty:       -> { _("Nothing is Priority 2") },
          description: -> { _("Your medium-priority tasks show up here.") },
        },
        "priority-3" => {
          title:       -> { _("Priority 3") },
          icon:        "flag-outline-thick-symbolic",
          items:       ->(store) { store.priority_items(Item::PRIORITY_3) },
          empty:       -> { _("Nothing is Priority 3") },
          description: -> { _("Your low-priority tasks show up here.") },
        },
        "priority-4" => {
          title:       -> { _("No Priority") },
          icon:        "flag-outline-thick-symbolic",
          items:       ->(store) { store.priority_items(Item::PRIORITY_4) },
          empty:       -> { _("Everything has a priority") },
          description: -> { _("Tasks with no priority set show up here.") },
        },
      }.freeze

      include Sorting

      def initialize(window, key, label: nil)
        super(window)
        @key = key
        @label = label
        @chips = []
      end

      # All Tasks is the one view with a saved filter set; the rest are
      # already a filter and layer chips on top for the session only.
      def settings_prefix
        if key == "all"
          "all-items"
        else
          "session"
        end
      end

      def filters_key = "all-items-filters"

      attr_reader :key, :label

      def filter = FILTERS.fetch(key, FILTERS.fetch("inbox"))

      def title
        if label.nil?
          filter[:title].call
        else
          label.name
        end
      end

      def subtitle
        items.size.then { |count| n_("%d task", "%d tasks", count) % count }
      end

      def items
        base_items.then { |found| apply_chips(found) }
      end

      def base_items
        if label.nil?
          filter[:items].call(store)
        else
          store.items_by_label(label.id)
        end
      end

      # src/Objects/Filters/FilterItem.vala: a chip is "type:value" and chips
      # intersect, so adding one always narrows.
      def chips
        if key == "all" && Settings.key?(filters_key)
          Settings.settings.get_strv(filters_key).to_a
        else
          @chips
        end
      end

      def chips=(values)
        @chips = values

        if key == "all" && Settings.key?(filters_key)
          Settings.settings.set_strv(filters_key, values)
        end
      end

      def apply_chips(found)
        chips.reduce(found) { |narrowed, chip| narrow(narrowed, chip) }
      end

      def narrow(found, chip)
        chip.split(":", 2).then do |(kind, value)|
          case kind
          when "priority" then found.select { |item| item.priority.to_s == value }
          when "label"    then found.select { |item| item.label_ids.include?(value) }
          when "due-date" then found.select { |item| matches_due?(item, value) }
          when "section"  then found.select { |item| item.section_id.to_s == value }
          else found
          end
        end
      end

      DUE_MATCHERS = {
        "today"    => ->(item) { Datetime.today?(item.due_date) },
        "tomorrow" => ->(item) { Datetime.tomorrow?(item.due_date) },
        "week"     => ->(item) { Datetime.this_week?(item.due_date) },
        "overdue"  => ->(item) { Datetime.overdue?(item.due_date) },
        "none"     => ->(item) { !item.has_due? },
      }.freeze

      def matches_due?(item, value)
        DUE_MATCHERS.fetch(value, ->(_) { true }).call(item)
      end

      def quick_add_defaults
        if key == "today"
          { project: store.inbox_project }
        else
          { project: store.inbox_project }
        end
      end

      def empty_title
        if label.nil?
          filter[:empty].call
        else
          _("No tasks with this label")
        end
      end

      def empty_description
        if label.nil?
          filter[:description].call
        else
          _("Tasks labeled “%s” show up here.") % label.name
        end
      end

      def empty_icon
        if label.nil?
          filter[:icon]
        else
          "tag-outline-symbolic"
        end
      end

      # Today is the only filter that gets the overdue header upstream; the
      # store already sorts overdue items first, so the count is enough here.
      def refresh
        super
        rebuild_chips
        overdue_banner.revealed = key == "today" && !store.overdue_items.empty?
        overdue_banner.title = n_("%d overdue task", "%d overdue tasks", store.overdue_items.size) %
                               store.overdue_items.size
      end

      def build
        @build ||= super.tap do
          toolbar.add_top_bar(overdue_banner)
          toolbar.add_top_bar(chips_bar)

          header.pack_end(sort_button)
          header.pack_end(filter_button)
          sort_button.menu_model = sort_menu_model
          register_sort_actions(toolbar)

          filter_button.popover = filter_popover
          filter_popover.child = filter_menu.build

          Services::EventBus.on(:day_changed, owner: self) { refresh }
        end
      end

      # The chips sit in a bar under the header, so removing one is a click on
      # the chip itself.
      def rebuild_chips
        while chips_box.first_child
          chips_box.remove(chips_box.first_child)
        end

        chips.each { |chip| chips_box.append(chip_button(chip)) }
        chips_bar.reveal_child = !chips.empty?
      end

      def chip_button(chip)
        Gtk::Button.new.tap do |button|
          button.add_css_class("pill")
          button.child = Adwaita::ButtonContent.new.tap do |content|
            content.icon_name = "window-close-symbolic"
            content.label = chip_title(chip)
          end
          button.signal_connect("clicked") { remove_chip(chip) }
        end
      end

      def chip_title(chip)
        chip.split(":", 2).then do |(kind, value)|
          case kind
          when "priority" then Item.new(priority: value.to_i).priority_text
          when "label"    then store.label(value)&.name.to_s
          when "due-date" then due_title(value)
          when "section"  then store.section(value)&.name.to_s
          else chip
          end
        end
      end

      DUE_TITLES = {
        "today"    => -> { _("Due today") },
        "tomorrow" => -> { _("Due tomorrow") },
        "week"     => -> { _("Due this week") },
        "overdue"  => -> { _("Overdue") },
        "none"     => -> { _("No due date") },
      }.freeze

      def due_title(value) = DUE_TITLES.fetch(value, -> { value }).call

      def add_chip(chip)
        self.chips = (chips + [chip]).uniq
        filter_popover.popdown
        refresh
      end

      def remove_chip(chip)
        self.chips = chips - [chip]
        refresh
      end

      def overdue_banner
        @overdue_banner ||= Adwaita::Banner.new("").tap do |banner|
          banner.revealed = false
        end
      end

      # Adwaita::Banner takes only a title and a button, so the chip row is a
      # Revealer of its own rather than a banner's child.
      def chips_bar
        @chips_bar ||= Gtk::Revealer.new.tap do |bar|
          bar.transition_type = :slide_down
          bar.reveal_child = false
          bar.child = chips_box
        end
      end

      def chips_box
        @chips_box ||= Gtk::Box.new(:horizontal, 6).tap do |box|
          box.margin_start = 12
          box.margin_end = 12
          box.margin_top = 6
          box.margin_bottom = 6
        end
      end

      def sort_button
        @sort_button ||= Gtk::MenuButton.new.tap do |button|
          button.icon_name = "vertical-arrows-long-symbolic"
          button.add_css_class("flat")
          button.tooltip_text = _("View Option Menu")
        end
      end

      def filter_button
        @filter_button ||= Gtk::MenuButton.new.tap do |button|
          button.icon_name = "funnel-outline-symbolic"
          button.add_css_class("flat")
          button.tooltip_text = _("Filter")
        end
      end

      def filter_popover = @filter_popover ||= Gtk::Popover.new

      # Priorities, due-date buckets and every label, as things to narrow by.
      def filter_menu
        @filter_menu ||= ContextMenu::Menu.new(width: 260).tap do |menu|
          priority_entries.each { |entry| menu.add(entry) }
          menu.add(ContextMenu::MenuSeparator.new)
          due_entries.each { |entry| menu.add(entry) }
          menu.add(ContextMenu::MenuSeparator.new)
          label_entries.each { |entry| menu.add(entry) }
        end
      end

      def priority_entries
        [Item::PRIORITY_1, Item::PRIORITY_2, Item::PRIORITY_3, Item::PRIORITY_4].map do |level|
          ContextMenu::MenuItem.new(
            Item.new(priority: level).priority_text,
            icon: "flag-outline-thick-symbolic",
          ) { add_chip("priority:#{level}") }
        end
      end

      def due_entries
        DUE_TITLES.map do |value, title|
          ContextMenu::MenuItem.new(title.call, icon: "month-symbolic") do
            add_chip("due-date:#{value}")
          end
        end
      end

      def label_entries
        store.labels.map do |record|
          ContextMenu::MenuItem.new(record.name.to_s, icon: "tag-outline-symbolic") do
            add_chip("label:#{record.id}")
          end
        end
      end
    end
  end
end
