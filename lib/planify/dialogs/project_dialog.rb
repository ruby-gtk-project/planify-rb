# frozen_string_literal: true

module Planify
  module Dialogs
    # src/Dialogs/Project.vala: create or edit a project — name, icon, colour,
    # description, parent, layout — and the "move task to project" variant of
    # the same picker.
    class ProjectDialog
      def initialize(window, project: nil, source: nil)
        @window = window
        @project = project
        @source = source
        @editing = !project.nil?
      end

      attr_reader :window, :project, :source

      def self.move(window, item)
        MoveDialog.new(window, [item])
      end

      def self.move_many(window, items)
        MoveDialog.new(window, items)
      end

      def store = Store.instance

      def present(parent)
        dialog.tap do |d|
          d.child = toolbar

          toolbar.tap do |view|
            view.add_top_bar(header)
            view.content = page

            header.tap do |h|
              h.show_end_title_buttons = false
              h.pack_start(cancel_button)
              h.pack_end(save_button)

              cancel_button.signal_connect("clicked") { d.close }
              save_button.signal_connect("clicked") { save }
            end

            page.tap do |p|
              p.add(identity_group)
              p.add(appearance_group)
              p.add(placement_group)

              identity_group.tap do |group|
                group.add(name_row)
                group.add(description_row)
              end

              appearance_group.tap do |group|
                group.add(icon_style_row)
                group.add(emoji_row)
                group.add(color_row)

                emoji_row.add_suffix(emoji_picker.build)
                color_row.child = color_picker.build

                icon_style_row.tap do |row|
                  row.model = Gtk::StringList.new([_("Progress"), _("Emoji")])
                  row.signal_connect("notify::selected") { refresh_icon_style }
                end
              end

              placement_group.tap do |group|
                group.add(parent_row)
                group.add(layout_row)

                parent_row.model = Gtk::StringList.new(parent_titles)
                layout_row.model = Gtk::StringList.new([_("List"), _("Board")])
              end
            end
          end

          load
          d.present(parent)
          name_row.grab_focus
        end
      end

      def parents = [nil] + store.active_projects.reject { |candidate| candidate == project }

      def parent_titles = parents.map { |candidate| candidate.nil? ? _("None") : candidate.name }

      def load
        header.title_widget =
          Adwaita::WindowTitle.new(@editing ? _("Edit Project") : _("New Project"), "")

        if @editing
          name_row.text = project.name.to_s
          description_row.text = project.description.to_s
          if project.emoji?
            icon_style_row.selected = 1
          else
            icon_style_row.selected = 0
          end
          emoji_picker.emoji = project.emoji.to_s
          color_picker.color = project.color.to_s
          parent_row.selected = parents.index { |c| c&.id == project.parent_id } || 0
          if project.board?
            layout_row.selected = 1
          else
            layout_row.selected = 0
          end
        else
          color_picker.color = Palette.random
        end

        refresh_icon_style
      end

      def refresh_icon_style
        emoji_row.visible = icon_style_row.selected == 1
      end

      def save
        name_row.text.strip.then do |name|
          unless name.empty?
            target.tap do |record|
              record.name = name
              record.description = description_row.text
              if icon_style_row.selected == 1
                record.icon_style = "emoji"
              else
                record.icon_style = "progress"
              end
              record.emoji = emoji_picker.emoji
              record.color = color_picker.color
              record.parent_id = parents[parent_row.selected]&.id.to_s
              if layout_row.selected == 1
                record.view_style = "board"
              else
                record.view_style = "list"
              end
              persist(record)
            end

            dialog.close
          end
        end
      end

      # A project created from an account's "+" belongs to that account; one
      # created from the menu belongs to the local source.
      def target
        project || Project.new(source_id: (source || Store.instance.local_source)&.id.to_s)
      end

      def persist(record)
        if @editing
          store.update_project(record)
        else
          record.child_order = store.root_projects.size
          store.insert_project(record)
          window.show_project(record)
        end
      end

      # --- widgets ---------------------------------------------------------

      def dialog
        @dialog ||= Adwaita::Dialog.new.tap do |d|
          d.content_width = 480
          d.content_height = 640
        end
      end

      def toolbar = @toolbar ||= Adwaita::ToolbarView.new

      def header = @header ||= Adwaita::HeaderBar.new

      def cancel_button = @cancel_button ||= Gtk::Button.new(label: _("Cancel"))

      def save_button
        @save_button ||= Gtk::Button.new(label: _("Save")).tap do |button|
          button.add_css_class("suggested-action")
        end
      end

      def page = @page ||= Adwaita::PreferencesPage.new

      def identity_group = @identity_group ||= Adwaita::PreferencesGroup.new

      def name_row
        @name_row ||= Adwaita::EntryRow.new.tap do |row|
          row.title = _("Name")
        end
      end

      def description_row
        @description_row ||= Adwaita::EntryRow.new.tap do |row|
          row.title = _("Description")
        end
      end

      def appearance_group
        @appearance_group ||= Adwaita::PreferencesGroup.new.tap do |group|
          group.title = _("Appearance")
        end
      end

      def icon_style_row
        @icon_style_row ||= Adwaita::ComboRow.new.tap do |row|
          row.title = _("Icon")
        end
      end

      def emoji_row
        @emoji_row ||= Adwaita::ActionRow.new.tap do |row|
          row.title = _("Emoji")
        end
      end

      def emoji_picker = @emoji_picker ||= EmojiPicker.new

      def color_row
        @color_row ||= Adwaita::PreferencesRow.new.tap do |row|
          row.activatable = false
        end
      end

      def color_picker = @color_picker ||= ColorPicker.new

      def placement_group
        @placement_group ||= Adwaita::PreferencesGroup.new.tap do |group|
          group.title = _("Placement")
        end
      end

      def parent_row
        @parent_row ||= Adwaita::ComboRow.new.tap do |row|
          row.title = _("Parent Project")
        end
      end

      def layout_row
        @layout_row ||= Adwaita::ComboRow.new.tap do |row|
          row.title = _("Layout")
        end
      end
    end

    # "Move" from a task's menu: pick a project, and a section within it.
    class MoveDialog
      def initialize(window, items)
        @window = window
        @items = Array(items)
      end

      attr_reader :window, :items

      def item = items.first

      def store = Store.instance

      def present(parent)
        dialog.tap do |d|
          d.child = toolbar

          toolbar.tap do |view|
            view.add_top_bar(header)
            view.content = scrolled

            scrolled.child = listbox

            listbox.tap do |list|
              targets.each { |target| list.append(target_row(target)) }

              list.signal_connect("row-activated") do |_, row|
                move_to(targets[row.index])
                d.close
              end
            end
          end

          header.title_widget = Adwaita::WindowTitle.new(_("Move To"), move_subtitle)
          d.present(parent)
        end
      end

      # Each project contributes itself and each of its sections as a target.
      def targets
        @targets ||= store.active_projects.push(store.inbox_project).compact.uniq.flat_map do |project|
          [[project, nil]] + store.sections_by_project(project.id).map { |section| [project, section] }
        end
      end

      def target_row((project, section))
        Adwaita::ActionRow.new.tap do |row|
          row.title = project.name.to_s
          row.subtitle = section&.name.to_s
          row.activatable = true
        end
      end

      def move_to((project, section))
        items.each do |moved|
          moved.project_id = project.id
          moved.section_id = section&.id.to_s
          moved.child_order = store.next_child_order(moved.project_id, moved.section_id)
          store.update_item(moved)
        end

        window.toast(
          n_("Task moved to %s", "%d tasks moved", items.size) % moved_arguments(project),
        )
      end

      # One task names its destination; several report their count, because
      # the destination is the same for all of them and the number is what
      # the user needs confirmed.
      def moved_arguments(project)
        items.size == 1 ? project.name : items.size
      end

      def move_subtitle
        if items.size == 1
          item.content.to_s
        else
          n_("%d task", "%d tasks", items.size) % items.size
        end
      end

      def dialog
        @dialog ||= Adwaita::Dialog.new.tap do |d|
          d.content_width = 400
          d.content_height = 520
        end
      end

      def toolbar = @toolbar ||= Adwaita::ToolbarView.new

      def header = @header ||= Adwaita::HeaderBar.new

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
    end
  end
end
