# frozen_string_literal: true

module Planify
  module Services
    # core/Services/EventBus.vala. Store carries the data events; this carries
    # the UI ones — selection, drag state, theme changes, multi-select mode —
    # that no single object owns.
    module EventBus
      module_function

      def subscribers = @subscribers ||= Hash.new { |hash, key| hash[key] = [] }

      def on(event, owner: nil, &block)
        subscribers[event] << [owner, block]
      end

      def unsubscribe(owner)
        subscribers.each_value { |list| list.reject! { |(who, _)| who.equal?(owner) } }
      end

      def emit(event, *args)
        subscribers[event].dup.each { |(_, block)| block.call(*args) }
      end

      # The multi-select mode the toolbar drives. Kept here rather than on a
      # view because the sidebar, the toolbar and every row need to agree.
      def multi_select? = @multi_select == true

      def multi_select=(value)
        @multi_select = value
        emit(:multi_select_changed, value)
      end

      def selected = @selected ||= []

      def select(item)
        unless selected.include?(item)
          selected.push(item)
        end
        emit(:selection_changed, selected)
      end

      def unselect(item)
        selected.delete(item)
        emit(:selection_changed, selected)
      end

      def clear_selection
        @selected = []
        emit(:selection_changed, selected)
      end

      def toggle_selection(item)
        if selected.include?(item)
          unselect(item)
        else
          select(item)
        end
      end
    end
  end
end
