# frozen_string_literal: true

module Planify
  # src/Widgets/Attachments.vala and AttachmentRow.vala. Files attached to a
  # task are referenced by path, not copied, which is what upstream does and
  # what makes a backup portable.
  class Attachments
    def initialize(item = nil, window = nil)
      @item = item
      @window = window
    end

    attr_reader :item, :window

    def store = Store.instance

    def build
      @build ||= group.tap do |g|
        g.header_suffix = add_button
        add_button.signal_connect("clicked") { choose_file }
        refresh
      end
    end

    def item=(value)
      @item = value
      refresh
    end

    def refresh
      @rows ||= []
      @rows.each { |row| group.remove(row) }
      @rows = attachments.map { |attachment| attachment_row(attachment) }
      @rows.each { |row| group.add(row) }
      if attachments.empty?
        group.description = _("No attachments")
      else
        group.description = nil
      end
    end

    def attachments
      item.nil? ? [] : store.attachments_by_item(item.id)
    end

    def attachment_row(attachment)
      Adwaita::ActionRow.new.tap do |row|
        row.title = attachment.file_name.to_s
        row.subtitle = describe(attachment)
        row.activatable = true
        row.add_prefix(Gtk::Image.new(icon_name: icon_for(attachment)))
        row.add_suffix(remove_button(attachment))
        row.signal_connect("activated") { open(attachment) }
      end
    end

    def describe(attachment)
      [human_size(attachment.file_size), missing?(attachment) ? _("File missing") : nil]
        .compact.join(" · ")
    end

    def missing?(attachment) = !File.exist?(attachment.file_path.to_s)

    UNITS = %w[B KiB MiB GiB].freeze

    # Binary units, matching what the file manager shows next to it.
    def human_size(bytes)
      bytes.to_i.then do |size|
        UNITS.each_with_index.map { |unit, index| [unit, size.to_f / (1024**index)] }
             .find { |(unit, scaled)| scaled < 1024 || unit == UNITS.last }
             .then { |(unit, scaled)| format("%.1f %s", scaled, unit) }
      end
    end

    ICONS = {
      "image" => "image-x-generic-symbolic",
      "video" => "video-x-generic-symbolic",
      "audio" => "audio-x-generic-symbolic",
      "text"  => "text-x-generic-symbolic",
    }.freeze

    def icon_for(attachment)
      ICONS.fetch(attachment.file_type.to_s.split("/").first, "mail-attachment-symbolic")
    end

    def remove_button(attachment)
      Gtk::Button.new(icon_name: "user-trash-symbolic").tap do |button|
        button.add_css_class("flat")
        button.valign = :center
        button.tooltip_text = _("Remove Attachment")
        button.signal_connect("clicked") do
          store.delete_attachment(attachment)
          refresh
        end
      end
    end

    def open(attachment)
      Gtk::FileLauncher.new(Gio::File.new_for_path(attachment.file_path.to_s))
                       .launch(window&.window, nil)
    rescue StandardError => error
      Services::LogService.warn("Attachments", "open failed: #{error.message}")
    end

    # Gtk::FileDialog is async and raises when the user cancels, so the
    # rescue is the cancel path rather than an error path.
    def choose_file
      Gtk::FileDialog.new.tap do |dialog|
        dialog.title = _("Attach a File")
        dialog.open(window&.window, nil) do |_, result|
          begin
            attach(dialog.open_finish(result))
          rescue StandardError
            nil
          end
        end
      end
    end

    def attach(file)
      unless file.nil? || item.nil?
        store.insert_attachment(
          Attachment.new(
            item_id:   item.id,
            file_name: File.basename(file.path),
            file_path: file.path,
            file_size: File.size(file.path).to_s,
            file_type: content_type(file),
          ),
        )
        refresh
      end
    end

    def content_type(file)
      file.query_info("standard::content-type", :none, nil).content_type.to_s
    rescue StandardError
      "application/octet-stream"
    end

    def group
      @group ||= Adwaita::PreferencesGroup.new.tap do |g|
        g.title = _("Attachments")
      end
    end

    def add_button
      @add_button ||= Gtk::Button.new(icon_name: "plus-large-symbolic").tap do |button|
        button.add_css_class("flat")
        button.tooltip_text = _("Attach a File")
      end
    end
  end

  # src/Widgets/SubItems.vala: a task's subtasks, with their own add row.
  class SubItems
    def initialize(window, item = nil)
      @window = window
      @item = item
      @rows = {}
    end

    attr_reader :window, :item

    def store = Store.instance

    def build
      @build ||= box.tap do |b|
        b.append(header)
        b.append(listbox)
        b.append(add_row)

        header.tap do |h|
          h.append(title_label)
          h.append(progress_label)
        end

        add_row.tap do |row|
          row.append(add_entry)
          add_entry.signal_connect("activate") { submit }
        end

        refresh
      end
    end

    def item=(value)
      @item = value
      refresh
    end

    def subitems = item.nil? ? [] : store.subitems_of(item.id)

    def refresh
      @rows = {}

      while listbox.first_child
        listbox.remove(listbox.first_child)
      end

      subitems.each do |subitem|
        ItemRow.new(window, subitem, depth: 0).build.tap do |row|
          @rows[subitem.id] = row
          listbox.append(row)
        end
      end

      progress_label.label = "#{subitems.count(&:checked?)}/#{subitems.size}"
      progress_label.visible = !subitems.empty?
      box.visible = !item.nil?
    end

    def submit
      add_entry.text.strip.then do |content|
        unless content.empty? || item.nil?
          store.insert_item(
            Item.new(
              content:     content,
              project_id:  item.project_id,
              section_id:  item.section_id,
              parent_id:   item.id,
              child_order: subitems.size,
            ),
          )
          add_entry.text = ""
          refresh
        end
      end
    end

    def box = @box ||= Gtk::Box.new(:vertical, 6)

    def header = @header ||= Gtk::Box.new(:horizontal, 6)

    def title_label
      @title_label ||= Gtk::Label.new(_("Sub-tasks")).tap do |label|
        label.add_css_class("heading")
        label.xalign = 0
        label.hexpand = true
      end
    end

    def progress_label
      @progress_label ||= Gtk::Label.new("").tap do |label|
        label.add_css_class("dim-label")
        label.add_css_class("caption")
        label.visible = false
      end
    end

    def listbox
      @listbox ||= Gtk::ListBox.new.tap do |list|
        list.selection_mode = :none
        list.add_css_class("background")
      end
    end

    def add_row = @add_row ||= Gtk::Box.new(:horizontal, 6)

    def add_entry
      @add_entry ||= Gtk::Entry.new.tap do |entry|
        entry.placeholder_text = _("Add a sub-task")
        entry.hexpand = true
      end
    end
  end
end
