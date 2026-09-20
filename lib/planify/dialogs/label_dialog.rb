# frozen_string_literal: true

module Planify
  module Dialogs
    # src/Dialogs/Label.vala: a label is a name and a colour.
    class LabelDialog
      def initialize(window, label: nil)
        @window = window
        @label = label
        @editing = !label.nil?
      end

      attr_reader :window, :label

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
                Adwaita::WindowTitle.new(@editing ? _("Edit Label") : _("New Label"), "")

              cancel_button.signal_connect("clicked") { d.close }
              save_button.signal_connect("clicked") { save }
            end

            page.add(group)

            group.tap do |g|
              g.add(name_row)
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
          name_row.text = label.name.to_s
          color_picker.color = label.color.to_s
        else
          color_picker.color = Palette.random
        end
      end

      # Label names are unique in the schema, so a clash is reported rather
      # than left to fail against the constraint.
      def save
        name_row.text.strip.then do |name|
          if name.empty?
            name_row.add_css_class("error")
          elsif taken?(name)
            window.toast(_("A label named “%s” already exists") % name)
          else
            persist(name)
            dialog.close
          end
        end
      end

      def taken?(name)
        store.label_by_name(name).then { |existing| !existing.nil? && existing != label }
      end

      def persist(name)
        (label || Label.new(source_id: "local")).tap do |record|
          record.name = name
          record.color = color_picker.color

          if @editing
            store.update_label(record)
          else
            record.item_order = store.labels.size
            store.insert_label(record)
          end
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

      def color_row
        @color_row ||= Adwaita::PreferencesRow.new.tap do |row|
          row.activatable = false
        end
      end

      def color_picker = @color_picker ||= ColorPicker.new
    end
  end
end
