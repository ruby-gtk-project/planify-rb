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
            store.label(row.name.to_s).then do |label|
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
          LabelRow.new(window, label).tap do |row|
            @rows[label.id] = row
            list_box.append(row.build)
          end
        end

        if labels.empty?
          stack.visible_child_name = "empty"
        else
          stack.visible_child_name = "list"
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
