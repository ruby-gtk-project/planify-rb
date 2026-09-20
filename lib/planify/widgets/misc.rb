# frozen_string_literal: true

module Planify
  # src/Widgets/EventRow.vala and EventsList.vala. The system calendar's
  # events, shown above the tasks for a day.
  class EventsList
    def initialize(date = Date.today)
      @date = date
    end

    attr_reader :date

    def build
      @build ||= box.tap do |b|
        b.append(header)
        b.append(listbox)
        refresh
      end
    end

    def date=(value)
      @date = value
      refresh
    end

    def refresh
      while listbox.first_child
        listbox.remove(listbox.first_child)
      end

      events.each { |event| listbox.append(EventRow.new(event).build) }
      box.visible = !events.empty?
    end

    def events
      if Services::CalendarEvents.enabled?
        Services::CalendarEvents.events_on(date)
      else
        []
      end
    end

    def box = @box ||= Gtk::Box.new(:vertical, 3).tap { |b| b.visible = false }

    def header
      @header ||= Gtk::Label.new(_("Events")).tap do |label|
        label.add_css_class("heading")
        label.add_css_class("dim-label")
        label.xalign = 0
        label.margin_bottom = 3
      end
    end

    def listbox
      @listbox ||= Gtk::ListBox.new.tap do |list|
        list.selection_mode = :none
        list.add_css_class("background")
      end
    end
  end

  class EventRow
    def initialize(event)
      @event = event
    end

    attr_reader :event

    def build
      @build ||= row.tap do |r|
        r.child = box

        box.tap do |b|
          b.append(stripe)
          b.append(text_box)

          text_box.append(summary_label)
          text_box.append(detail_label)
        end
      end
    end

    # A colour stripe rather than a dot: the events sit next to tasks, whose
    # left edge already carries a checkbox.
    def stripe
      @stripe ||= Gtk::Box.new(:vertical, 0).tap do |b|
        b.width_request = 3
        Gtk::CssProvider.new.tap do |provider|
          provider.load(
            data: "box { background: #{Palette.hex(event.color)}; border-radius: 2px; }",
          )
          b.style_context.add_provider(provider, Gtk::StyleProvider::PRIORITY_APPLICATION)
        end
      end
    end

    def timing
      if event.all_day
        _("All day")
      else
        "#{event.start_time.strftime(Datetime.time_format)}–" \
          "#{event.end_time.strftime(Datetime.time_format)}"
      end
    end

    def row
      @row ||= Gtk::ListBoxRow.new.tap { |r| r.activatable = false }
    end

    def box
      @box ||= Gtk::Box.new(:horizontal, 9).tap do |b|
        b.margin_start = 9
        b.margin_end = 9
        b.margin_top = 3
        b.margin_bottom = 3
      end
    end

    def text_box = @text_box ||= Gtk::Box.new(:vertical, 0).tap { |b| b.hexpand = true }

    def summary_label
      @summary_label ||= Gtk::Label.new(event.summary.to_s).tap do |label|
        label.xalign = 0
        label.ellipsize = :end
      end
    end

    def detail_label
      @detail_label ||= Gtk::Label.new(
        [timing, event.location, event.source_name].reject { |v| v.to_s.empty? }.join(" · "),
      ).tap do |label|
        label.xalign = 0
        label.add_css_class("caption")
        label.add_css_class("dim-label")
        label.ellipsize = :end
      end
    end
  end

  # src/Widgets/CompletedTaskRow.vala: a completed task, shown with when it
  # was finished rather than when it was due.
  class CompletedTaskRow
    def initialize(window, item)
      @window = window
      @item = item
    end

    attr_reader :window, :item

    def build
      @build ||= row.tap do |r|
        r.child = box

        box.tap do |b|
          b.append(check_button)
          b.append(text_box)

          text_box.append(content_label)
          text_box.append(detail_label)

          check_button.signal_connect("toggled") do
            unless check_button.active?
              Store.instance.complete_item(item, check_button.active?)
            end
          end
        end

        r.add_controller(gesture)
        gesture.signal_connect("released") { window.show_item(item) }
      end
    end

    def row = @row ||= Gtk::ListBoxRow.new

    def box
      @box ||= Gtk::Box.new(:horizontal, 9).tap do |b|
        b.margin_start = 9
        b.margin_end = 9
        b.margin_top = 6
        b.margin_bottom = 6
      end
    end

    def check_button
      @check_button ||= Gtk::CheckButton.new.tap do |check|
        check.active = true
        check.valign = :start
      end
    end

    def text_box = @text_box ||= Gtk::Box.new(:vertical, 0).tap { |b| b.hexpand = true }

    def content_label
      @content_label ||= Gtk::Label.new(item.content.to_s).tap do |label|
        label.xalign = 0
        label.wrap = true
        label.add_css_class("dim-label")
        label.attributes = Pango::AttrList.new.tap do |attributes|
          attributes.insert(Pango::AttrStrikethrough.new(true))
        end
      end
    end

    def detail_label
      @detail_label ||= Gtk::Label.new(detail_text).tap do |label|
        label.xalign = 0
        label.add_css_class("caption")
        label.add_css_class("dim-label")
      end
    end

    def detail_text
      [
        item.project&.name,
        Datetime.relative(Datetime.parse(item.completed_at)),
      ].compact.reject(&:empty?).join(" · ")
    end

    def gesture = @gesture ||= Gtk::GestureClick.new
  end

  # src/Widgets/ItemChangeHistoryRow.vala: one recorded change to a task.
  class ItemChangeHistoryRow
    def initialize(event)
      @event = event
    end

    attr_reader :event

    def build
      @build ||= row.tap do |r|
        r.title = event.title
        r.subtitle = subtitle
        r.add_prefix(Gtk::Image.new(icon_name: icon))
        r.add_suffix(stamp_label)
      end
    end

    def icon
      event.inserted? ? "plus-large-symbolic" : "edit-symbolic"
    end

    # An insert has nothing to compare against, so it shows the value alone.
    def subtitle
      if event.inserted?
        event.describe(event.new_value)
      else
        [event.describe(event.old_value), event.describe(event.new_value)]
          .map { |value| value.to_s.empty? ? _("(empty)") : value }
          .join(" → ")
      end
    end

    def row = @row ||= Adwaita::ActionRow.new

    def stamp_label
      @stamp_label ||= Gtk::Label.new(Datetime.relative(event.event_date)).tap do |label|
        label.add_css_class("caption")
        label.add_css_class("dim-label")
        label.valign = :center
      end
    end
  end

  # src/Dialogs/ProductivityReport/StatCard.vala.
  class StatCard
    def initialize(title, value, subtitle = "")
      @title = title
      @value = value
      @subtitle = subtitle
    end

    def build
      @build ||= box.tap do |b|
        b.append(value_label)
        b.append(title_label)
        b.append(subtitle_label)
      end
    end

    def value=(text)
      value_label.label = text.to_s
    end

    def subtitle=(text)
      subtitle_label.label = text.to_s
      subtitle_label.visible = !text.to_s.empty?
    end

    def box
      @box ||= Gtk::Box.new(:vertical, 3).tap do |b|
        b.add_css_class("card")
        b.add_css_class("stat-card")
        b.margin_start = 6
        b.margin_end = 6
        b.margin_top = 12
        b.margin_bottom = 12
        b.hexpand = true
      end
    end

    def value_label
      @value_label ||= Gtk::Label.new(@value.to_s).tap do |label|
        label.add_css_class("title-1")
      end
    end

    def title_label
      @title_label ||= Gtk::Label.new(@title.to_s).tap do |label|
        label.add_css_class("dim-label")
      end
    end

    def subtitle_label
      @subtitle_label ||= Gtk::Label.new(@subtitle.to_s).tap do |label|
        label.add_css_class("caption")
        label.add_css_class("dim-label")
        label.visible = !@subtitle.to_s.empty?
      end
    end
  end

  # src/Dialogs/ProductivityReport/HeatMap.vala. A year of completions, one
  # cell per day, drawn with Cairo.
  class HeatMap
    CELL = 11
    GAP = 3
    ROWS = 7

    def initialize
      @data = []
    end

    attr_reader :data

    def build
      @build ||= area.tap do |a|
        a.set_draw_func { |_, context, width, height| draw(context, width, height) }
      end
    end

    def data=(values)
      @data = values
      area.set_size_request(columns * (CELL + GAP), ROWS * (CELL + GAP))
      area.queue_draw
    end

    def columns = (data.size / ROWS.to_f).ceil

    def maximum = data.map { |cell| cell[:count] }.max.to_i

    def draw(context, _width, _height)
      Palette.rgba(Theme::DEFAULT_ACCENT).then do |rgba|
        data.each_with_index do |cell, index|
          column = index / ROWS
          row = index % ROWS
          context.set_source_rgba(
            rgba.red,
            rgba.green,
            rgba.blue,
            intensity(cell[:count]),
          )
          context.rectangle(
            column * (CELL + GAP),
            row * (CELL + GAP),
            CELL,
            CELL,
          )
          context.fill
        end
      end
    end

    # Five steps, so a day with one completion is visibly different from an
    # empty one without a single busy day flattening the rest.
    def intensity(count)
      if count.zero?
        0.08
      elsif maximum.zero?
        0.08
      else
        0.2 + (0.8 * (count.to_f / maximum))
      end
    end

    def area
      @area ||= Gtk::DrawingArea.new.tap do |a|
        a.halign = :center
      end
    end
  end

  # src/Widgets/ProductivityMiniWidget.vala: the goal ring in the header.
  class ProductivityMiniWidget
    def build
      @build ||= button.tap do |b|
        b.child = box

        box.append(ring.build)
        box.append(label)

        Services::EventBus.on(:stats_changed, owner: self) { refresh }
        refresh
      end
    end

    def refresh
      Services::Productivity.stats.then do |stats|
        ring.percentage = stats[:daily_progress]
        label.label = "#{stats[:completed_today]}/#{[stats[:daily_goal], 1].max}"
        button.visible = Services::Productivity.goals?
        button.tooltip_text = _("%d day streak") % stats[:streak]
      end
    end

    def button
      @button ||= Gtk::MenuButton.new.tap do |b|
        b.add_css_class("flat")
      end
    end

    def box = @box ||= Gtk::Box.new(:horizontal, 6)

    def ring = @ring ||= CircularProgressBar.new(size: 16)

    def label
      @label ||= Gtk::Label.new("").tap do |l|
        l.add_css_class("caption")
      end
    end
  end

  # src/Widgets/NewVersionPopup.vala: what the sidebar shows when the release
  # feed reports a newer version than the one running.
  class NewVersionPopup
    def initialize(&on_dismiss)
      @on_dismiss = on_dismiss
      @version = nil
    end

    attr_reader :version

    def build
      @build ||= box.tap do |b|
        b.append(title_label)
        b.append(body_label)
        b.append(button_box)

        button_box.append(dismiss_button)
        button_box.append(open_button)

        dismiss_button.signal_connect("clicked") { @on_dismiss&.call(version) }
        open_button.signal_connect("clicked") { open_release }
      end
    end

    def release=(release)
      @version = release[:version]
      title_label.label = _("Planify %s is available") % release[:version]
      body_label.label = release[:summary].to_s
      @url = release[:url]
    end

    def open_release
      Gtk::UriLauncher.new(@url.to_s).launch(nil, nil)
    rescue StandardError => error
      Services::LogService.warn("Release", "could not open: #{error.message}")
    end

    def box
      @box ||= Gtk::Box.new(:vertical, 6).tap do |b|
        b.add_css_class("card")
        b.margin_start = 6
        b.margin_end = 6
        b.margin_bottom = 6
        b.margin_top = 6
      end
    end

    def title_label
      @title_label ||= Gtk::Label.new("").tap do |label|
        label.add_css_class("heading")
        label.xalign = 0
        label.margin_start = 9
        label.margin_top = 9
      end
    end

    def body_label
      @body_label ||= Gtk::Label.new("").tap do |label|
        label.add_css_class("caption")
        label.add_css_class("dim-label")
        label.xalign = 0
        label.wrap = true
        label.margin_start = 9
        label.margin_end = 9
      end
    end

    def button_box
      @button_box ||= Gtk::Box.new(:horizontal, 6).tap do |b|
        b.halign = :end
        b.margin_end = 9
        b.margin_bottom = 9
      end
    end

    def dismiss_button
      @dismiss_button ||= Gtk::Button.new(label: _("Dismiss")).tap do |button|
        button.add_css_class("flat")
      end
    end

    def open_button
      @open_button ||= Gtk::Button.new(label: _("What's New")).tap do |button|
        button.add_css_class("suggested-action")
      end
    end
  end
end
