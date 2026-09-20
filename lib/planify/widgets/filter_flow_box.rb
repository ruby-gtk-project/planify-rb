# frozen_string_literal: true

module Planify
  # src/Widgets/FilterFlowBox.vala with FilterPaneRow and FilterPaneChild. The
  # sidebar filters render either as a grid of tiles or as a list of rows,
  # which `filters-list-view` chooses between, and `views-order-visible` says
  # which of them appear and in what order.
  class FilterFlowBox
    FILTERS = [
      {
        key:   "inbox",
        title: -> { _("Inbox") },
        icon:  "mailbox-symbolic",
        color: "#3584e4",
      },
      {
        key:   "today",
        title: -> { _("Today") },
        icon:  "star-outline-thick-symbolic",
        color: "#33d17a",
      },
      {
        key:   "scheduled",
        title: -> { _("Scheduled") },
        icon:  "month-symbolic",
        color: "#9141ac",
      },
      {
        key:   "labels",
        title: -> { _("Labels") },
        icon:  "tag-outline-symbolic",
        color: "#ff7800",
      },
      {
        key:   "pinboard",
        title: -> { _("Pinboard") },
        icon:  "pin-symbolic",
        color: "#e01b24",
      },
      {
        key:   "completed",
        title: -> { _("Completed") },
        icon:  "check-round-outline-symbolic",
        color: "#26a269",
      },
    ].freeze

    def initialize(&on_activate)
      @on_activate = on_activate
      @tiles = {}
      @counts = {}
    end

    def store = Store.instance

    def build
      @build ||= stack.tap do |s|
        s.add_named(flowbox, "grid")
        s.add_named(listbox, "list")

        flowbox.signal_connect("child-activated") do |_, child|
          visible_filters[child.index].then { |filter| @on_activate&.call(filter[:key]) }
        end

        listbox.signal_connect("row-activated") do |_, row|
          visible_filters[row.index].then { |filter| @on_activate&.call(filter[:key]) }
        end

        rebuild
      end
    end

    # The setting stores the visible keys in display order; an empty value
    # means "all of them, as shipped".
    def visible_filters
      Settings.settings.get_strv("views-order-visible").to_a.then do |order|
        if order.empty?
          FILTERS
        else
          order.filter_map { |key| FILTERS.find { |filter| filter[:key] == key } }
        end
      end
    rescue StandardError
      FILTERS
    end

    def rebuild
      @tiles = {}
      @counts = {}

      clear(flowbox)
      clear(listbox)

      visible_filters.each do |filter|
        flowbox.append(tile(filter))
        listbox.append(row(filter))
      end

      if Settings.get_boolean("filters-list-view")
        stack.visible_child_name = "list"
      else
        stack.visible_child_name = "grid"
      end
      refresh_counts
    end

    def clear(container)
      while container.first_child
        container.remove(container.first_child)
      end
    end

    # A tile is a coloured icon over a name and a count; upstream's grid.
    def tile(filter)
      Gtk::Box.new(:vertical, 3).tap do |box|
        box.add_css_class("filter-tile")
        box.add_css_class("card")
        box.margin_top = 3
        box.margin_bottom = 3
        box.append(tile_icon(filter))
        box.append(Gtk::Label.new(filter[:title].call).tap { |l| l.add_css_class("caption") })
        box.append(count_label(filter, :grid))
      end
    end

    def tile_icon(filter)
      Gtk::Image.new(icon_name: filter[:icon]).tap do |image|
        image.pixel_size = 20
        image.margin_top = 9
        tint(image, filter[:color])
      end
    end

    def row(filter)
      Gtk::ListBoxRow.new.tap do |r|
        r.child = Gtk::Box.new(:horizontal, 9).tap do |box|
          box.margin_start = 6
          box.margin_end = 6
          box.margin_top = 6
          box.margin_bottom = 6
          box.append(row_icon(filter))
          box.append(Gtk::Label.new(filter[:title].call).tap { |l| l.xalign = 0 })
          box.append(count_label(filter, :list))
        end

        @tiles[filter[:key]] = r
      end
    end

    def row_icon(filter)
      Gtk::Image.new(icon_name: filter[:icon]).tap do |image|
        image.pixel_size = 16
        tint(image, filter[:color])
      end
    end

    def tint(widget, color)
      Gtk::CssProvider.new.tap do |provider|
        provider.load(data: "image { color: #{color}; }")
        widget.style_context.add_provider(provider, Gtk::StyleProvider::PRIORITY_APPLICATION)
      end
    end

    def count_label(filter, which)
      Gtk::Label.new("").tap do |label|
        label.add_css_class("caption")
        label.add_css_class("dim-label")
        label.hexpand = which == :list
        if which == :list
          label.xalign = 1
        else
          label.xalign = 0.5
        end
        (@counts[filter[:key]] ||= []) << label
      end
    end

    COUNTS = {
      "inbox"     => lambda { |store|
        store.inbox_project.then do |project|
          project.nil? ? 0 : store.items_by_project(project.id).count { |i| !i.checked? }
        end
      },
      "today"     => ->(store) { store.today_items.size },
      "scheduled" => ->(store) { store.scheduled_items.size },
      "labels"    => ->(store) { store.labels.size },
      "pinboard"  => ->(store) { store.pinboard_items.size },
      "completed" => ->(store) { store.completed_items.size },
    }.freeze

    def refresh_counts
      show = Settings.get_boolean("show-tasks-count")

      @counts.each do |key, labels|
        labels.each do |label|
          if show
            label.label = COUNTS.fetch(key).call(store).to_s
          else
            label.label = ""
          end
        end
      end
    end

    def select(key)
      @tiles.each_value { |tile| tile.remove_css_class("selected") }
      @tiles[key]&.add_css_class("selected")
    end

    def stack
      @stack ||= Gtk::Stack.new.tap do |s|
        s.hexpand = true
      end
    end

    def flowbox
      @flowbox ||= Gtk::FlowBox.new.tap do |box|
        box.max_children_per_line = 2
        box.min_children_per_line = 2
        box.homogeneous = true
        box.selection_mode = :none
        box.row_spacing = 6
        box.column_spacing = 6
      end
    end

    def listbox
      @listbox ||= Gtk::ListBox.new.tap do |list|
        list.add_css_class("navigation-sidebar")
        list.selection_mode = :none
      end
    end
  end

  # src/Widgets/PinnedItemsBox.vala: the pinned tasks a project view shows
  # above its sections.
  class PinnedItemsBox
    def initialize(window, project)
      @window = window
      @project = project
    end

    attr_reader :window, :project

    def store = Store.instance

    def build
      @build ||= box.tap do |b|
        b.append(header)
        b.append(listbox)
        refresh
      end
    end

    def items
      store.items_by_project(project.id).select { |item| item.pinned? && !item.checked? }
    end

    def refresh
      while listbox.first_child
        listbox.remove(listbox.first_child)
      end

      items.each { |item| listbox.append(ItemRow.new(window, item).build) }
      box.visible = !items.empty?
    end

    def box
      @box ||= Gtk::Box.new(:vertical, 3).tap do |b|
        b.visible = false
        b.margin_bottom = 12
      end
    end

    def header
      @header ||= Gtk::Box.new(:horizontal, 6).tap do |b|
        b.append(Gtk::Image.new(icon_name: "pin-symbolic"))
        b.append(
          Gtk::Label.new(_("Pinned")).tap do |label|
                    label.add_css_class("heading")
                    label.xalign = 0
                  end,
        )
      end
    end

    def listbox
      @listbox ||= Gtk::ListBox.new.tap do |list|
        list.selection_mode = :none
        list.add_css_class("background")
      end
    end
  end
end
