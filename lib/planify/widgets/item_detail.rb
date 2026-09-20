# frozen_string_literal: true

module Planify
  # Layouts/ItemSidebarView.vala: the task detail pane on the end edge of the
  # window. Every edit writes straight through to the store, so the row in the
  # list behind it updates as you type.
  class ItemDetail
    def initialize(window)
      @window = window
      @item = nil
      @loading = false
    end

    attr_reader :window, :item
    attr_accessor :on_close

    def build
      @build ||= toolbar.tap do |view|
        view.add_top_bar(header)
        view.content = stack

        header.tap do |h|
          h.show_title = false
          h.pack_end(close_button)
          h.pack_start(complete_button)

          close_button.signal_connect("clicked") { on_close&.call }
          complete_button.signal_connect("toggled") { complete }
        end

        stack.tap do |s|
          s.add_named(empty_page, "empty")
          s.add_named(scrolled, "item")
          s.visible_child_name = "empty"
        end

        scrolled.child = content_box

        content_box.tap do |box|
          box.append(content_entry)
          box.append(description_view_frame)
          box.append(properties_group)

          content_entry.signal_connect("changed") { save_content }

          description_buffer.signal_connect("changed") { save_description }

          properties_group.tap do |group|
            group.add(project_row)
            group.add(due_row)
            group.add(deadline_row)
            group.add(priority_row)
            group.add(labels_row)
            group.add(reminders_row)
            group.add(pinned_row)

            due_row.tap do |row|
              row.activatable_widget = due_button
              row.add_suffix(due_button)
              due_button.popover = due_popover
              due_popover.child = date_picker.build
            end

            deadline_row.tap do |row|
              row.activatable_widget = deadline_button
              row.add_suffix(deadline_button)
              deadline_button.popover = deadline_popover
              deadline_popover.child = deadline_picker.build
            end

            priority_row.tap do |row|
              row.model = Gtk::StringList.new(priority_titles)
              row.signal_connect("notify::selected") { save_priority }
            end

            labels_row.tap do |row|
              row.activatable_widget = labels_button
              row.add_suffix(labels_button)
              labels_button.popover = labels_popover
              labels_popover.child = label_picker.build
            end

            pinned_row.signal_connect("notify::active") { save_pinned }
          end
        end

        subscribe
      end
    end

    def store = Store.instance

    def subscribe
      store.on(:item_updated, owner: self) do |updated|
        if !item.nil? && updated.id == item.id
          load(updated)
        end
      end

      store.on(:item_deleted, owner: self) do |deleted|
        if !item.nil? && deleted.id == item.id
          clear
        end
      end
    end

    def item=(value)
      load(value)
    end

    # Loading sets every widget from the item; the flag stops the change
    # handlers those setters fire from writing straight back.
    def load(value)
      @item = value
      @loading = true

      stack.visible_child_name = "item"
      content_entry.text = value.content.to_s
      description_buffer.text = value.description.to_s
      complete_button.active = value.checked?
      priority_row.selected = priority_index(value.priority.to_i)
      pinned_row.active = value.pinned?
      project_row.subtitle = project_subtitle
      begin
        date_picker.datetime = value.due_date
        date_picker.repeat = value.due_hash["recurrency_type"].to_s
        deadline_picker.datetime = value.deadline
        label_picker.selected = value.label_ids
        refresh_buttons
      ensure
        @loading = false
      end
    end

    def clear
      @item = nil
      stack.visible_child_name = "empty"
    end

    def project_subtitle
      [item.project&.name, item.section&.name].compact.join(" / ")
    end

    def refresh_buttons
      if item.has_due?
        due_button.label = Datetime.relative(item.due_date)
      else
        due_button.label = _("Schedule")
      end
      if item.deadline.nil?
        deadline_button.label = _("Add")
      else
        deadline_button.label = Datetime.relative(item.deadline)
      end
      labels_button.label = labels_summary
      reminders_row.subtitle = reminders_summary
    end

    def labels_summary
      item.label_objects.then do |labels|
        labels.empty? ? _("Add") : labels.map(&:name).join(", ")
      end
    end

    def reminders_summary
      store.reminders_by_item(item.id).then do |reminders|
        reminders.empty? ? _("None") : reminders.map { |r| Datetime.relative(r.due_date) }.join(", ")
      end
    end

    PRIORITIES = [Item::PRIORITY_1, Item::PRIORITY_2, Item::PRIORITY_3, Item::PRIORITY_4].freeze

    def priority_titles = PRIORITIES.map { |level| Item.new(priority: level).priority_text }

    def priority_index(priority) = PRIORITIES.index(priority) || 3

    # --- writes ---------------------------------------------------------

    def save_content
      unless @loading || item.nil?
        item.content = content_entry.text
        store.update_item(item)
      end
    end

    def save_description
      unless @loading || item.nil?
        item.description = description_buffer.text
        store.update_item(item)
      end
    end

    def save_priority
      unless @loading || item.nil?
        item.priority = PRIORITIES[priority_row.selected]
        store.update_item(item)
      end
    end

    def save_pinned
      unless @loading || item.nil?
        if pinned_row.active?
          item.pinned = 1
        else
          item.pinned = 0
        end
        store.update_item(item)
      end
    end

    def save_due(time, repeat)
      unless @loading || item.nil?
        item.due_date = time

        unless time.nil?
          item.due = JSON.generate(
            item.due_hash.merge(
              "recurrency_type" => repeat,
              "is_recurring"    => repeat != "none",
            ),
          )
        end

        store.update_item(item)
        due_popover.popdown
      end
    end

    def save_deadline(time, _repeat)
      unless @loading || item.nil?
        if time.nil?
          item.deadline_date = ""
        else
          item.deadline_date = Datetime.format(time)
        end
        store.update_item(item)
        deadline_popover.popdown
      end
    end

    def save_labels(ids)
      unless @loading || item.nil?
        item.label_ids = ids
        store.update_item(item)
      end
    end

    def complete
      unless @loading || item.nil?
        store.complete_item(item, complete_button.active?)
      end
    end

    # --- widgets --------------------------------------------------------

    def toolbar = @toolbar ||= Adwaita::ToolbarView.new

    def header
      @header ||= Adwaita::HeaderBar.new.tap do |h|
        h.add_css_class("flat")
      end
    end

    def close_button
      @close_button ||= Gtk::Button.new(icon_name: "go-next-symbolic").tap do |button|
        button.add_css_class("flat")
        button.tooltip_text = _("Close Details")
      end
    end

    def complete_button
      @complete_button ||= Gtk::ToggleButton.new.tap do |button|
        button.icon_name = "check-round-outline-symbolic"
        button.add_css_class("flat")
        button.tooltip_text = _("Complete")
      end
    end

    def stack = @stack ||= Gtk::Stack.new

    def empty_page
      @empty_page ||= Adwaita::StatusPage.new.tap do |page|
        page.icon_name = "check-round-outline-symbolic"
        page.title = _("No Task Selected")
        page.description = _("Select a task to see its details here.")
      end
    end

    def scrolled
      @scrolled ||= Gtk::ScrolledWindow.new.tap do |scroll|
        scroll.hscrollbar_policy = :never
        scroll.vexpand = true
      end
    end

    def content_box
      @content_box ||= Gtk::Box.new(:vertical, 12).tap do |box|
        box.margin_start = 12
        box.margin_end = 12
        box.margin_top = 12
        box.margin_bottom = 12
      end
    end

    def content_entry
      @content_entry ||= Gtk::Entry.new.tap do |entry|
        entry.placeholder_text = _("To-do name")
        entry.add_css_class("title-3")
      end
    end

    def description_view_frame
      @description_view_frame ||= Gtk::Frame.new.tap do |frame|
        frame.child = description_view
        frame.height_request = 120
      end
    end

    def description_view
      @description_view ||= Gtk::TextView.new(description_buffer).tap do |view|
        view.wrap_mode = :word_char
        view.top_margin = 6
        view.bottom_margin = 6
        view.left_margin = 6
        view.right_margin = 6
      end
    end

    def description_buffer = @description_buffer ||= Gtk::TextBuffer.new

    def properties_group
      @properties_group ||= Adwaita::PreferencesGroup.new.tap do |group|
        group.title = _("Details")
      end
    end

    def project_row
      @project_row ||= Adwaita::ActionRow.new.tap do |row|
        row.title = _("Project")
      end
    end

    def due_row
      @due_row ||= Adwaita::ActionRow.new.tap do |row|
        row.title = _("Schedule")
      end
    end

    def due_button
      @due_button ||= Gtk::MenuButton.new.tap do |button|
        button.add_css_class("flat")
        button.valign = :center
      end
    end

    def due_popover = @due_popover ||= Gtk::Popover.new

    def date_picker
      @date_picker ||= DateTimePicker.new { |time, repeat| save_due(time, repeat) }
    end

    def deadline_row
      @deadline_row ||= Adwaita::ActionRow.new.tap do |row|
        row.title = _("Deadline")
      end
    end

    def deadline_button
      @deadline_button ||= Gtk::MenuButton.new.tap do |button|
        button.add_css_class("flat")
        button.valign = :center
      end
    end

    def deadline_popover = @deadline_popover ||= Gtk::Popover.new

    def deadline_picker
      @deadline_picker ||= DateTimePicker.new { |time, repeat| save_deadline(time, repeat) }
    end

    def priority_row
      @priority_row ||= Adwaita::ComboRow.new.tap do |row|
        row.title = _("Priority")
      end
    end

    def labels_row
      @labels_row ||= Adwaita::ActionRow.new.tap do |row|
        row.title = _("Labels")
      end
    end

    def labels_button
      @labels_button ||= Gtk::MenuButton.new.tap do |button|
        button.add_css_class("flat")
        button.valign = :center
      end
    end

    def labels_popover = @labels_popover ||= Gtk::Popover.new

    def label_picker
      @label_picker ||= LabelPicker.new { |ids| save_labels(ids) }
    end

    def reminders_row
      @reminders_row ||= Adwaita::ActionRow.new.tap do |row|
        row.title = _("Reminders")
      end
    end

    def pinned_row
      @pinned_row ||= Adwaita::SwitchRow.new.tap do |row|
        row.title = _("Pinned")
      end
    end
  end
end
