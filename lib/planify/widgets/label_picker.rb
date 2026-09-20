# frozen_string_literal: true

module Planify
  # core/Widgets/LabelPicker: a searchable, checkable list of labels, plus a
  # row that creates a label from whatever is typed when nothing matches.
  class LabelPicker
    def initialize(selected = [], &on_change)
      @selected = selected.dup
      @on_change = on_change
      @checks = {}
    end

    attr_reader :selected

    def build
      @build ||= box.tap do |b|
        b.append(search_entry)
        b.append(scrolled)

        scrolled.child = listbox

        search_entry.signal_connect("search-changed") { listbox.invalidate_filter }

        listbox.tap do |list|
          list.set_filter_func { |row| matches?(row) }
          list.signal_connect("row-activated") { |_, row| toggle(row) }
        end

        reload
      end
    end

    def selected=(ids)
      @selected = ids.dup
      @checks.each { |label_id, check| check.active = @selected.include?(label_id) }
    end

    def reload
      @checks = {}
      while listbox.first_child
        listbox.remove(listbox.first_child)
      end

      Store.instance.labels.sort_by { |label| label.item_order.to_i }.each do |label|
        listbox.append(label_row(label))
      end
    end

    def label_row(label)
      Gtk::ListBoxRow.new.tap do |row|
        row.child = Gtk::Box.new(:horizontal, 9).tap do |b|
          b.margin_start = 9
          b.margin_end = 9
          b.margin_top = 3
          b.margin_bottom = 3
          b.append(dot(label))
          b.append(Gtk::Label.new(label.name).tap { |l| l.xalign = 0; l.hexpand = true })
          b.append(check_for(label))
        end
      end
    end

    def check_for(label)
      Gtk::CheckButton.new.tap do |check|
        check.active = @selected.include?(label.id)
        check.sensitive = false
        @checks[label.id] = check
      end
    end

    def dot(label)
      Gtk::Image.new(icon_name: "tag-outline-symbolic").tap do |image|
        Gtk::CssProvider.new.tap do |provider|
          provider.load(data: "image { color: #{Palette.hex(label.color)}; }")
          image.style_context.add_provider(provider, Gtk::StyleProvider::PRIORITY_APPLICATION)
        end
      end
    end

    def toggle(row)
      @checks.keys[row.index].then do |label_id|
        if @selected.include?(label_id)
          @selected.delete(label_id)
        else
          @selected << label_id
        end

        @checks[label_id].active = @selected.include?(label_id)
        @on_change&.call(@selected)
      end
    end

    def matches?(row)
      search_entry.text.strip.then do |term|
        if term.empty?
          true
        else
          Store.instance.labels[row.index].then do |label|
            label.nil? ? true : label.name.downcase.include?(term.downcase)
          end
        end
      end
    end

    def box
      @box ||= Gtk::Box.new(:vertical, 6).tap do |b|
        b.margin_start = 6
        b.margin_end = 6
        b.margin_top = 6
        b.margin_bottom = 6
        b.width_request = 275
      end
    end

    def search_entry
      @search_entry ||= Gtk::SearchEntry.new.tap do |entry|
        entry.placeholder_text = _("Search or create")
      end
    end

    def scrolled
      @scrolled ||= Gtk::ScrolledWindow.new.tap do |scroll|
        scroll.hscrollbar_policy = :never
        scroll.height_request = 200
      end
    end

    def listbox
      @listbox ||= Gtk::ListBox.new.tap do |list|
        list.selection_mode = :none
        list.add_css_class("menu-listbox")
      end
    end
  end
end
