# frozen_string_literal: true

module Planify
  module Dialogs
    # src/Dialogs/QuickFind: one search field over tasks, projects and labels,
    # grouped by kind, opening whatever is picked.
    class QuickFind
      def initialize(window)
        @window = window
        @results = []
      end

      attr_reader :window

      def store = Store.instance

      def present(parent, term = nil)
        dialog.tap do |d|
          d.child = toolbar

          toolbar.tap do |view|
            view.add_top_bar(header)
            view.content = stack

            header.title_widget = search_entry

            stack.tap do |s|
              s.add_named(scrolled, "results")
              s.add_named(empty_page, "empty")
              s.visible_child_name = "empty"
            end

            scrolled.child = listbox

            search_entry.signal_connect("search-changed") { search }

            listbox.signal_connect("row-activated") do |_, row|
              open(@results[row.index])
              d.close
            end
          end

          d.present(parent)
          unless term.to_s.empty?
            search_entry.text = term.to_s
          end
          search_entry.grab_focus
        end
      end

      def search
        search_entry.text.strip.then do |term|
          if term.empty?
            @results = []
            stack.visible_child_name = "empty"
          else
            @results = flatten(store.search(term))
            rebuild
          end
        end
      end

      def flatten(found)
        found[:items].map { |item| [:item, item] } +
          found[:projects].map { |project| [:project, project] } +
          found[:labels].map { |label| [:label, label] }
      end

      def rebuild
        while listbox.first_child
          listbox.remove(listbox.first_child)
        end

        @results.each { |result| listbox.append(result_row(result)) }
        if @results.empty?
          stack.visible_child_name = "empty"
        else
          stack.visible_child_name = "results"
        end
        empty_page.title = _("No results")
      end

      KIND_ICONS = {
        item:    "check-round-outline-symbolic",
        project: "shoe-box-symbolic",
        label:   "tag-outline-symbolic",
      }.freeze

      KIND_TITLES = {
        item:    -> { _("Task") },
        project: -> { _("Project") },
        label:   -> { _("Label") },
      }.freeze

      def result_row((kind, record))
        Adwaita::ActionRow.new.tap do |row|
          if kind == :item
            row.title = record.content.to_s
          else
            row.title = record.name.to_s
          end
          row.subtitle = KIND_TITLES.fetch(kind).call
          row.activatable = true
          row.add_prefix(Gtk::Image.new(icon_name: KIND_ICONS.fetch(kind)))
        end
      end

      def open((kind, record))
        case kind
        when :item then window.show_item(record)
        when :project then window.show_project(record)
        when :label then window.show_label(record)
        end
      end

      def dialog
        @dialog ||= Adwaita::Dialog.new.tap do |d|
          d.content_width = 520
          d.content_height = 480
          d.title = _("Quick Find")
        end
      end

      def toolbar = @toolbar ||= Adwaita::ToolbarView.new

      def header
        @header ||= Adwaita::HeaderBar.new.tap do |h|
          h.show_title = true
        end
      end

      def search_entry
        @search_entry ||= Gtk::SearchEntry.new.tap do |entry|
          entry.placeholder_text = _("Quick Find")
          entry.width_request = 320
        end
      end

      def stack = @stack ||= Gtk::Stack.new

      def scrolled
        @scrolled ||= Gtk::ScrolledWindow.new.tap do |scroll|
          scroll.hscrollbar_policy = :never
          scroll.vexpand = true
        end
      end

      def listbox
        @listbox ||= Gtk::ListBox.new.tap do |list|
          list.selection_mode = :none
          list.add_css_class("boxed-list")
          list.margin_start = 12
          list.margin_end = 12
          list.margin_top = 12
          list.margin_bottom = 12
        end
      end

      def empty_page
        @empty_page ||= Adwaita::StatusPage.new.tap do |page|
          page.icon_name = "edit-find-symbolic"
          page.title = _("Search Planify")
          page.description = _("Find tasks, projects and labels.")
        end
      end
    end
  end
end
