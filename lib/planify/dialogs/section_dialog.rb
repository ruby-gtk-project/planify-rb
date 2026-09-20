# frozen_string_literal: true

module Planify
  module Dialogs
    # src/Dialogs/Section.vala: name and colour, create or edit.
    class SectionDialog
      def initialize(window, project, section: nil)
        @window = window
        @project = project
        @section = section
        @editing = !section.nil?
      end

      attr_reader :window, :project, :section

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
              h.title_widget =
                Adwaita::WindowTitle.new(@editing ? _("Edit Section") : _("New Section"), "")

              cancel_button.signal_connect("clicked") { d.close }
              save_button.signal_connect("clicked") { save }
            end

            page.add(group)

            group.tap do |g|
              g.add(name_row)
              g.add(description_row)
              g.add(color_row)
              color_row.child = color_picker.build
            end
          end

          load
          d.present(parent)
          name_row.grab_focus
        end
      end

      def load
        if @editing
          name_row.text = section.name.to_s
          description_row.text = section.description.to_s
          color_picker.color = section.color.to_s
        else
          color_picker.color = Palette.random
        end
      end

      def save
        name_row.text.strip.then do |name|
          unless name.empty?
            target.tap do |record|
              record.name = name
              record.description = description_row.text
              record.color = color_picker.color
              persist(record)
            end

            dialog.close
          end
        end
      end

      def target = section || Section.new(project_id: project.id)

      def persist(record)
        if @editing
          store.update_section(record)
        else
          record.section_order = store.sections_by_project(project.id).size
          store.insert_section(record)
        end
      end

      def dialog
        @dialog ||= Adwaita::Dialog.new.tap do |d|
          d.content_width = 440
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

      def group = @group ||= Adwaita::PreferencesGroup.new

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

      def color_row
        @color_row ||= Adwaita::PreferencesRow.new.tap do |row|
          row.activatable = false
        end
      end

      def color_picker = @color_picker ||= ColorPicker.new
    end
  end
end
