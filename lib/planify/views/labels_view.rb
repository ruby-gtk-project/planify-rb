# frozen_string_literal: true

module Planify
  module Views
    # src/Views/Label: every label with its pending count. Activating one opens
    # the filter view for that label.
    class LabelsView < BaseView
      def title = _("Labels")

      def subtitle
        store.labels.size.then { |count| n_("%d label", "%d labels", count) % count }
      end

      def build
        @build ||= super.tap do
          header.pack_end(add_label_button)
          add_label_button.signal_connect("clicked") { add_label }
          add_button.tooltip_text = _("Add Label")

          list_box.signal_connect("row-activated") do |_, row|
            labels[row.index].then do |label|
              unless label.nil?
                window.show_label(label)
              end
            end
          end
        end
      end

      def subscribe
        %i[label_added label_updated label_deleted item_added item_updated item_deleted]
          .each { |event| store.on(event, owner: self) { refresh } }
      end

      def labels
        store.labels.then do |all|
          if Settings.get_boolean("labels-show-active-only")
            all.select { |label| !store.items_by_label(label.id).empty? }
          else
            all
          end
        end.sort_by { |label| label.item_order.to_i }
      end

      def rebuild
        @rows = {}
        while list_box.first_child
          list_box.remove(list_box.first_child)
        end

        labels.each do |label|
          label_row(label).tap do |row|
            @rows[label.id] = row
            list_box.append(row)
          end
        end

        if labels.empty?
          stack.visible_child_name = "empty"
        else
          stack.visible_child_name = "list"
        end
      end

      def label_row(label)
        Adwaita::ActionRow.new.tap do |row|
          row.title = label.name.to_s
          row.subtitle = n_("%d task", "%d tasks", store.items_by_label(label.id).size) %
                         store.items_by_label(label.id).size
          row.activatable = true
          row.add_prefix(label_icon(label))
          row.add_suffix(edit_button(label))
          row.add_suffix(delete_button(label))
        end
      end

      def label_icon(label)
        Gtk::Image.new(icon_name: "tag-outline-symbolic").tap do |image|
          Gtk::CssProvider.new.tap do |provider|
            provider.load(data: "image { color: #{Palette.hex(label.color)}; }")
            image.style_context.add_provider(provider, Gtk::StyleProvider::PRIORITY_APPLICATION)
          end
        end
      end

      def edit_button(label)
        Gtk::Button.new(icon_name: "edit-symbolic").tap do |button|
          button.add_css_class("flat")
          button.valign = :center
          button.tooltip_text = _("Edit Label")
          button.signal_connect("clicked") do
            Dialogs::LabelDialog.new(window, label: label).present(window.window)
          end
        end
      end

      def delete_button(label)
        Gtk::Button.new(icon_name: "user-trash-symbolic").tap do |button|
          button.add_css_class("flat")
          button.valign = :center
          button.tooltip_text = _("Delete Label")
          button.signal_connect("clicked") { confirm_delete(label) }
        end
      end

      def confirm_delete(label)
        Adwaita::AlertDialog.new(
          _("Delete Label?"),
          _("“%s” will be removed from every task that carries it.") % label.name,
        ).tap do |dialog|
          dialog.add_response("cancel", _("Cancel"))
          dialog.add_response("delete", _("Delete"))
          dialog.set_response_appearance("delete", Adwaita::ResponseAppearance::DESTRUCTIVE)
          dialog.signal_connect("response") do |_, response|
            if response == "delete"
              store.delete_label(label)
            end
          end
          dialog.present(window.window)
        end
      end

      def add_task = add_label

      def add_label
        Dialogs::LabelDialog.new(window).present(window.window)
      end

      def empty_title = _("No labels yet")

      def empty_description = _("Labels help you group tasks across projects.")

      def empty_icon = "tag-outline-symbolic"

      def add_label_button
        @add_label_button ||= Gtk::Button.new(icon_name: "plus-large-symbolic").tap do |button|
          button.add_css_class("flat")
          button.tooltip_text = _("Add Label")
        end
      end
    end
  end
end
