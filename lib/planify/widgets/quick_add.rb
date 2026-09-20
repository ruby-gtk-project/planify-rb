# frozen_string_literal: true

module Planify
  # core/QuickAddCore.vala: the one-line task entry with its property buttons.
  # The magic upstream is the natural-language parsing — "buy milk tomorrow
  # p1 @home" — which is reproduced here for dates, priorities and labels.
  class QuickAdd
    def initialize(window, project: nil, section: nil)
      @window = window
      @project = project || Store.instance.inbox_project
      @section = section
      @due = nil
      @repeat = "none"
      @labels = []
      @priority = Settings.default_priority
    end

    attr_reader :window

    def present(parent)
      dialog.tap do |d|
        d.child = toolbar

        toolbar.tap do |view|
          view.add_top_bar(header)
          view.content = content_box

          content_box.tap do |box|
            box.append(content_entry)
            box.append(description_entry)
            box.append(buttons_box)
            box.append(create_more_row)

            content_entry.tap do |entry|
              entry.signal_connect("activate") { submit }
              entry.signal_connect("changed") { parse_smart_input }
            end

            buttons_box.tap do |buttons|
              buttons.append(project_button)
              buttons.append(due_button)
              buttons.append(label_button)
              buttons.append(priority_picker.build)
              buttons.append(add_button)

              project_button.popover = project_popover
              project_popover.child = project_list

              due_button.popover = due_popover
              due_popover.child = date_picker.build

              label_button.popover = label_popover
              label_popover.child = label_picker.build

              add_button.signal_connect("clicked") { submit }
            end
          end

          header.title_widget = Adwaita::WindowTitle.new(_("Add To-Do"), project_title)
        end

        refresh_buttons
        d.present(parent)
        content_entry.grab_focus
      end
    end

    def store = Store.instance

    def project_title = [@project&.name, @section&.name].compact.join(" / ")

    # --- smart input ----------------------------------------------------

    DATE_WORDS = {
      /\btoday\b/i     => 0,
      /\btomorrow\b/i  => 1,
      /\bnext week\b/i => 7,
    }.freeze

    PRIORITY_WORDS = {
      /\bp1\b/i => Item::PRIORITY_1,
      /\bp2\b/i => Item::PRIORITY_2,
      /\bp3\b/i => Item::PRIORITY_3,
      /\bp4\b/i => Item::PRIORITY_4,
    }.freeze

    # Upstream highlights the recognised tokens in place; here they are simply
    # read out of the text and reflected in the property buttons, and stripped
    # when the task is created.
    def parse_smart_input
      if Settings.get_boolean("smart-date-recognition")
        content_entry.text.then do |text|
          DATE_WORDS.each do |pattern, offset|
            if text.match?(pattern)
              @due = Datetime.strip_time(Time.now + (offset * 86_400))
            end
          end

          PRIORITY_WORDS.each do |pattern, priority|
            if text.match?(pattern)
              @priority = priority
            end
          end

          @labels = text.scan(/@(\S+)/).flatten.filter_map do |name|
            store.label_by_name(name)&.id
          end

          refresh_buttons
        end
      end
    end

    def strip_tokens(text)
      (DATE_WORDS.keys + PRIORITY_WORDS.keys + [/@\S+/])
        .reduce(text) { |stripped, pattern| stripped.gsub(pattern, "") }
        .squeeze(" ")
        .strip
    end

    # --- submit ---------------------------------------------------------

    def submit
      content_entry.text.strip.then do |raw|
        unless raw.empty?
          create(strip_tokens(raw))
        end
      end
    end

    def create(content)
      Item.new(
        content:     content,
        description: description_entry.text,
        project_id:  @project&.id.to_s,
        section_id:  @section&.id.to_s,
        priority:    priority_picker.priority,
        child_order: store.next_child_order(@project&.id.to_s, @section&.id.to_s),
      ).tap do |item|
        item.due_date = @due
        item.label_ids = @labels
        apply_recurrency(item)
        store.insert_item(item)
        window.toast(_("Task added"))
        finish
      end
    end

    def apply_recurrency(item)
      unless @repeat == "none" || @due.nil?
        item.due = JSON.generate(
          item.due_hash.merge(
            "recurrency_type" => @repeat,
            "is_recurring"    => true,
          ),
        )
      end
    end

    def finish
      if Settings.get_boolean("quick-add-create-more") || create_more_row.active?
        reset
      else
        dialog.close
      end
    end

    def reset
      content_entry.text = ""
      description_entry.text = ""

      unless Settings.get_boolean("quick-add-keep-properties")
        @due = nil
        @labels = []
        @repeat = "none"
        priority_picker.priority = Settings.default_priority
      end

      refresh_buttons
      content_entry.grab_focus
    end

    def refresh_buttons
      if @due.nil?
        due_button.label = _("Schedule")
      else
        due_button.label = Datetime.relative(@due)
      end
      if @labels.empty?
        label_button.label = _("Labels")
      else
        label_button.label = @labels.size.to_s
      end
      if @project.nil?
        project_button.label = _("Inbox")
      else
        project_button.label = @project.name
      end
      priority_picker.priority = @priority
      label_picker.selected = @labels
    end

    # --- widgets --------------------------------------------------------

    def dialog
      @dialog ||= Adwaita::Dialog.new.tap do |d|
        d.title = _("Add To-Do")
        d.content_width = 480
      end
    end

    def toolbar = @toolbar ||= Adwaita::ToolbarView.new

    def header
      @header ||= Adwaita::HeaderBar.new.tap do |h|
        h.add_css_class("flat")
      end
    end

    def content_box
      @content_box ||= Gtk::Box.new(:vertical, 12).tap do |box|
        box.margin_start = 12
        box.margin_end = 12
        box.margin_top = 12
        box.margin_bottom = 12
      end
    end

    def content_entry
      @content_entry ||= Gtk::Entry.new.tap do |entry|
        entry.placeholder_text = _("To-do name")
        entry.add_css_class("title-3")
      end
    end

    def description_entry
      @description_entry ||= Gtk::Entry.new.tap do |entry|
        entry.placeholder_text = _("Description")
      end
    end

    def buttons_box = @buttons_box ||= Gtk::Box.new(:horizontal, 6)

    def project_button
      @project_button ||= Gtk::MenuButton.new.tap do |button|
        button.add_css_class("flat")
        button.tooltip_text = _("Project")
      end
    end

    def project_popover = @project_popover ||= Gtk::Popover.new

    def project_list
      @project_list ||= Gtk::ListBox.new.tap do |list|
        list.selection_mode = :none
        list.add_css_class("menu-listbox")

        store.projects.reject(&:archived?).each do |project|
          list.append(project_option(project))
        end

        list.signal_connect("row-activated") do |_, row|
          @project = store.projects.reject(&:archived?)[row.index]
          @section = nil
          project_popover.popdown
          refresh_buttons
        end
      end
    end

    def project_option(project)
      Gtk::ListBoxRow.new.tap do |row|
        row.child = Gtk::Label.new(project.name).tap do |label|
          label.xalign = 0
          label.margin_start = 9
          label.margin_end = 9
          label.margin_top = 6
          label.margin_bottom = 6
        end
      end
    end

    def due_button
      @due_button ||= Gtk::MenuButton.new.tap do |button|
        button.add_css_class("flat")
        button.tooltip_text = _("Schedule")
      end
    end

    def due_popover = @due_popover ||= Gtk::Popover.new

    def date_picker
      @date_picker ||= DateTimePicker.new do |time, repeat|
        @due = time
        @repeat = repeat
        refresh_buttons
      end
    end

    def label_button
      @label_button ||= Gtk::MenuButton.new.tap do |button|
        button.add_css_class("flat")
        button.tooltip_text = _("Labels")
      end
    end

    def label_popover = @label_popover ||= Gtk::Popover.new

    def label_picker
      @label_picker ||= LabelPicker.new do |ids|
        @labels = ids
        refresh_buttons
      end
    end

    def priority_picker
      @priority_picker ||= PriorityPicker.new(@priority) { |priority| @priority = priority }
    end

    def add_button
      @add_button ||= Gtk::Button.new(label: _("Add To-Do")).tap do |button|
        button.add_css_class("suggested-action")
        button.hexpand = true
      end
    end

    def create_more_row
      @create_more_row ||= Adwaita::SwitchRow.new.tap do |row|
        row.title = _("Create More")
        row.subtitle = _("Keep this dialog open after adding a task")
        row.active = Settings.get_boolean("quick-add-create-more")
      end
    end
  end
end
