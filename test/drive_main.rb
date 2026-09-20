# frozen_string_literal: true

# Drives the real window: first run seeds the database, the sidebar fills, the
# filters switch, a task completes, quick add creates one, and the detail pane
# edits it.

require "tmpdir"

ENV["PLANIFY_TEST"] = "1"

# Without a dconf daemon a GSettings write is silently dropped, so a test that
# toggles a preference would read back the old value. The memory backend makes
# settings behave, and keeps the run from touching the user's real dconf.
ENV["GSETTINGS_BACKEND"] = "memory"

# stdout is a pipe under the test runner, so it block-buffers; a killed run
# would otherwise lose everything it had printed.
$stdout.sync = true

scratch = Dir.mktmpdir("planify-drive")
ENV["XDG_DATA_HOME"] = scratch
ENV["XDG_CONFIG_HOME"] = scratch

require_relative "../lib/planify"
require_relative "gtk_driver"

include Planify
include Planify::Services

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
    d.check("the sidebar groups projects under an account") do
      window.call.sidebar.source_rows.size == 1
    end
    d.check("the tutorial project is in the tree") do
      window.call.sidebar.project_rows.size == 1
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
        window.call.sidebar.project_rows.key?(project&.id)
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

  d.step("preferences renders every page") do
    d.check("six pages") { @prefs.pages.size == 6 }
    d.check("home view combo populated") { @prefs.general.home_view_row.model.n_items == 5 }
    d.check("dark mode row reflects the setting") do
      @prefs.appearance.dark_row.active? == Settings.get_boolean("dark-mode")
    end
    d.check("accounts page offers three providers") do
      [@prefs.accounts.todoist_row, @prefs.accounts.nextcloud_row,
       @prefs.accounts.caldav_row
].all? { |row| !row.nil? }
    end
    d.check("no accounts are set up yet") { @prefs.accounts.sources_group.visible? == false }
    d.check("the calendar page says whether EDS is available") do
      !@prefs.calendar.enable_group.description.to_s.empty?
    end
    d.shot("13-preferences")
  end

  d.step("toggling a preference writes through to GSettings") do
    @prefs.general.task_count_row.active = !Settings.get_boolean("show-tasks-count")
  end

  d.step("the setting moved") do
    d.check("show-tasks-count follows the switch") do
      Settings.get_boolean("show-tasks-count") == @prefs.general.task_count_row.active?
    end
    window.call.window.visible_dialog&.close
  end

  d.step("shortcuts window opens") do
    Dialogs::Shortcuts.new.present(window.call.window)
  end

  d.step("shortcuts renders") do
    d.shot("14-shortcuts")
    window.call.window.visible_dialog&.close
  end

  d.step("an overdue and a today task exist") do
    store.call.inbox_project.then do |inbox|
      @overdue = Item.new(content: "Overdue thing", project_id: inbox.id)
      @overdue.due_date = Datetime.strip_time(Time.now - (3 * 86_400))
      store.call.insert_item(@overdue)

      @due_today = Item.new(content: "Today thing", project_id: inbox.id)
      @due_today.due_date = Datetime.strip_time(Time.now)
      store.call.insert_item(@due_today)
    end
  end

  d.step("Today shows overdue separately from today") do
    window.call.go_today
  end

  d.step("the Today sections are populated") do
    window.call.instance_variable_get(:@views)["filter-today"].then do |view|
      d.check("overdue section is revealed") { view.overdue_box.visible? }
      d.check("overdue counts one") { view.overdue_count.label == "1" }
      d.check("today section is revealed") { view.today_box.visible? }
      d.check("today holds the due-today task") { view.today.include?(@due_today) }
      d.check("today excludes the overdue one") { !view.today.include?(@overdue) }
    end
    d.shot("15-today-sections")
  end

  d.step("rescheduling the overdue task from the header") do
    window.call.instance_variable_get(:@views)["filter-today"]
          .reschedule_picker.pick(Datetime.strip_time(Time.now))
  end

  d.step("it moved to today") do
    d.check("no longer overdue") { !Datetime.overdue?(store.call.item(@overdue.id).due_date) }
    d.check("due today now") { Datetime.today?(store.call.item(@overdue.id).due_date) }
    d.shot("16-rescheduled")
  end

  d.step("Scheduled groups by day") do
    window.call.go_scheduled
  end

  d.step("the scheduled view renders its day sections") do
    window.call.instance_variable_get(:@views)["filter-scheduled"].then do |view|
      d.check("scheduled view is showing") do
        window.call.views_stack.visible_child_name == "filter-scheduled"
      end
      d.check("it lists the future task") { view.items.include?(store.call.item(@created.id)) }
      d.check("a day section was built") { view.sections_box.first_child != nil }
    end
    d.shot("17-scheduled")
  end

  d.step("switch the tutorial project to a board") do
    store.call.projects.reject(&:inbox?).first.then do |project|
      window.call.show_project(project)
      window.call.instance_variable_get(:@views)["project-#{project.id}"].toggle_view_style
    end
  end

  d.step("the board renders a column per section plus one for loose tasks") do
    store.call.projects.reject(&:inbox?).first.then do |project|
      window.call.instance_variable_get(:@views)["project-#{project.id}"].then do |view|
        d.check("board page is showing") { view.stack.visible_child_name == "board" }
        d.check("three columns") do
          view.instance_variable_get(:@boards).size == 3
        end
        d.check("the project is stored as a board") { project.board? }
      end
    end
    d.shot("18-board")
  end

  d.step("switch back to the list") do
    store.call.projects.reject(&:inbox?).first.then do |project|
      window.call.instance_variable_get(:@views)["project-#{project.id}"].toggle_view_style
    end
  end

  d.step("the list came back") do
    store.call.projects.reject(&:inbox?).first.then do |project|
      d.check("list page is showing") do
        window.call.instance_variable_get(:@views)["project-#{project.id}"]
              .stack.visible_child_name == "list"
      end
    end
    d.shot("19-back-to-list")
  end

  d.step("pinning a task shows it on the Pinboard") do
    store.call.item(@created.id).then do |item|
      item.pinned = 1
      store.call.update_item(item)
    end
    window.call.go_pinboard
  end

  d.step("the Pinboard lists it") do
    d.check("pinboard view showing") do
      window.call.views_stack.visible_child_name == "filter-pinboard"
    end
    d.check("one pinned task") { store.call.pinboard_items.size == 1 }
    d.check("the row is rendered") do
      window.call.instance_variable_get(:@views)["filter-pinboard"].rows.size == 1
    end
    d.shot("20-pinboard")
  end

  d.step("a Todoist account can be added and shows in the sidebar") do
    @todoist = Source.new(source_type: "todoist", display_name: "Todoist Account")
    @todoist.merge_payload("access_token" => "token", "sync_token" => "*")
    store.call.insert_source(@todoist)
  end

  d.step("the accounts page lists it") do
    d.check("source is stored") { store.call.synced_sources.size == 1 }
    d.check("its projects list is empty") { store.call.projects_by_source(@todoist.id).empty? }
    d.shot("21-account-added")
  end

  d.step("a synced project queues its creation") do
    @synced_project = Project.new(name: "Synced", source_id: @todoist.id)
    store.call.insert_project(@synced_project)
  end

  d.step("the queue recorded it") do
    Services::SyncQueue.all(@todoist.id).then do |queued|
      d.check("one queued command") { queued.size == 1 }
      d.check("it is a project_add") { queued.first.query == "project_add" }
      d.check("it carries a temp id") { !queued.first.temp_id.to_s.empty? }
    end
  end

  d.step("removing the account takes its projects with it") do
    store.call.delete_source(@todoist)
  end

  d.step("nothing of it is left") do
    d.check("source gone") { store.call.source(@todoist.id).nil? }
    d.check("its project gone") { store.call.project(@synced_project.id).nil? }
    d.check("its queue cleared") { Services::SyncQueue.all(@todoist.id).empty? }
    d.shot("22-account-removed")
  end

  d.step("a sub-task appears under its parent") do
    store.call.item(@created.id).then do |parent|
      store.call.insert_item(
        Item.new(content: "A sub-task", project_id: parent.project_id, parent_id: parent.id),
      )
    end
  end

  d.step("the detail pane shows it") do
    window.call.show_item(store.call.item(@created.id))
  end

  d.step("the sub-task list is populated") do
    window.call.item_detail.sub_items.then do |sub|
      d.check("one sub-task") { sub.subitems.size == 1 }
      d.check("its progress reads 0/1") { sub.progress_label.label == "0/1" }
    end
    d.shot("23-subtasks")
  end

  d.step("the change history was recorded by the database triggers") do
    store.call.events_for_item(@created.id).then do |events|
      d.check("the insert was recorded") { events.any?(&:inserted?) }
      d.check("the rename was recorded") do
        events.any? { |event| event.key == "content" && !event.inserted? }
      end
      d.check("it reads back the old and new names") do
        events.find { |e| e.key == "content" && !e.inserted? }
              .then { |e| e.new_value == "Buy oat milk" }
      end
    end
  end

  d.step("a label with a duplicate name is refused") do
    @label_dialog = Dialogs::LabelDialog.new(window.call)
    @label_dialog.present(window.call.window)
  end

  d.step("fill it with an existing name") do
    @label_dialog.name_row.text = store.call.labels.first.name
  end

  d.step("saving it does not create a second label") do
    before = store.call.labels.size
    @label_dialog.save
    d.check("no label was added") { store.call.labels.size == before }
    window.call.window.visible_dialog&.close
    d.shot("24-duplicate-label")
  end

  d.step("All Tasks opens with its filter chips") do
    window.call.go_all
  end

  d.step("it lists everything pending") do
    window.call.instance_variable_get(:@views)["filter-all"].then do |view|
      d.check("all-tasks view is showing") do
        window.call.views_stack.visible_child_name == "filter-all"
      end
      d.check("no chips yet") { view.chips.empty? }
      d.check("it holds every pending task") { view.items.size == store.call.pending.size }
      @all_view = view
    end
    d.shot("25-all-tasks")
  end

  d.step("narrowing by priority") do
    @all_view.add_chip("priority:#{Item::PRIORITY_1}")
  end

  d.step("the chip narrows the list") do
    d.check("one chip") { @all_view.chips.size == 1 }
    d.check("the chip bar is revealed") { @all_view.chips_bar.reveal_child? }
    d.check("only P1 tasks remain") do
      @all_view.items.all? { |item| item.priority.to_i == Item::PRIORITY_1 }
    end
    d.check("it is fewer than everything") { @all_view.items.size < store.call.pending.size }
    d.check("the chip reads as the priority") do
      @all_view.chip_title("priority:#{Item::PRIORITY_1}").include?("Priority 1")
    end
    d.shot("26-filtered")
  end

  d.step("chips intersect rather than widen") do
    @all_view.add_chip("due-date:none")
  end

  d.step("the second chip narrows further") do
    d.check("two chips") { @all_view.chips.size == 2 }
    d.check("nothing matches both") { @all_view.items.empty? }
    d.check("the empty state is showing") { @all_view.stack.visible_child_name == "empty" }
    d.shot("27-intersected")
  end

  d.step("removing a chip widens again") do
    @all_view.remove_chip("due-date:none")
  end

  d.step("it is back to the priority filter") do
    d.check("one chip") { @all_view.chips.size == 1 }
    d.check("P1 tasks are back") { !@all_view.items.empty? }
  end

  d.step("the priority filter view stands on its own") do
    window.call.show_filter("priority-1")
  end

  d.step("it matches the chip-filtered list") do
    window.call.instance_variable_get(:@views)["filter-priority-1"].then do |view|
      d.check("priority view is showing") do
        window.call.views_stack.visible_child_name == "filter-priority-1"
      end
      d.check("same tasks as the chip filter") do
        view.items.map(&:id).sort == store.call.priority_items(Item::PRIORITY_1).map(&:id).sort
      end
    end
    d.shot("28-priority-view")
  end

  d.step("a CalDAV account with Deck can be described") do
    @caldav = Services::CalDAV.build_source(

      "https://cloud.example.com",
      "nathan",
      "secret",
      "nextcloud",
      false,

    )
    store.call.insert_source(@caldav)
  end

  d.step("its URLs are derived correctly") do
    d.check("stored") { !store.call.source(@caldav.id).nil? }
    d.check("calendar home defaults conventionally") do
      @caldav.calendar_home_url == "https://cloud.example.com/calendars/nathan/"
    end
    d.check("deck base url is derived") do
      @caldav.deck_base_url == "https://cloud.example.com/index.php/apps/deck/api/v1.0"
    end
    d.check("deck is off until asked for") { @caldav["use_deck"] != true }
    d.check("the sidebar grew a second account") do
      window.call.sidebar.source_rows.size == 2
    end
    d.shot("29-caldav-account")
  end

  d.step("deleting a synced task queues what the server call needs") do
    store.call.insert_project(Project.new(name: "Remote", source_id: @caldav.id)).then do |project|
      @remote_item = Item.new(content: "Remote task", project_id: project.id)
      store.call.insert_item(@remote_item)
      Services::SyncQueue.clear(@caldav.id)
      store.call.delete_item(@remote_item)
    end
  end

  d.step("the delete entry carries the ids") do
    Services::SyncQueue.all(@caldav.id).find { |e| e.query == "item_delete" }.then do |entry|
      d.check("a delete was queued") { !entry.nil? }
      d.check("it names the task") { entry.target_id == @remote_item.id }
      d.check("it carries the project") do
        entry.arguments["project_id"] == @remote_item.project_id
      end
    end
    store.call.delete_source(@caldav)
  end
end
