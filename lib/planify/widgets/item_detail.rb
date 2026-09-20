# frozen_string_literal: true

module Planify
  # src/Layouts/ItemSidebarView.vala. The task detail pane: title, Markdown
  # description, every property, sub-tasks, attachments, and the change
  # history. Every edit writes straight through, so the row behind it updates
  # as you type.
  class ItemDetail
    def initialize(window)
      @window = window
      @item = nil
      @loading = false
    end

    attr_reader :window, :item
    attr_accessor :on_close

    def store = Store.instance

    def build
      @build ||= toolbar.tap do |view|
        view.add_top_bar(header)
        view.content = stack

        header.tap do |h|
          h.show_title = false
          h.pack_start(complete_button)
          h.pack_end(close_button)
          h.pack_end(menu_button)

          close_button.signal_connect("clicked") { on_close&.call }
          complete_button.signal_connect("toggled") { complete }
          menu_button.menu_model = item_menu
        end

        stack.tap do |s|
          s.add_named(empty_page, "empty")
          s.add_named(scrolled, "item")
          s.visible_child_name = "empty"
        end

        scrolled.child = content_box

        content_box.tap do |box|
          box.append(content_entry)
          box.append(markdown_editor.build)
          box.append(properties_group)
          box.append(sub_items.build)
          box.append(attachments.build)
          box.append(history_group)

          content_entry.signal_connect("changed") { save_content }
          content_entry.signal_connect("activate") { save_content }

          build_properties
        end

        register_actions
        subscribe
      end
    end

    def build_properties
      properties_group.tap do |group|
        group.add(project_row)
        group.add(due_row)
        group.add(deadline_row)
        group.add(priority_row)
        group.add(labels_row)
        group.add(reminders_row)
        group.add(pinned_row)

        wire_project_row
        wire_due_row
        wire_deadline_row
        wire_priority_row
        wire_labels_row
        wire_reminders_row

        pinned_row.signal_connect("notify::active") { save_pinned }
      end
    end

    def wire_project_row
      project_row.tap do |row|
        row.activatable_widget = project_button
        row.add_suffix(project_button)
        project_button.popover = project_popover
        project_popover.child = project_picker.build
      end
    end

    def wire_due_row
      due_row.tap do |row|
        row.activatable_widget = due_button
        row.add_suffix(due_button)
        due_button.popover = due_popover
        due_popover.child = date_picker.build
      end
    end

    def wire_deadline_row
      deadline_row.tap do |row|
        row.activatable_widget = deadline_button
        row.add_suffix(deadline_button)
        deadline_button.popover = deadline_popover
        deadline_popover.child = deadline_picker.build
      end
    end

    def wire_priority_row
      priority_row.tap do |row|
        row.model = Gtk::StringList.new(priority_titles)
        row.signal_connect("notify::selected") { save_priority }
      end
    end

    def wire_labels_row
      labels_row.tap do |row|
        row.activatable_widget = labels_button
        row.add_suffix(labels_button)
        labels_button.popover = labels_popover
        labels_popover.child = label_picker.build
      end
    end

    def wire_reminders_row
      reminders_row.tap do |row|
        row.activatable_widget = reminders_button
        row.add_suffix(reminders_button)
        reminders_button.popover = reminders_popover
        reminders_popover.child = reminder_picker.build
      end
    end

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

      %i[item_added item_deleted].each do |event|
        store.on(event, owner: self) do
          unless item.nil?
            sub_items.refresh
          end
        end
      end
    end

    def item=(value)
      load(value)
    end

    # Loading sets every widget from the item; the flag stops the change
    # handlers those setters fire from writing straight back. The ensure is
    # what keeps a raised setter from wedging the pane read-only.
    def load(value)
      @item = value
      @loading = true

      begin
        stack.visible_child_name = "item"
        content_entry.text = value.content.to_s
        markdown_editor.text = value.description.to_s
        complete_button.active = value.checked?
        priority_row.selected = priority_index(value.priority.to_i)
        pinned_row.active = value.pinned?
        date_picker.datetime = value.due_date
        date_picker.due = value.due_hash
        deadline_picker.datetime = value.deadline
        label_picker.selected = value.label_ids
        project_picker.select(value.project, value.section)
        reminder_picker.item = value
        sub_items.item = value
        attachments.item = value
        refresh_buttons
        refresh_history
      ensure
        @loading = false
      end
    end

    def clear
      @item = nil
      stack.visible_child_name = "empty"
    end

    def refresh_buttons
      project_button.label = project_summary
      project_row.subtitle = project_summary
      if item.has_due?
        due_button.label = Datetime.relative(item.due_date)
      else
        due_button.label = _("Schedule")
      end
      if item.recurring?
        due_row.subtitle = date_picker.repeat_summary
      else
        due_row.subtitle = ""
      end
      if item.deadline.nil?
        deadline_button.label = _("Add")
      else
        deadline_button.label = Datetime.relative(item.deadline)
      end
      labels_button.label = labels_summary
      reminders_button.label = reminders_summary
    end

    def project_summary
      [item.project&.name, item.section&.name].compact.reject(&:empty?).join(" / ")
        .then { |text| text.empty? ? _("Inbox") : text }
    end

    def labels_summary
      item.label_objects.then do |labels|
        labels.empty? ? _("Add") : labels.map(&:name).join(", ")
      end
    end

    def reminders_summary
      store.reminders_by_item(item.id).then do |reminders|
        reminders.empty? ? _("None") : n_("%d reminder", "%d reminders", reminders.size) % reminders.size
      end
    end

    # The history is recorded by database triggers, so it is read back rather
    # than tracked in memory.
    def refresh_history
      @history_rows ||= []
      @history_rows.each { |row| history_group.remove(row) }

      store.events_for_item(item.id).first(20).then do |events|
        @history_rows = events.map { |event| ItemChangeHistoryRow.new(event).build }
        @history_rows.each { |row| history_group.add(row) }
        history_group.visible = !events.empty?
      end
    end

    PRIORITIES = [Item::PRIORITY_1, Item::PRIORITY_2, Item::PRIORITY_3, Item::PRIORITY_4].freeze

    def priority_titles = PRIORITIES.map { |level| Item.new(priority: level).priority_text }

    def priority_index(priority) = PRIORITIES.index(priority) || 3

    # --- writes ---------------------------------------------------------

    def editing? = @loading || item.nil?

    def save_content
      unless editing?
        item.content = content_entry.text
        store.update_item(item)
      end
    end

    def save_description(text)
      unless editing?
        item.description = text
        store.update_item(item)
      end
    end

    def save_priority
      unless editing?
        item.priority = PRIORITIES[priority_row.selected]
        store.update_item(item)
      end
    end

    def save_pinned
      unless editing?
        item.pinned = Record.flag(pinned_row.active?)
        store.update_item(item)
      end
    end

    def save_due(time, due)
      unless editing?
        item.due_date = time

        unless time.nil?
          item.due = JSON.generate(item.due_hash.merge(due))
        end

        store.update_item(item)
        due_popover.popdown
      end
    end

    def save_deadline(time, _due)
      unless editing?
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
      unless editing?
        item.label_ids = ids
        store.update_item(item)
      end
    end

    def save_project(project, section)
      unless editing?
        item.project_id = project.id
        item.section_id = section&.id.to_s
        item.child_order = store.next_child_order(item.project_id, item.section_id)
        store.update_item(item)
        project_popover.popdown
      end
    end

    def complete
      unless editing?
        store.complete_item(item, complete_button.active?)
        if complete_button.active?
          Services::Notification.play_complete_tone
        end
      end
    end

    # --- actions --------------------------------------------------------

    DETAIL_ACTIONS = {
      "duplicate" => :duplicate,
      "copy-link" => :copy_link,
      "export"    => :export_task,
      "delete"    => :delete_item,
    }.freeze

    def register_actions
      Gio::SimpleActionGroup.new.tap do |group|
        DETAIL_ACTIONS.each do |name, method|
          Gio::SimpleAction.new(name).tap do |action|
            action.signal_connect("activate") { public_send(method) }
            group.add_action(action)
          end
        end

        toolbar.insert_action_group("detail", group)
      end
    end

    def item_menu
      @item_menu ||= Gio::Menu.new.tap do |menu|
        Gio::Menu.new.tap do |section|
          section.append(_("Duplicate"), "detail.duplicate")
          section.append(_("Copy Link"), "detail.copy-link")
          section.append(_("Copy as Text"), "detail.export")
          menu.append_section(nil, section)
        end

        Gio::Menu.new.tap do |section|
          section.append(_("Delete Task"), "detail.delete")
          menu.append_section(nil, section)
        end
      end
    end

    def duplicate
      unless item.nil?
        store.insert_item(
          Item.new(**item.to_row.except(:id)).tap do |copy|
            copy.content = _("%s (copy)") % item.content
            copy.child_order = store.next_child_order(item.project_id, item.section_id)
          end,
        )
      end
    end

    # The app's own URI scheme, which the DBus handler resolves back to a task.
    def copy_link
      unless item.nil?
        Gdk::Display.default.clipboard.set("planify://task/#{item.id}")
        window.toast(_("Link copied"))
      end
    end

    def export_task
      unless item.nil?
        Gdk::Display.default.clipboard.set(as_text)
        window.toast(_("Task copied"))
      end
    end

    def as_text
      ["- [#{item.checked? ? 'x' : ' '}] #{item.content}"].tap do |lines|
        unless item.description.to_s.strip.empty?
          lines << item.description.to_s
        end
        if item.has_due?
          lines << _("Due: %s") % Datetime.relative(item.due_date)
        end
      end.join("\n")
    end

    def delete_item
      unless item.nil?
        item.then do |doomed|
          store.trash_item(doomed)
          window.toast_with_undo(_("Task deleted")) { store.restore_item(doomed) }
        end
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

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.icon_name = "view-more-symbolic"
        button.add_css_class("flat")
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

    def markdown_editor
      @markdown_editor ||= MarkdownEditor.new { |text| save_description(text) }
    end

    def properties_group
      @properties_group ||= Adwaita::PreferencesGroup.new.tap do |group|
        group.title = _("Details")
      end
    end

    def project_row
      @project_row ||= Adwaita::ActionRow.new.tap { |row| row.title = _("Project") }
    end

    def project_button
      @project_button ||= Gtk::MenuButton.new.tap do |button|
        button.add_css_class("flat")
        button.valign = :center
      end
    end

    def project_popover = @project_popover ||= Gtk::Popover.new

    def project_picker
      @project_picker ||= ProjectPicker.new { |project, section| save_project(project, section) }
    end

    def due_row
      @due_row ||= Adwaita::ActionRow.new.tap { |row| row.title = _("Schedule") }
    end

    def due_button
      @due_button ||= Gtk::MenuButton.new.tap do |button|
        button.add_css_class("flat")
        button.valign = :center
      end
    end

    def due_popover = @due_popover ||= Gtk::Popover.new

    def date_picker
      @date_picker ||= DateTimePicker.new { |time, due| save_due(time, due) }
    end

    def deadline_row
      @deadline_row ||= Adwaita::ActionRow.new.tap { |row| row.title = _("Deadline") }
    end

    def deadline_button
      @deadline_button ||= Gtk::MenuButton.new.tap do |button|
        button.add_css_class("flat")
        button.valign = :center
      end
    end

    def deadline_popover = @deadline_popover ||= Gtk::Popover.new

    def deadline_picker
      @deadline_picker ||= DateTimePicker.new { |time, due| save_deadline(time, due) }
    end

    def priority_row
      @priority_row ||= Adwaita::ComboRow.new.tap { |row| row.title = _("Priority") }
    end

    def labels_row
      @labels_row ||= Adwaita::ActionRow.new.tap { |row| row.title = _("Labels") }
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
      @reminders_row ||= Adwaita::ActionRow.new.tap { |row| row.title = _("Reminders") }
    end

    def reminders_button
      @reminders_button ||= Gtk::MenuButton.new.tap do |button|
        button.add_css_class("flat")
        button.valign = :center
      end
    end

    def reminders_popover = @reminders_popover ||= Gtk::Popover.new

    def reminder_picker = @reminder_picker ||= ReminderPicker.new

    def pinned_row
      @pinned_row ||= Adwaita::SwitchRow.new.tap { |row| row.title = _("Pinned") }
    end

    def sub_items = @sub_items ||= SubItems.new(window)

    def attachments = @attachments ||= Attachments.new(nil, window)

    def history_group
      @history_group ||= Adwaita::PreferencesGroup.new.tap do |group|
        group.title = _("Activity")
        group.visible = false
      end
    end
  end
end
