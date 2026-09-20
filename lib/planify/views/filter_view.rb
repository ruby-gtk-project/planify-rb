# frozen_string_literal: true

module Planify
  module Views
    # src/Views/Filter.vala plus Today, Scheduled, Pinboard and the label
    # filter — one view class, because upstream's separate view classes differ
    # only in which items they select and what they are called.
    class FilterView < BaseView
      FILTERS = {
        "inbox"     => {
          title:       -> { _("Inbox") },
          icon:        "mailbox-symbolic",
          items:       ->(store) { store.inbox_project.then { |p| p.nil? ? [] : store.items_by_project(p.id).reject { |i| i.checked? || !i.parent_id.to_s.empty? } } },
          empty:       -> { _("Your inbox is empty") },
          description: -> { _("Add a task here and file it away later.") },
        },
        "today"     => {
          title:       -> { _("Today") },
          icon:        "star-outline-thick-symbolic",
          items:       ->(store) { store.today_items },
          empty:       -> { _("Nothing due today") },
          description: -> { _("Enjoy the rest of your day.") },
        },
        "scheduled" => {
          title:       -> { _("Scheduled") },
          icon:        "month-symbolic",
          items:       ->(store) { store.scheduled_items },
          empty:       -> { _("Nothing scheduled") },
          description: -> { _("Tasks with a future due date show up here.") },
        },
        "pinboard"  => {
          title:       -> { _("Pinboard") },
          icon:        "pin-symbolic",
          items:       ->(store) { store.pinboard_items },
          empty:       -> { _("No pinned tasks") },
          description: -> { _("Pin a task to keep it close at hand.") },
        },
        "completed" => {
          title:       -> { _("Completed") },
          icon:        "check-round-outline-symbolic",
          items:       ->(store) { store.completed_items },
          empty:       -> { _("Nothing completed yet") },
          description: -> { _("Completed tasks are collected here.") },
        },
        "anytime"   => {
          title:       -> { _("Anytime") },
          icon:        "grid-large-symbolic",
          items:       ->(store) { store.anytime_items },
          empty:       -> { _("No undated tasks") },
          description: -> { _("Tasks without a due date show up here.") },
        },
        "repeating" => {
          title:       -> { _("Repeating") },
          icon:        "arrow-circular-top-right-symbolic",
          items:       ->(store) { store.repeating_items },
          empty:       -> { _("No repeating tasks") },
          description: -> { _("Tasks that repeat on a schedule show up here.") },
        },
        "unlabeled" => {
          title:       -> { _("Unlabeled") },
          icon:        "tag-outline-remove-symbolic",
          items:       ->(store) { store.unlabeled_items },
          empty:       -> { _("Everything is labeled") },
          description: -> { _("Tasks without a label show up here.") },
        },
        "tomorrow"  => {
          title:       -> { _("Tomorrow") },
          icon:        "month-symbolic",
          items:       ->(store) { store.tomorrow_items },
          empty:       -> { _("Nothing due tomorrow") },
          description: -> { _("Tasks due tomorrow show up here.") },
        },
      }.freeze

      def initialize(window, key, label: nil)
        super(window)
        @key = key
        @label = label
      end

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
        if label.nil?
          filter[:items].call(store)
        else
          store.items_by_label(label.id)
        end
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
        overdue_banner.revealed = key == "today" && !store.overdue_items.empty?
        overdue_banner.title = n_("%d overdue task", "%d overdue tasks", store.overdue_items.size) %
                               store.overdue_items.size
      end

      def build
        @build ||= super.tap do
          toolbar.add_top_bar(overdue_banner)
        end
      end

      def overdue_banner
        @overdue_banner ||= Adwaita::Banner.new("").tap do |banner|
          banner.revealed = false
        end
      end
    end
  end
end
