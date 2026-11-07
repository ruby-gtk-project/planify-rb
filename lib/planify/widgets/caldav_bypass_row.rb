# frozen_string_literal: true

module Planify
  # Widgets/BypassResolveSwitchRow.vala. A switch row offered in the CalDAV
  # setup form; the warning dialog is what stands between a casual click and
  # actually disabling the resolve process, since it changes how discovery
  # talks to the server.
  class BypassResolveSwitchRow
    def initialize(dialog)
      @dialog = dialog
    end

    attr_reader :dialog

    def build
      @build ||= row.tap do |r|
        r.title = _("Bypass Location Resolve")
        r.subtitle = _("Workaround for CalDAV connection issues with connections using non-default ports")
        r.add_suffix(toggle)
        r.activatable_widget = toggle

        toggle.signal_connect("state-set") { |_, state| state_set(state) }
      end
    end

    def active? = toggle.active?

    def active=(value)
      toggle.active = value
    end

    # Returning true from state-set holds the switch at its old visual
    # position until the alert dialog settles it, so a stray tap cannot turn
    # this on without the warning being read.
    def state_set(state)
      if state
        confirm
        true
      else
        false
      end
    end

    def confirm
      Adwaita::AlertDialog.new(
        _("Warning"),
        _("This will disable the CalDAV resolve process.\nProceed at your own risk"),
      ).tap do |alert|
        alert.add_response("cancel", _("Cancel"))
        alert.add_response("accept", _("Continue Anyway"))
        alert.set_response_appearance("accept", Adwaita::ResponseAppearance::DESTRUCTIVE)
        alert.signal_connect("response") do |_, response|
          toggle.active = response == "accept"
        end
        alert.present(dialog)
      end
    end

    def row = @row ||= Adwaita::ActionRow.new

    def toggle
      @toggle ||= Gtk::Switch.new.tap do |s|
        s.valign = :center
        s.halign = :end
      end
    end
  end
end
