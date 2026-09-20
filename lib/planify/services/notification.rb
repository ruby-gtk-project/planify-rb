# frozen_string_literal: true

module Planify
  module Services
    # src/Services/Notification.vala. A reminder that is already past fires at
    # once; one due later today gets a timeout; one further out waits for
    # TimeMonitor to roll the day over and ask again.
    module Notification
      module_function

      def store = Store.instance

      def application = @application

      def application=(app)
        @application = app
      end

      def timeouts = @timeouts ||= {}

      def init(app)
        self.application = app
        store.on(:reminder_added, owner: self) { |reminder| reminder_added(reminder) }
        store.on(:reminder_deleted, owner: self) { |reminder| cancel(reminder) }
        store.on(:item_deleted, owner: self) { |item| cancel_for_item(item) }
        refresh
      end

      def refresh
        timeouts.each_value { |id| GLib::Source.remove(id) }
        @timeouts = {}
        store.reminders.each { |reminder| reminder_added(reminder) }
      end

      def reminder_added(reminder)
        reminder.due_date.then do |due|
          if due.nil?
            nil
          elsif due <= Time.now
            send_for(reminder)
          elsif Datetime.today?(due)
            schedule(reminder, due)
          end
        end
      end

      # GLib timeouts take milliseconds and the reminder may be seconds away,
      # so the delay is clamped to at least one tick.
      def schedule(reminder, due)
        [((due - Time.now) * 1000).to_i, 1000].max.then do |delay|
          timeouts[reminder.id] = GLib::Timeout.add(delay) do
            timeouts.delete(reminder.id)
            send_for(reminder)
            false
          end
        end
      end

      def cancel(reminder)
        timeouts.delete(reminder.id).then do |id|
          unless id.nil?
            GLib::Source.remove(id)
          end
        end
      end

      def cancel_for_item(item)
        store.reminders_by_item(item.id).each { |reminder| cancel(reminder) }
      end

      def send_for(reminder)
        store.item(reminder.item_id).then do |item|
          unless item.nil? || item.checked?
            notify(item)
          end
        end
      end

      # The notification carries the task id, so activating it opens that task
      # rather than just raising the window.
      def notify(item)
        if application.nil?
          LogService.warn("Notification", "no application; dropping #{item.content}")
        else
          Gio::Notification.new(item.content.to_s).tap do |notification|
            notification.body = body_for(item)
            notification.set_icon(Gio::ThemedIcon.new(APP_ID))
            notification.set_priority(:high)
            notification.set_default_action_and_target_value(
              "app.open-item",
              GLib::Variant.new(item.id.to_s),
            )
            notification.add_button_with_target_value(
              _("Mark as Completed"),
              "app.complete-item",
              GLib::Variant.new(item.id.to_s),
            )
            application.send_notification(item.id.to_s, notification)
          end
        end
      end

      def body_for(item)
        [
          item.project&.name,
          item.has_due? ? Datetime.relative(item.due_date) : nil,
        ].compact.reject(&:empty?).join(" · ")
      end

      def withdraw(item_id)
        application&.withdraw_notification(item_id.to_s)
      end

      # The tone a completed task plays, when the preference is on.
      def play_complete_tone
        if Settings.get_boolean("task-complete-tone")
          File.join(Paths.resources, "sounds", "success.ogg").then do |path|
            if File.exist?(path)
              Gtk::MediaFile.for_filename(path).tap(&:play)
            end
          end
        end
      rescue StandardError => error
        LogService.debug("Notification", "tone failed: #{error.message}")
      end
    end
  end
end
