# frozen_string_literal: true

module Planify
  # src/Widgets/ReorderChild.vala. Wraps the content of a list row so the row
  # can be dragged to a new position: the wrapper reveals a drop strip above or
  # below itself depending on which half of the row the pointer is over, and on
  # the drop it moves the dragged row into that slot and tells the caller so the
  # new order can be written down.
  #
  # The drag source and the drop target go on the row, not on this wrapper, so
  # the whole row is grabbable rather than just the part the content covers.
  class ReorderChild
    TRANSITION_DURATION = 200

    # Gdk::ContentProvider carries GObject values only, so the wrapper itself
    # cannot ride along in the drop the way it does in Vala. What travels is a
    # string identifying the dragged row, and the drop finds that row among its
    # own siblings. The row's widget name is it, which is also what the caller
    # reads the new order back by.
    def initialize(widget, row, token: nil, &on_drop_end)
      @widget = widget
      @row = row
      @token = token
      @on_drop_end = on_drop_end
      @dragging = false
    end

    attr_reader :widget, :row

    def token = (@token || row.name).to_s

    def build
      @build ||= bin.tap do |b|
        b.child = main_revealer

        main_revealer.child = main_box

        main_box.tap do |box|
          box.append(motion_top_revealer)
          box.append(widget)
          box.append(motion_bottom_revealer)

          motion_top_revealer.child = motion_top
          motion_bottom_revealer.child = motion_bottom
        end
      end
    end

    def on_drag_event(&block)
      @on_drag_event = block
    end

    def reveal_child = main_revealer.reveal_child?

    def reveal_child=(value)
      main_revealer.reveal_child = value
    end

    def dragging? = @dragging == true

    # --- drag and drop ----------------------------------------------------

    def build_drag_and_drop
      row.add_controller(drag_source)
      row.add_controller(drop_target)
      row.add_controller(drop_motion)

      drag_source.tap do |source|
        source.actions = Gdk::DragAction::MOVE
        source.signal_connect("prepare") { |_, _, _| Gdk::ContentProvider.new(token) }
        source.signal_connect("drag-begin") do |_, _drag|
          source.set_icon(Gtk::WidgetPaintable.new(widget), 0, 0)
          drag_begin
        end
        source.signal_connect("drag-end") { drag_end }
        source.signal_connect("drag-cancel") do
          drag_end
          false
        end
      end

      drop_target.signal_connect("drop") do |_, value, _x, y|
        accept_drop(value, y >= (row.height / 2.0))
      end

      drop_motion.tap do |motion|
        motion.signal_connect("enter") do |_, _x, y|
          draw_motion_widgets
          track_motion(y)
        end
        motion.signal_connect("motion") { |_, _x, y| track_motion(y) }
        motion.signal_connect("leave") { hide_motion_widgets }
      end
    end

    # Which half of the row the pointer is in says which side of it the dragged
    # row would land on, and only the matching strip is opened.
    def track_motion(pointer_y)
      (pointer_y < (row.height / 2.0)).then do |top_half|
        reveal_motion(motion_top_revealer, motion_top, top_half)
        reveal_motion(motion_bottom_revealer, motion_bottom, !top_half)
      end
    end

    def reveal_motion(revealer, target, active)
      unless revealer.reveal_child? == active
        revealer.reveal_child = active
        if active
          target.add_css_class("drop-area")
        else
          target.remove_css_class("drop-area")
        end
      end
    end

    def hide_motion_widgets
      motion_top_revealer.reveal_child = false
      motion_bottom_revealer.reveal_child = false
      motion_top.remove_css_class("drop-area")
      motion_bottom.remove_css_class("drop-area")
    end

    def accept_drop(value, bottom)
      drag_end
      hide_motion_widgets

      row.parent.then do |listbox|
        find_row(listbox, value.to_s).then do |picked|
          if picked.nil? || picked == row
            false
          else
            move(listbox, picked, bottom)
          end
        end
      end
    end

    # The dragged row comes out of the list and goes back in at this row's
    # index, or just after it when the pointer was in the bottom half. Taking
    # it out first is what makes the index arithmetic come out right: a row
    # dragged downwards has already shifted the target up by one.
    def move(listbox, picked, bottom)
      picked_index = picked.index
      listbox.remove(picked)

      position = row.index
      if bottom
        position += 1
      end
      if picked_index < position
        position -= 1
      end

      listbox.insert(picked, position)
      @on_drop_end&.call(listbox)
      true
    end

    def find_row(listbox, id)
      child = listbox.first_child
      while child && child.name.to_s != id
        child = child.next_sibling
      end
      child
    end

    def drag_begin
      widget.add_css_class("drop-begin")
      @dragging = true
      @on_drag_event&.call(true)
      main_revealer.reveal_child = false
    end

    def drag_end
      widget.remove_css_class("drop-begin")
      @dragging = false
      @on_drag_event&.call(false)
      main_revealer.reveal_child = true
    end

    # The drop strips have to be as tall as the row they would displace, or the
    # list jumps as one opens.
    def draw_motion_widgets
      [row.height, 32].max.then do |height|
        motion_top.height_request = height
        motion_bottom.height_request = height
      end
    end

    # --- widgets ----------------------------------------------------------

    def bin = @bin ||= Adwaita::Bin.new

    def main_box = @main_box ||= Gtk::Box.new(:vertical, 0)

    def main_revealer
      @main_revealer ||= Gtk::Revealer.new.tap do |revealer|
        revealer.transition_type = :slide_down
        revealer.reveal_child = true
      end
    end

    def motion_top
      @motion_top ||= Adwaita::Bin.new.tap { |target| target.add_css_class("drop-target") }
    end

    def motion_bottom
      @motion_bottom ||= Adwaita::Bin.new.tap { |target| target.add_css_class("drop-target") }
    end

    def motion_top_revealer
      @motion_top_revealer ||= Gtk::Revealer.new.tap do |revealer|
        revealer.transition_type = :slide_down
        revealer.transition_duration = TRANSITION_DURATION
      end
    end

    def motion_bottom_revealer
      @motion_bottom_revealer ||= Gtk::Revealer.new.tap do |revealer|
        revealer.transition_type = :slide_down
        revealer.transition_duration = TRANSITION_DURATION
      end
    end

    def drag_source = @drag_source ||= Gtk::DragSource.new

    def drop_target
      @drop_target ||= Gtk::DropTarget.new(GLib::Type["gchararray"], Gdk::DragAction::MOVE)
    end

    def drop_motion = @drop_motion ||= Gtk::DropControllerMotion.new
  end
end
