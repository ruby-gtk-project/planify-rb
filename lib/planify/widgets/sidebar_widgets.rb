# frozen_string_literal: true

module Planify
  # src/Widgets/SyncButton.vala. A spinner while a sync runs, an error badge
  # when one failed, and the last sync time in its tooltip.
  class SyncButton
    def initialize(window)
      @window = window
    end

    attr_reader :window

    def store = Store.instance

    def build
      @build ||= button.tap do |b|
        b.child = stack

        stack.tap do |s|
          s.add_named(icon, "idle")
          s.add_named(spinner, "syncing")
          s.add_named(error_icon, "error")
          s.visible_child_name = "idle"
        end

        b.signal_connect("clicked") { window.sync }

        store.on(:sync_started, owner: self) { syncing }
        store.on(:sync_finished, owner: self) { |source| finished(source) }
        store.on(:sync_failed, owner: self) { |_, message| failed(message) }

        refresh
      end
    end

    def syncing
      stack.visible_child_name = "syncing"
      spinner.start
      button.tooltip_text = _("Syncing…")
    end

    def finished(source)
      spinner.stop
      stack.visible_child_name = "idle"
      button.tooltip_text = _("Last synced: %s") % Datetime.relative(Datetime.parse(source.last_sync))
    end

    def failed(message)
      spinner.stop
      stack.visible_child_name = "error"
      button.tooltip_text = message.to_s
    end

    # The button only earns its place once an account exists to sync.
    def refresh
      button.visible = !store.synced_sources.empty?
      button.tooltip_text = _("Sync")
    end

    def button
      @button ||= Gtk::Button.new.tap do |b|
        b.add_css_class("flat")
        b.tooltip_text = _("Sync")
      end
    end

    def stack = @stack ||= Gtk::Stack.new

    def icon = @icon ||= Gtk::Image.new(icon_name: "update-symbolic")

    def spinner = @spinner ||= Gtk::Spinner.new

    def error_icon
      @error_icon ||= Gtk::Image.new(icon_name: "dialog-warning-symbolic").tap do |image|
        image.add_css_class("error")
      end
    end
  end

  # src/Layouts/SidebarSourceRow.vala. One account's header in the sidebar,
  # with its projects under it and a disclosure that collapses the group.
  class SidebarSourceRow
    def initialize(window, source)
      @window = window
      @source = source
      @project_rows = {}
    end

    attr_reader :window, :source, :project_rows

    def store = Store.instance

    def build
      @build ||= box.tap do |b|
        b.append(header)
        b.append(revealer)

        header.tap do |h|
          h.append(collapse_button)
          h.append(icon)
          h.append(title_box)
          h.append(add_button)
          h.append(menu_button)

          title_box.append(title_label)
          title_box.append(subtitle_label)

          collapse_button.signal_connect("clicked") { toggle }
          add_button.signal_connect("clicked") { window.new_project(source) }
          menu_button.menu_model = context_menu
        end

        revealer.child = listbox

        listbox.signal_connect("row-activated") do |_, row|
          project_rows.key(row).then do |id|
            store.project(id).then do |project|
              unless project.nil?
                window.show_project(project)
              end
            end
          end
        end

        register_actions
        reload
      end
    end

    def toggle
      revealer.reveal_child = !revealer.reveal_child?
      if revealer.reveal_child?
        collapse_button.icon_name = "arrow3-down-symbolic"
      else
        collapse_button.icon_name = "arrow3-right-symbolic"
      end
    end

    def reload
      @project_rows = {}

      while listbox.first_child
        listbox.remove(listbox.first_child)
      end

      store.root_projects_by_source(source.id).each { |project| append(project, 0) }

      title_label.label = source.header_text
      subtitle_label.label = source.subheader_text
      subtitle_label.visible = !source.subheader_text.empty?
      icon.icon_name = source.icon_name
      box.visible = source.visible?
    end

    def append(project, depth)
      ProjectRow.new(window, project, depth).build.tap do |row|
        @project_rows[project.id] = row
        listbox.append(row)
        store.subprojects_of(project.id).each { |child| append(child, depth + 1) }
      end
    end

    def select(project_id)
      if project_rows.key?(project_id)
        listbox.select_row(project_rows[project_id])
      end
    end

    SOURCE_ACTIONS = {
      "sync"    => :sync_now,
      "hide"    => :toggle_visible,
      "refresh" => :reload,
      "remove"  => :remove,
    }.freeze

    def register_actions
      Gio::SimpleActionGroup.new.tap do |group|
        SOURCE_ACTIONS.each do |name, method|
          Gio::SimpleAction.new(name).tap do |action|
            action.signal_connect("activate") { public_send(method) }
            group.add_action(action)
          end
        end

        box.insert_action_group("source", group)
      end
    end

    def context_menu
      @context_menu ||= Gio::Menu.new.tap do |menu|
        Gio::Menu.new.tap do |section|
          section.append(_("Sync Now"), "source.sync")
          section.append(_("Refresh"), "source.refresh")
          menu.append_section(nil, section)
        end

        Gio::Menu.new.tap do |section|
          section.append(_("Hide"), "source.hide")
          section.append(_("Remove Account"), "source.remove")
          menu.append_section(nil, section)
        end
      end
    end

    def sync_now
      store.sync_source(source) { |_, _| nil }
    end

    def toggle_visible
      if source.visible?
        source.is_visible = 0
      else
        source.is_visible = 1
      end
      store.update_source(source)
    end

    def remove
      Adwaita::AlertDialog.new(
        _("Remove Account?"),
        _(
          "“%s” and everything synced from it will be removed from this computer. " \
                    "Nothing is deleted on the server.",
        ) % source.display_name,
      ).tap do |dialog|
        dialog.add_response("cancel", _("Cancel"))
        dialog.add_response("remove", _("Remove"))
        dialog.set_response_appearance("remove", Adwaita::ResponseAppearance::DESTRUCTIVE)
        dialog.signal_connect("response") do |_, response|
          if response == "remove"
            store.delete_source(source)
          end
        end
        dialog.present(window.window)
      end
    end

    def box = @box ||= Gtk::Box.new(:vertical, 0)

    def header
      @header ||= Gtk::Box.new(:horizontal, 6).tap do |b|
        b.margin_top = 12
        b.margin_bottom = 3
      end
    end

    def collapse_button
      @collapse_button ||= Gtk::Button.new(icon_name: "arrow3-down-symbolic").tap do |button|
        button.add_css_class("flat")
      end
    end

    def icon
      @icon ||= Gtk::Image.new(icon_name: "computer-symbolic").tap { |i| i.pixel_size = 16 }
    end

    def title_box
      @title_box ||= Gtk::Box.new(:vertical, 0).tap { |b| b.hexpand = true }
    end

    def title_label
      @title_label ||= Gtk::Label.new("").tap do |label|
        label.add_css_class("heading")
        label.add_css_class("dim-label")
        label.xalign = 0
      end
    end

    def subtitle_label
      @subtitle_label ||= Gtk::Label.new("").tap do |label|
        label.add_css_class("caption")
        label.add_css_class("dim-label")
        label.xalign = 0
        label.visible = false
      end
    end

    def add_button
      @add_button ||= Gtk::Button.new(icon_name: "plus-large-symbolic").tap do |button|
        button.add_css_class("flat")
        button.tooltip_text = _("Add Project")
      end
    end

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.icon_name = "view-more-symbolic"
        button.add_css_class("flat")
      end
    end

    def revealer
      @revealer ||= Gtk::Revealer.new.tap do |r|
        r.transition_type = :slide_down
        r.reveal_child = true
      end
    end

    def listbox
      @listbox ||= Gtk::ListBox.new.tap do |list|
        list.add_css_class("navigation-sidebar")
        list.selection_mode = :single
      end
    end
  end

  # src/Widgets/MagicButton.vala. The floating plus, which upstream lets you
  # drag up the list to choose where the new task lands.
  class MagicButton
    def initialize(&on_activate)
      @on_activate = on_activate
    end

    def build
      @build ||= button.tap do |b|
        b.signal_connect("clicked") { @on_activate&.call(nil) }
        b.add_controller(drag_source)

        drag_source.signal_connect("prepare") do |_, _, _|
          Gdk::ContentProvider.new("magic-button")
        end

        drag_source.signal_connect("drag-begin") { button.add_css_class("dragging") }
        drag_source.signal_connect("drag-end") { button.remove_css_class("dragging") }
      end
    end

    def button
      @button ||= Gtk::Button.new(icon_name: "plus-large-symbolic").tap do |b|
        b.add_css_class("suggested-action")
        b.add_css_class("circular")
        b.add_css_class("magic-button")
        b.halign = :end
        b.valign = :end
        b.margin_end = 24
        b.margin_bottom = 24
        b.width_request = 48
        b.height_request = 48
        b.tooltip_text = _("Add Task")
      end
    end

    def drag_source
      @drag_source ||= Gtk::DragSource.new.tap do |source|
        source.actions = Gdk::DragAction::COPY
      end
    end
  end

  # src/Widgets/MultiSelectToolbar.vala. Appears over the list while tasks are
  # selected, and acts on all of them at once.
  class MultiSelectToolbar
    def initialize(window)
      @window = window
    end

    attr_reader :window

    def store = Store.instance

    def build
      @build ||= revealer.tap do |r|
        r.child = box

        box.tap do |b|
          b.append(count_label)
          b.append(complete_button)
          b.append(schedule_button)
          b.append(priority_button)
          b.append(label_button)
          b.append(move_button)
          b.append(delete_button)
          b.append(cancel_button)

          complete_button.signal_connect("clicked") { complete }
          delete_button.signal_connect("clicked") { delete }
          cancel_button.signal_connect("clicked") { cancel }
          move_button.signal_connect("clicked") { move }

          schedule_button.popover = schedule_popover
          schedule_popover.child = date_picker.build

          priority_button.popover = priority_popover
          priority_popover.child = priority_list

          priority_list.tap do |list|
            PRIORITIES.each { |level| list.append(priority_row(level)) }
            list.signal_connect("row-activated") do |_, row|
              set_priority(PRIORITIES[row.index])
            end
          end

          label_button.popover = label_popover
          label_popover.child = label_picker.build
        end

        Services::EventBus.on(:selection_changed, owner: self) { |selected| refresh(selected) }
      end
    end

    PRIORITIES = [Item::PRIORITY_1, Item::PRIORITY_2, Item::PRIORITY_3, Item::PRIORITY_4].freeze

    def selected = Services::EventBus.selected

    def refresh(items)
      revealer.reveal_child = !items.empty?
      count_label.label = n_("%d selected", "%d selected", items.size) % items.size
    end

    def complete
      selected.each { |item| store.complete_item(item, true) }
      cancel
    end

    def set_priority(level)
      selected.each do |item|
        item.priority = level
        store.update_item(item)
      end
      priority_popover.popdown
      cancel
    end

    def schedule(time, due)
      selected.each do |item|
        item.due_date = time
        unless time.nil?
          item.due = JSON.generate(item.due_hash.merge(due))
        end
        store.update_item(item)
      end
      schedule_popover.popdown
      cancel
    end

    def apply_labels(ids)
      selected.each do |item|
        item.label_ids = (item.label_ids + ids).uniq
        store.update_item(item)
      end
    end

    def move
      Dialogs::ProjectDialog.move_many(window, selected.dup).present(window.window)
      cancel
    end

    def delete
      selected.dup.then do |items|
        items.each { |item| store.trash_item(item) }
        window.toast_with_undo(
          n_("%d task deleted", "%d tasks deleted", items.size) % items.size,
        ) { items.each { |item| store.restore_item(item) } }
      end
      cancel
    end

    def cancel
      Services::EventBus.clear_selection
      Services::EventBus.multi_select = false
    end

    def revealer
      @revealer ||= Gtk::Revealer.new.tap do |r|
        r.transition_type = :slide_up
        r.valign = :end
        r.halign = :center
      end
    end

    def box
      @box ||= Gtk::Box.new(:horizontal, 6).tap do |b|
        b.add_css_class("toolbar")
        b.add_css_class("osd")
        b.margin_bottom = 24
        b.margin_start = 12
        b.margin_end = 12
      end
    end

    def count_label
      @count_label ||= Gtk::Label.new("").tap do |label|
        label.margin_start = 9
        label.margin_end = 9
      end
    end

    def complete_button
      @complete_button ||= Gtk::Button.new(icon_name: "check-round-outline-symbolic").tap do |b|
        b.add_css_class("flat")
        b.tooltip_text = _("Complete")
      end
    end

    def schedule_button
      @schedule_button ||= Gtk::MenuButton.new.tap do |b|
        b.icon_name = "month-symbolic"
        b.add_css_class("flat")
        b.tooltip_text = _("Schedule")
      end
    end

    def schedule_popover = @schedule_popover ||= Gtk::Popover.new

    def date_picker
      @date_picker ||= DateTimePicker.new { |time, due| schedule(time, due) }
    end

    def priority_button
      @priority_button ||= Gtk::MenuButton.new.tap do |b|
        b.icon_name = "flag-outline-thick-symbolic"
        b.add_css_class("flat")
        b.tooltip_text = _("Priority")
      end
    end

    def priority_popover = @priority_popover ||= Gtk::Popover.new

    def priority_list
      @priority_list ||= Gtk::ListBox.new.tap do |list|
        list.selection_mode = :none
        list.add_css_class("menu-listbox")
      end
    end

    def priority_row(level)
      Gtk::ListBoxRow.new.tap do |row|
        row.child = Gtk::Label.new(Item.new(priority: level).priority_text).tap do |label|
          label.xalign = 0
          label.margin_start = 9
          label.margin_end = 9
          label.margin_top = 6
          label.margin_bottom = 6
        end
      end
    end

    def label_button
      @label_button ||= Gtk::MenuButton.new.tap do |b|
        b.icon_name = "tag-outline-symbolic"
        b.add_css_class("flat")
        b.tooltip_text = _("Labels")
      end
    end

    def label_popover = @label_popover ||= Gtk::Popover.new

    def label_picker
      @label_picker ||= LabelPicker.new { |ids| apply_labels(ids) }
    end

    def move_button
      @move_button ||= Gtk::Button.new(icon_name: "arrow3-right-symbolic").tap do |b|
        b.add_css_class("flat")
        b.tooltip_text = _("Move")
      end
    end

    def delete_button
      @delete_button ||= Gtk::Button.new(icon_name: "user-trash-symbolic").tap do |b|
        b.add_css_class("flat")
        b.tooltip_text = _("Delete")
      end
    end

    def cancel_button
      @cancel_button ||= Gtk::Button.new(icon_name: "window-close-symbolic").tap do |b|
        b.add_css_class("flat")
        b.tooltip_text = _("Cancel")
      end
    end
  end
end
