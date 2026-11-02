# frozen_string_literal: true

module Planify
  # core/Layouts/HeaderItem.vala. A titled section with a list under it: the
  # sidebar's Favorites and account groups, the preferences pages' groups, the
  # reminder list. The whole thing collapses behind one revealer, so a group
  # with nothing in it folds away instead of leaving a stranded heading, and
  # an empty list shows a dimmed message in its place.
  class HeaderItem
    def initialize(header_title = nil, subheader_title: "", placeholder_message: "")
      @header_title = header_title
      @subheader_title = subheader_title.to_s
      @placeholder_message = placeholder_message.to_s
    end

    attr_reader :header_title, :subheader_title, :placeholder_message

    def build
      @build ||= bin.tap do |b|
        b.child = content_revealer

        content_revealer.child = content_box

        content_box.tap do |content|
          content.append(header_box)
          content.append(separator_revealer)
          content.append(listbox)
          content.append(drop_target_revealer)

          header_box.tap do |header|
            header.append(header_label_box)
            header.append(action_box)

            header_label_box.tap do |labels|
              labels.append(header_label)
              labels.append(subheader_revealer)

              subheader_revealer.child = subheader_label
            end
          end

          separator_revealer.child = separator

          drop_target_revealer.child = drop_target

          listbox.tap do |list|
            list.set_placeholder(placeholder)
            list.signal_connect("row-activated") { |_, row| @on_row_activated&.call(row) }
          end
        end

        self.header_title = header_title
        self.subheader_title = subheader_title
        self.placeholder_message = placeholder_message
      end
    end

    # The listbox itself, for callers that need to sort, filter or select in
    # it; upstream exposes it under the name `items`.
    def items = listbox

    def on_row_activated(&block)
      @on_row_activated = block
    end

    # --- titles -----------------------------------------------------------

    def header_title=(value)
      @header_title = value
      header_label.label = value.to_s
      header_label.visible = !value.nil?
    end

    def subheader_title=(value)
      @subheader_title = value.to_s
      subheader_label.label = @subheader_title
      subheader_revealer.reveal_child = !@subheader_title.empty?
    end

    def placeholder_message=(value)
      @placeholder_message = value.to_s
      placeholder_label.label = @placeholder_message
    end

    # --- state ------------------------------------------------------------

    def reveal = content_revealer.reveal_child?

    def reveal=(value)
      content_revealer.reveal_child = value
    end

    def show_separator=(value)
      separator_revealer.reveal_child = value
    end

    def show_drop_target=(value)
      drop_target_revealer.reveal_child = value
    end

    # A group folds away entirely once it is empty, which is what keeps the
    # sidebar from showing a Favorites heading over nothing.
    def check_visibility(size)
      content_revealer.reveal_child = size.to_i.positive?
    end

    # --- styling switches upstream exposes as properties -------------------

    def card=(value)
      if value
        listbox.css_classes = ["boxed-list"]
        set_listbox_margins(top: 12, bottom: 3, start: 3, end: 3)
      else
        listbox.css_classes = []
        set_listbox_margins
      end
    end

    def separator_space=(value)
      if value
        listbox.add_css_class("listbox-separator-3")
      end
    end

    def separator_lines=(value)
      if value
        listbox.add_css_class("separator-lines")
      end
    end

    def listbox_no_margin=(value)
      if value
        set_listbox_margins
      end
    end

    def listbox_margin_top=(value)
      listbox.margin_top = value
    end

    def set_listbox_margins(top: 0, bottom: 0, start: 0, **options)
      listbox.margin_top = top
      listbox.margin_bottom = bottom
      listbox.margin_start = start
      listbox.margin_end = options.fetch(:end, 0)
    end

    # --- children ---------------------------------------------------------

    def add_child(widget)
      listbox.append(widget)
    end

    def insert_child(widget, position)
      listbox.insert(widget, position)
    end

    def remove_child(widget)
      listbox.remove(widget)
    end

    # Buttons that sit at the right end of the heading — add, sync, menu.
    def add_widget_end(widget)
      action_box.append(widget)
    end

    def children
      [].tap do |found|
        child = listbox.first_child
        while child
          found << child
          child = child.next_sibling
        end
      end
    end

    def clear
      while listbox.first_child
        listbox.remove(listbox.first_child)
      end
    end

    def set_sort_func(&block)
      listbox.set_sort_func(&block)
    end

    def set_filter_func(&block)
      listbox.set_filter_func(&block)
    end

    def invalidate_filter
      listbox.invalidate_filter
    end

    # Upstream also drops the sort and filter closures here, to break the
    # reference cycle they hold onto the rows; Ruby's GC needs no such help,
    # so emptying the list is the whole of it.
    def clean_up
      clear
    end

    # --- widgets ----------------------------------------------------------

    def bin = @bin ||= Adwaita::Bin.new

    def content_revealer
      @content_revealer ||= Gtk::Revealer.new.tap do |revealer|
        revealer.transition_type = :slide_down
      end
    end

    def content_box
      @content_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.hexpand = true
        box.margin_top = 3
      end
    end

    def header_box
      @header_box ||= Gtk::Box.new(:horizontal, 6).tap do |box|
        box.hexpand = true
        box.margin_start = 6
        box.margin_end = 6
      end
    end

    def header_label_box
      @header_label_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.valign = :center
      end
    end

    def header_label
      @header_label ||= Gtk::Label.new.tap do |label|
        label.halign = :start
        label.ellipsize = :end
        label.add_css_class("h4")
        label.add_css_class("heading")
      end
    end

    def subheader_label
      @subheader_label ||= Gtk::Label.new.tap do |label|
        label.halign = :start
        label.ellipsize = :end
        label.add_css_class("caption")
        label.add_css_class("dim-label")
      end
    end

    def subheader_revealer
      @subheader_revealer ||= Gtk::Revealer.new.tap do |revealer|
        revealer.transition_type = :slide_down
      end
    end

    def action_box
      @action_box ||= Gtk::Box.new(:horizontal, 6).tap do |box|
        box.hexpand = true
        box.halign = :end
      end
    end

    def listbox
      @listbox ||= Gtk::ListBox.new.tap do |list|
        list.hexpand = true
        list.margin_top = 6
        list.add_css_class("bg-transparent")
      end
    end

    def separator
      @separator ||= Gtk::Separator.new(:horizontal).tap do |sep|
        sep.margin_top = 6
        sep.margin_start = 3
        sep.margin_bottom = 3
      end
    end

    def separator_revealer
      @separator_revealer ||= Gtk::Revealer.new.tap do |revealer|
        revealer.transition_type = :slide_down
      end
    end

    # The strip under the list that a dragged row can be dropped onto to land
    # at the end of the group.
    def drop_target
      @drop_target ||= Gtk::Grid.new.tap do |grid|
        grid.height_request = 27
        grid.margin_top = 3
        grid.add_css_class("drop-target")
      end
    end

    def drop_target_revealer
      @drop_target_revealer ||= Gtk::Revealer.new.tap do |revealer|
        revealer.transition_type = :slide_up
        revealer.transition_duration = 150
      end
    end

    def placeholder
      @placeholder ||= Adwaita::Bin.new.tap do |placeholder_bin|
        placeholder_bin.margin_top = 12
        placeholder_bin.margin_bottom = 12
        placeholder_bin.margin_start = 12
        placeholder_bin.margin_end = 12
        placeholder_bin.child = placeholder_label
      end
    end

    def placeholder_label
      @placeholder_label ||= Gtk::Label.new.tap do |label|
        label.wrap = true
        label.justify = :center
        label.add_css_class("dim-label")
        label.add_css_class("caption")
      end
    end
  end
end
