# frozen_string_literal: true

module Planify
  # Layouts/SectionRow.vala: a collapsible header over the section's tasks,
  # with the add-task button and the section menu.
  class SectionRow
    def initialize(window, section, project)
      @window = window
      @section = section
      @project = project
      @rows = {}
    end

    attr_reader :window, :section, :project

    def build
      @build ||= box.tap do |b|
        b.append(header_box)
        b.append(revealer)

        header_box.tap do |header|
          header.append(collapse_button)
          header.append(name_label)
          header.append(count_label)
          header.append(add_button)
          header.append(menu_button)

          collapse_button.signal_connect("clicked") { toggle_collapsed }
          add_button.signal_connect("clicked") { add_task }
          menu_button.menu_model = context_menu
        end

        revealer.child = listbox

        listbox.signal_connect("row-activated") do |_, row|
          @rows.find { |_, entry| entry.build == row }.then do |found|
            unless found.nil?
              window.show_item(Store.instance.item(found.first))
            end
          end
        end

        register_actions
        refresh
      end
    end

    def store = Store.instance

    def refresh
      name_label.label = section.name.to_s
      count_label.label = items.count { |item| !item.checked? }.to_s
      count_label.visible = Settings.get_boolean("show-tasks-count")
      if section.collapsed?
        collapse_button.icon_name = "arrow3-right-symbolic"
      else
        collapse_button.icon_name = "arrow3-down-symbolic"
      end
      revealer.reveal_child = !section.collapsed?
      rebuild
    end

    def items
      store.items_by_section(section.id).then do |all|
        if project.show_completed?
          all
        else
          all.reject(&:checked?)
        end
      end
    end

    # Rows are reused between refreshes rather than rebuilt, which keeps a
    # long list from churning a MenuButton per row on every item event.
    def rebuild
      items.then do |current|
        ids = current.map(&:id)

        (@rows.keys - ids).each { |id| listbox.remove(@rows.delete(id).build) }

        current.each do |item|
          if @rows.key?(item.id)
            @rows.fetch(item.id).refresh
          else
            add_row(item)
          end
        end

        placeholder.visible = current.empty?
      end
    end

    def add_row(item)
      ItemRow.new(window, item).tap do |row|
        @rows[item.id] = row
        listbox.append(row.build)
      end
    end

    def toggle_collapsed
      if section.collapsed?
        section.collapsed = 0
      else
        section.collapsed = 1
      end
      store.update_section(section)
      refresh
    end

    def add_task
      QuickAdd.new(window, project: project, section: section).present(window.window)
    end

    SECTION_ACTIONS = {
      "edit"      => :edit,
      "duplicate" => :duplicate,
      "archive"   => :archive,
      "delete"    => :delete,
    }.freeze

    def register_actions
      Gio::SimpleActionGroup.new.tap do |group|
        SECTION_ACTIONS.each do |name, method|
          Gio::SimpleAction.new(name).tap do |action|
            action.signal_connect("activate") { public_send(method) }
            group.add_action(action)
          end
        end

        box.insert_action_group("section", group)
      end
    end

    def context_menu
      @context_menu ||= Gio::Menu.new.tap do |menu|
        Gio::Menu.new.tap do |group|
          group.append(_("Edit Section"), "section.edit")
          group.append(_("Duplicate"), "section.duplicate")
          menu.append_section(nil, group)
        end

        Gio::Menu.new.tap do |group|
          group.append(_("Archive"), "section.archive")
          group.append(_("Delete Section"), "section.delete")
          menu.append_section(nil, group)
        end
      end
    end

    def edit
      Dialogs::SectionDialog.new(window, project, section: section).present(window.window)
    end

    def duplicate
      Section.new(
        name:          _("%s (copy)") % section.name,
        project_id:    project.id,
        color:         section.color,
        section_order: section.section_order.to_i + 1,
      ).tap do |copy|
        store.insert_section(copy)
        items.each do |item|
          store.insert_item(Item.new(**item.to_row.except(:id), section_id: copy.id))
        end
      end
    end

    def archive
      section.is_archived = 1
      store.update_section(section)
      window.toast_with_undo(_("Section archived")) do
        section.is_archived = 0
        store.update_section(section)
      end
    end

    def delete
      Adwaita::AlertDialog.new(
        _("Delete Section?"),
        _(
          "This will delete the section and " \
                                                                "all of its tasks.",
        ),
      ).tap do |dialog|
        dialog.add_response("cancel", _("Cancel"))
        dialog.add_response("delete", _("Delete"))
        dialog.set_response_appearance("delete", Adwaita::ResponseAppearance::DESTRUCTIVE)
        dialog.signal_connect("response") do |_, response|
          if response == "delete"
            store.delete_section(section)
          end
        end
        dialog.present(window.window)
      end
    end

    # --- widgets --------------------------------------------------------

    def box
      @box ||= Gtk::Box.new(:vertical, 0).tap do |b|
        b.margin_top = 12
      end
    end

    def header_box
      @header_box ||= Gtk::Box.new(:horizontal, 6).tap do |b|
        b.margin_start = 6
        b.margin_end = 6
        b.margin_bottom = 3
      end
    end

    def collapse_button
      @collapse_button ||= Gtk::Button.new(icon_name: "arrow3-down-symbolic").tap do |button|
        button.add_css_class("flat")
      end
    end

    def name_label
      @name_label ||= Gtk::Label.new("").tap do |label|
        label.add_css_class("heading")
        label.xalign = 0
        label.hexpand = true
      end
    end

    def count_label
      @count_label ||= Gtk::Label.new("").tap do |label|
        label.add_css_class("dim-label")
        label.add_css_class("caption")
      end
    end

    def add_button
      @add_button ||= Gtk::Button.new(icon_name: "plus-large-symbolic").tap do |button|
        button.add_css_class("flat")
        button.tooltip_text = _("Add Task")
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
      end
    end

    def listbox
      @listbox ||= Gtk::ListBox.new.tap do |list|
        list.selection_mode = :none
        list.add_css_class("background")
        list.set_placeholder(placeholder)
      end
    end

    def placeholder
      @placeholder ||= Gtk::Label.new(_("No tasks in this section")).tap do |label|
        label.add_css_class("dim-label")
        label.margin_top = 12
        label.margin_bottom = 12
      end
    end
  end
end
