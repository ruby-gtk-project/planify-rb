# frozen_string_literal: true

module Planify
  # core/Widgets/ProjectPicker and SectionPicker. One searchable tree of
  # projects, each with its sections, used by quick add, the detail pane and
  # the move dialog.
  class ProjectPicker
    def initialize(project: nil, section: nil, &on_select)
      @project = project
      @section = section
      @on_select = on_select
    end

    attr_reader :project, :section

    def store = Store.instance

    def build
      @build ||= box.tap do |b|
        b.append(search_entry)
        b.append(scrolled)

        scrolled.child = listbox

        search_entry.signal_connect("search-changed") { reload }

        listbox.signal_connect("row-activated") do |_, row|
          entries[row.index].then { |entry| choose(entry) }
        end

        reload
      end
    end

    def select(project, section = nil)
      @project = project
      @section = section
      reload
    end

    def choose(entry)
      @project = entry[:project]
      @section = entry[:section]
      reload
      @on_select&.call(@project, @section)
    end

    def entries = @entries ||= []

    # Inbox first, then every other project, each followed by its sections.
    def reload
      @entries = build_entries

      while listbox.first_child
        listbox.remove(listbox.first_child)
      end

      @entries.each { |entry| listbox.append(entry_row(entry)) }
      placeholder.visible = @entries.empty?
    end

    def build_entries
      candidates.flat_map do |candidate|
        [{ project: candidate, section: nil }] +
          store.sections_by_project(candidate.id).map do |section|
            { project: candidate, section: section }
          end
      end.select { |entry| matches?(entry) }
    end

    def candidates
      ([store.inbox_project] + store.active_projects).compact.uniq
    end

    def matches?(entry)
      search_entry.text.strip.downcase.then do |term|
        if term.empty?
          true
        else
          label_for(entry).downcase.include?(term)
        end
      end
    end

    def label_for(entry)
      [entry[:project].name, entry[:section]&.name].compact.join(" / ")
    end

    def entry_row(entry)
      Adwaita::ActionRow.new.tap do |row|
        row.title = entry[:project].name.to_s
        row.subtitle = entry[:section]&.name.to_s
        row.activatable = true
        row.add_prefix(IconColorProject.new(entry[:project]).build)
        row.add_suffix(tick(entry))
      end
    end

    def tick(entry)
      Gtk::Image.new(icon_name: "check-plain-symbolic").tap do |image|
        image.visible = selected?(entry)
      end
    end

    def selected?(entry)
      entry[:project] == project && entry[:section]&.id.to_s == section&.id.to_s
    end

    def summary
      if project.nil?
        _("Inbox")
      else
        label_for(project: project, section: section)
      end
    end

    def box
      @box ||= Gtk::Box.new(:vertical, 6).tap do |b|
        b.margin_start = 6
        b.margin_end = 6
        b.margin_top = 6
        b.margin_bottom = 6
        b.width_request = 300
      end
    end

    def search_entry
      @search_entry ||= Gtk::SearchEntry.new.tap do |entry|
        entry.placeholder_text = _("Search projects")
      end
    end

    def scrolled
      @scrolled ||= Gtk::ScrolledWindow.new.tap do |scroll|
        scroll.hscrollbar_policy = :never
        scroll.height_request = 260
      end
    end

    def listbox
      @listbox ||= Gtk::ListBox.new.tap do |list|
        list.selection_mode = :none
        list.add_css_class("boxed-list")
        list.set_placeholder(placeholder)
      end
    end

    def placeholder
      @placeholder ||= Gtk::Label.new(_("No matching projects")).tap do |label|
        label.add_css_class("dim-label")
        label.margin_top = 12
        label.margin_bottom = 12
      end
    end
  end

  # core/Widgets/SectionPicker: the sections of one project, for moving a task
  # within the project it is already in.
  class SectionPicker
    def initialize(project, section = nil, &on_select)
      @project = project
      @section = section
      @on_select = on_select
    end

    attr_reader :project, :section

    def store = Store.instance

    def build
      @build ||= listbox.tap do |list|
        reload
        list.signal_connect("row-activated") do |_, row|
          @section = sections[row.index]
          reload
          @on_select&.call(@section)
        end
      end
    end

    # The first entry is "no section", which is where a project's loose tasks
    # live and is a real destination, not an absence of one.
    def sections = @sections ||= [nil] + store.sections_by_project(project.id)

    def reload
      @sections = [nil] + store.sections_by_project(project.id)

      while listbox.first_child
        listbox.remove(listbox.first_child)
      end

      @sections.each { |candidate| listbox.append(section_row(candidate)) }
    end

    def section_row(candidate)
      Adwaita::ActionRow.new.tap do |row|
        if candidate.nil?
          row.title = _("No Section")
        else
          row.title = candidate.name.to_s
        end
        row.activatable = true
        row.add_suffix(
          Gtk::Image.new(icon_name: "check-plain-symbolic").tap do |image|
            image.visible = candidate&.id.to_s == section&.id.to_s
          end,
        )
      end
    end

    def listbox
      @listbox ||= Gtk::ListBox.new.tap do |list|
        list.selection_mode = :none
        list.add_css_class("boxed-list")
        list.width_request = 260
        list.margin_start = 6
        list.margin_end = 6
        list.margin_top = 6
        list.margin_bottom = 6
      end
    end
  end
end
