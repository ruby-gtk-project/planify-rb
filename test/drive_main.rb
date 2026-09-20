# frozen_string_literal: true

# Drives the real window: first run seeds the database, the sidebar fills, the
# filters switch, a task completes, quick add creates one, and the detail pane
# edits it.

require "tmpdir"

scratch = Dir.mktmpdir("planify-drive")
ENV["XDG_DATA_HOME"] = scratch
ENV["XDG_CONFIG_HOME"] = scratch

require_relative "../lib/planify"
require_relative "gtk_driver"

include Planify

app = Application.new

GtkDriver.drive(app, shots: "tmp/shots") do |d, _|
  window = -> { app.main_window }
  store = -> { Store.instance }

  d.window { window.call.window }

  d.step("the app starts on a seeded database") do
    d.check("window built") { !window.call.window.nil? }
    d.check("inbox project seeded") { !store.call.projects.find(&:inbox?).nil? }
    d.check("tutorial project seeded") { store.call.projects.size == 2 }
    d.check("default labels seeded") { store.call.labels.size == 5 }
    d.check("sidebar lists both projects") do
      window.call.sidebar.instance_variable_get(:@project_rows).size == 1
    end
    d.shot("01-startup")
  end

  d.step("the inbox opens by default") do
    d.check("inbox view is showing") do
      window.call.views_stack.visible_child_name == "filter-inbox"
    end
    d.shot("02-inbox")
  end

  d.step("switch to the tutorial project") do
    store.call.projects.reject(&:inbox?).first.then { |p| window.call.show_project(p) }
  end

  d.step("the project view renders its tasks and sections") do
    store.call.projects.reject(&:inbox?).first.then do |project|
      d.check("project view is showing") do
        window.call.views_stack.visible_child_name == "project-#{project.id}"
      end
      d.check("six loose tasks are listed") do
        window.call.instance_variable_get(:@views)["project-#{project.id}"]
              .rows.size == 6
      end
      d.check("two sections are rendered") do
        window.call.instance_variable_get(:@views)["project-#{project.id}"]
              .instance_variable_get(:@section_rows).size == 2
      end
    end
    d.shot("03-project")
  end

  d.step("completing a task from its row writes through to the store") do
    store.call.projects.reject(&:inbox?).first.then do |project|
      window.call.instance_variable_get(:@views)["project-#{project.id}"].then do |view|
        @completed_id = store.call.items_by_project_unsectioned(project.id).first.id
        view.rows[@completed_id].tap do |row|
          row.child.first_child.first_child.active = true
        end
      end
    end
  end

  d.step("the task is complete") do
    d.check("store marked it checked") { store.call.item(@completed_id).checked? }
    d.check("completed_at was stamped") do
      !store.call.item(@completed_id).completed_at.to_s.empty?
    end
    d.shot("04-completed")
  end

  d.step("quick add creates a task") do
    @quick = QuickAdd.new(window.call, project: store.call.inbox_project)
    @quick.present(window.call.window)
  end

  d.step("type into quick add") do
    @quick.content_entry.text = "Buy milk tomorrow p1"
  end

  d.step("smart input is recognised") do
    d.check("priority read from the text") { @quick.priority_picker.priority == Item::PRIORITY_1 }
    d.check("date read from the text") { Datetime.tomorrow?(@quick.instance_variable_get(:@due)) }
    d.shot("05-quick-add")
    @quick.submit
  end

  d.step("the task was created without its tokens") do
    store.call.items_by_project(store.call.inbox_project.id)
         .find { |item| item.content.start_with?("Buy milk") }.then do |item|
      @created = item
      d.check("task exists") { !item.nil? }
      d.check("tokens stripped from the content") { item&.content == "Buy milk" }
      d.check("due date set to tomorrow") { Datetime.tomorrow?(item&.due_date) }
      d.check("priority set to P1") { item&.priority.to_i == Item::PRIORITY_1 }
    end
    window.call.window.visible_dialog&.close
  end

  d.step("open the new task in the detail pane") do
    window.call.show_item(@created)
  end

  d.step("the detail pane is populated") do
    window.call.item_detail.then do |detail|
      d.check("detail shows the item page") { detail.stack.visible_child_name == "item" }
      d.check("content entry filled") { detail.content_entry.text == "Buy milk" }
      d.check("priority combo on P1") { detail.priority_row.selected.zero? }
      d.check("sidebar revealed") { window.call.detail_split_view.show_sidebar? }
    end
    d.shot("06-detail")
  end

  d.step("editing the title writes through") do
    window.call.item_detail.content_entry.text = "Buy oat milk"
  end

  d.step("the store took the edit") do
    d.check("content updated") { store.call.item(@created.id).content == "Buy oat milk" }
    d.shot("07-edited")
  end

  d.step("go to Today") do
    window.call.go_today
  end

  d.step("Today lists the overdue and due-today tasks") do
    d.check("today view showing") { window.call.views_stack.visible_child_name == "filter-today" }
    d.check("row count matches the filter") do
      window.call.instance_variable_get(:@views)["filter-today"].rows.size ==
        store.call.today_items.size
    end
    d.shot("08-today")
  end

  d.step("go to Labels") do
    window.call.go_labels
  end

  d.step("the labels view lists every label") do
    d.check("labels view showing") { window.call.views_stack.visible_child_name == "labels" }
    d.check("five labels rendered") do
      window.call.instance_variable_get(:@views)["labels"].rows.size == 5
    end
    d.shot("09-labels")
  end

  d.step("create a project") do
    @project_dialog = Dialogs::ProjectDialog.new(window.call)
    @project_dialog.present(window.call.window)
  end

  d.step("fill the project dialog") do
    @project_dialog.name_row.text = "Garden"
  end

  # The dialog needs a tick to realise before it has a render node to shoot.
  d.step("the project dialog renders, then saves") do
    d.shot("10-project-dialog")
    @project_dialog.save
  end

  d.step("the project exists and opened") do
    store.call.active_projects.find { |p| p.name == "Garden" }.then do |project|
      d.check("project created") { !project.nil? }
      d.check("its view opened") do
        window.call.views_stack.visible_child_name == "project-#{project&.id}"
      end
      d.check("sidebar picked it up") do
        window.call.sidebar.instance_variable_get(:@project_rows).key?(project&.id)
      end
    end
    window.call.window.visible_dialog&.close
    d.shot("11-new-project")
  end

  d.step("quick find searches everything") do
    @find = Dialogs::QuickFind.new(window.call)
    @find.present(window.call.window)
  end

  d.step("search for milk") do
    @find.search_entry.text = "milk"
  end

  d.step("the task is found") do
    d.check("one result") { @find.instance_variable_get(:@results).size == 1 }
    d.check("it is the task") do
      @find.instance_variable_get(:@results).first[1].content == "Buy oat milk"
    end
    d.shot("12-quick-find")
    window.call.window.visible_dialog&.close
  end

  d.step("preferences opens") do
    @prefs = Dialogs::Preferences.new
    @prefs.present(window.call.window)
  end

  d.step("preferences renders") do
    d.check("home view combo populated") { @prefs.home_view_row.model.n_items == 5 }
    d.shot("13-preferences")
    window.call.window.visible_dialog&.close
  end

  d.step("shortcuts window opens") do
    Dialogs::Shortcuts.new.present(window.call.window)
  end

  d.step("shortcuts renders") do
    d.shot("14-shortcuts")
    window.call.window.visible_dialog&.close
  end
end
