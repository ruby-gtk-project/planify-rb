# frozen_string_literal: true

module Planify
  # Layouts/ProjectRow.vala: one project in the sidebar — its emoji or its
  # progress ring, its name, the pending count, and the project menu.
  class ProjectRow
    def initialize(window, project, depth = 0)
      @window = window
      @project = project
      @depth = depth
    end

    attr_reader :window, :project, :depth

    def build
      @build ||= row.tap do |r|
        r.child = box

        box.tap do |b|
          b.append(icon_stack)
          b.append(name_label)
          b.append(count_label)
          b.append(menu_button)

          icon_stack.tap do |stack|
            stack.add_named(emoji_label, "emoji")
            stack.add_named(progress_area, "progress")
          end

          menu_button.menu_model = context_menu
        end

        register_actions
        refresh
      end
    end

    def store = Store.instance

    def refresh
      name_label.label = project.name.to_s
      if project.emoji?
        icon_stack.visible_child_name = "emoji"
      else
        icon_stack.visible_child_name = "progress"
      end
      emoji_label.label = project.emoji.to_s
      count_label.label = store.items_by_project(project.id).count { |item| !item.checked? }.to_s
      count_label.visible = Settings.get_boolean("show-tasks-count")
      progress_area.queue_draw
    end

    # The progress ring upstream draws with Cairo; same here, filled to the
    # project's completion fraction in the project's colour.
    def draw_progress(context, width, height)
      Palette.rgba(project.color).then do |rgba|
        radius = [width, height].min / 2.0 - 2
        centre_x = width / 2.0
        centre_y = height / 2.0

        context.set_source_rgba(
          rgba.red,
          rgba.green,
          rgba.blue,
          0.25,
        )
        context.arc(
          centre_x,
          centre_y,
          radius,
          0,
          2 * Math::PI,
        )
        context.fill

        context.set_source_rgba(
          rgba.red,
          rgba.green,
          rgba.blue,
          1.0,
        )
        context.move_to(centre_x, centre_y)
        context.arc(

          centre_x,

          centre_y,

          radius,
          -Math::PI / 2,

          (-Math::PI / 2) + (2 * Math::PI * project.percentage),
        )
        context.fill
      end
    end

    PROJECT_ACTIONS = {
      "edit"        => :edit,
      "favorite"    => :toggle_favorite,
      "add-section" => :add_section,
      "duplicate"   => :duplicate,
      "archive"     => :archive,
      "delete"      => :delete,
    }.freeze

    def register_actions
      Gio::SimpleActionGroup.new.tap do |group|
        PROJECT_ACTIONS.each do |name, method|
          Gio::SimpleAction.new(name).tap do |action|
            action.signal_connect("activate") { public_send(method) }
            group.add_action(action)
          end
        end

        row.insert_action_group("project", group)
      end
    end

    def context_menu
      @context_menu ||= Gio::Menu.new.tap do |menu|
        Gio::Menu.new.tap do |section|
          section.append(_("Edit Project"), "project.edit")
          section.append(_("Add to Favorites"), "project.favorite")
          section.append(_("Add Section"), "project.add-section")
          menu.append_section(nil, section)
        end

        Gio::Menu.new.tap do |section|
          section.append(_("Duplicate"), "project.duplicate")
          section.append(_("Archive"), "project.archive")
          section.append(_("Delete Project"), "project.delete")
          menu.append_section(nil, section)
        end
      end
    end

    def edit
      Dialogs::ProjectDialog.new(window, project: project).present(window.window)
    end

    def toggle_favorite
      if project.favorite?
        project.is_favorite = 0
      else
        project.is_favorite = 1
      end
      store.update_project(project)
    end

    def add_section
      Dialogs::SectionDialog.new(window, project).present(window.window)
    end

    def duplicate
      Project.new(**project.to_row.except(:id)).tap do |copy|
        copy.name = _("%s (copy)") % project.name
        copy.inbox_project = 0
        store.insert_project(copy)
      end
    end

    def archive
      store.archive_project(project)
      window.drop_view("project-#{project.id}")
      window.toast_with_undo(_("Project archived")) { store.unarchive_project(project) }
    end

    def delete
      Adwaita::AlertDialog.new(
        _("Delete Project?"),
        _("This will delete “%s” and all of its tasks. This cannot be undone.") % project.name,
      ).tap do |dialog|
        dialog.add_response("cancel", _("Cancel"))
        dialog.add_response("delete", _("Delete"))
        dialog.set_response_appearance("delete", Adwaita::ResponseAppearance::DESTRUCTIVE)
        dialog.signal_connect("response") do |_, response|
          if response == "delete"
            window.drop_view("project-#{project.id}")
            store.delete_project(project)
            window.go_inbox
          end
        end
        dialog.present(window.window)
      end
    end

    # --- widgets --------------------------------------------------------

    def row
      @row ||= Gtk::ListBoxRow.new.tap do |r|
        r.add_css_class("project-row")
      end
    end

    def box
      @box ||= Gtk::Box.new(:horizontal, 9).tap do |b|
        b.margin_start = 6 + (depth * 18)
        b.margin_end = 6
        b.margin_top = 3
        b.margin_bottom = 3
      end
    end

    def icon_stack
      @icon_stack ||= Gtk::Stack.new.tap do |stack|
        stack.width_request = 16
        stack.height_request = 16
        stack.valign = :center
      end
    end

    def emoji_label = @emoji_label ||= Gtk::Label.new("")

    def progress_area
      @progress_area ||= Gtk::DrawingArea.new.tap do |area|
        area.set_size_request(16, 16)
        area.set_draw_func { |_, context, width, height| draw_progress(context, width, height) }
      end
    end

    def name_label
      @name_label ||= Gtk::Label.new("").tap do |label|
        label.xalign = 0
        label.hexpand = true
        label.ellipsize = :end
      end
    end

    def count_label
      @count_label ||= Gtk::Label.new("").tap do |label|
        label.add_css_class("dim-label")
        label.add_css_class("caption")
      end
    end

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.icon_name = "view-more-symbolic"
        button.add_css_class("flat")
        button.valign = :center
      end
    end
  end
end
