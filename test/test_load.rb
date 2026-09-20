# frozen_string_literal: true

# Plain checks on everything expressible without a widget: the schema round
# trip, the filters, recurrency arithmetic and the smart-input parsing.

require "tmpdir"
require_relative "../lib/planify"

include Planify

@failures = 0

def check(name)
  if yield
    puts "  ok   #{name}"
  else
    puts "  FAIL #{name}"
    @failures += 1
  end
rescue StandardError => error
  puts "  FAIL #{name}: #{error.class}: #{error.message}"
  @failures += 1
end

Dir.mktmpdir do |dir|
  database = Database.new(File.join(dir, "test.db"))
  store = Store.new(database)
  Store.instance = store
  store.load

  puts "database"
  check("opens healthy") { database.healthy? }
  check("starts empty") { store.empty? }

  puts "seed"
  Seed.create_inbox(store)
  Seed.create_tutorial(store)
  Seed.create_default_labels(store)
  check("inbox exists") { !store.projects.find(&:inbox?).nil? }
  check("tutorial project has six loose tasks") do
    store.projects.reject(&:inbox?).first.then do |project|
      store.items_by_project_unsectioned(project.id).size == 6
    end
  end
  check("tutorial has two sections") do
    store.sections_by_project(store.projects.reject(&:inbox?).first.id).size == 2
  end
  check("five default labels") { store.labels.size == 5 }

  puts "round trip"
  project = store.projects.reject(&:inbox?).first
  item = Item.new(project_id: project.id, content: "Round trip", priority: Item::PRIORITY_1)
  item.due_date = Time.new(
    2030,
    5,
    1,
    9,
    30,
    0,
  )
  item.label_ids = [store.labels.first.id]
  store.insert_item(item)

  reloaded = Store.new(Database.new(database.path)).tap(&:load)
  check("item survives a reload") { !reloaded.item(item.id).nil? }
  check("due date survives") do
    reloaded.item(item.id).due_date == Time.new(
      2030,
      5,
      1,
      9,
      30,
      0,
    )
  end
  check("labels survive") { reloaded.item(item.id).label_ids == [store.labels.first.id] }
  check("priority survives") { reloaded.item(item.id).priority.to_i == Item::PRIORITY_1 }

  puts "filters"
  today = Item.new(project_id: project.id, content: "Due today")
  today.due_date = Datetime.strip_time(Time.now)
  store.insert_item(today)

  overdue = Item.new(project_id: project.id, content: "Overdue")
  overdue.due_date = Datetime.strip_time(Time.now - (3 * 86_400))
  store.insert_item(overdue)

  pinned = Item.new(project_id: project.id, content: "Pinned", pinned: 1)
  store.insert_item(pinned)

  check("today includes today's task") { store.today_items.include?(today) }
  check("today includes overdue") { store.today_items.include?(overdue) }
  check("today excludes the undated") { !store.today_items.include?(pinned) }
  check("scheduled excludes overdue") { !store.scheduled_items.include?(overdue) }
  check("scheduled includes the future") { store.scheduled_items.include?(reloaded.item(item.id) && item) }
  check("pinboard finds the pinned task") { store.pinboard_items == [pinned] }
  check("anytime holds only undated tasks") { store.anytime_items.none?(&:has_due?) }
  check("label filter finds the labelled task") do
    store.items_by_label(store.labels.first.id).include?(item)
  end
  check("unlabeled excludes it") { !store.unlabeled_items.include?(item) }

  puts "completion"
  store.complete_item(today, true)
  check("completing sets checked") { today.checked? }
  check("completing stamps completed_at") { !today.completed_at.to_s.empty? }
  check("completed leaves the today filter") { !store.today_items.include?(today) }
  check("completed joins the completed filter") { store.completed_items.include?(today) }
  store.complete_item(today, false)
  check("uncompleting returns it") { store.today_items.include?(today) }

  puts "subtasks follow the parent"
  subtask = Item.new(project_id: project.id, parent_id: today.id, content: "Subtask")
  store.insert_item(subtask)
  store.complete_item(today, true)
  check("subtask completed with parent") { subtask.checked? }
  store.complete_item(today, false)

  puts "trash"
  store.trash_item(pinned)
  check("trashed leaves the filters") { !store.pinboard_items.include?(pinned) }
  store.restore_item(pinned)
  check("restore brings it back") { store.pinboard_items.include?(pinned) }

  puts "cascade"
  section = store.sections_by_project(project.id).first
  section_item_count = store.items_by_section(section.id).size
  check("section has items to lose") { section_item_count.positive? }
  store.delete_section(section)
  check("section items are gone") { store.items_by_section(section.id).empty? }

  puts "label deletion detaches"
  label = store.labels.first
  store.delete_label(label)
  check("label removed") { store.label(label.id).nil? }
  check("item no longer carries it") { !store.item(item.id).label_ids.include?(label.id) }

  puts "project deletion cascades"
  child = Project.new(name: "Child", parent_id: project.id)
  store.insert_project(child)
  store.insert_item(Item.new(project_id: child.id, content: "Child task"))
  store.delete_project(project)
  check("project gone") { store.project(project.id).nil? }
  check("subproject gone") { store.project(child.id).nil? }
  check("its items gone") { store.items_by_project(project.id).empty? }
end

puts "datetime"
check("has_time? is false at midnight") { !Datetime.has_time?(
  Time.new(
    2030,
    1,
    1,
    0,
    0,
    0,
  ),
) }
check("has_time? is true otherwise") { Datetime.has_time?(
  Time.new(
    2030,
    1,
    1,
    9,
    0,
    0,
  ),
) }
check("today? recognises now") { Datetime.today?(Time.now) }
check("tomorrow? recognises tomorrow") { Datetime.tomorrow?(Time.now + 86_400) }
check("overdue? recognises yesterday") { Datetime.overdue?(Time.now - 86_400) }
check("overdue? is false for today") { !Datetime.overdue?(Time.now) }
check("format drops a zero time") { Datetime.format(Time.new(2030, 5, 1)) == "2030-05-01" }
check("format keeps a real time") do
  Datetime.format(
    Time.new(
      2030,
      5,
      1,
      9,
      30,
      0,
    ),
  ) == "2030-05-01T09:30:00"
end
check("parse round trips") do
  Datetime.parse(
    Datetime.format(
      Time.new(
        2030,
        5,
        1,
        9,
        30,
        0,
      ),
    ),
  ) == Time.new(
    2030,
    5,
    1,
    9,
    30,
    0,
  )
end

puts "recurrency"
def repeating(type, interval, **extra)
  Item.new.tap do |item|
    item.due = JSON.generate(
      {
        "date"                => "2030-01-31T09:00:00",
        "is_recurring"        => true,
        "recurrency_type"     => type,
        "recurrency_interval" => interval,
      }.merge(extra),
    )
  end
end

check("daily advances by the interval") do
  Recurrency.next_date(repeating("every_day", 3)) == Time.new(
    2030,
    2,
    3,
    9,
    0,
    0,
  )
end
check("weekly advances by whole weeks") do
  Recurrency.next_date(repeating("every_week", 2)) == Time.new(
    2030,
    2,
    14,
    9,
    0,
    0,
  )
end
check("monthly clamps the 31st to February") do
  Recurrency.next_date(repeating("every_month", 1)) == Time.new(
    2030,
    2,
    28,
    9,
    0,
    0,
  )
end
check("last-day-of-month lands on the last day") do
  Recurrency.next_date(repeating("every_month", 1, "recurrency_last_day_of_month" => true)) ==
    Time.new(
      2030,
      2,
      28,
      9,
      0,
      0,
    )
end
check("yearly advances a year") do
  Recurrency.next_date(repeating("every_year", 1)) == Time.new(
    2031,
    1,
    31,
    9,
    0,
    0,
  )
end
check("hourly advances hours") do
  Recurrency.next_date(repeating("hourly", 5)) == Time.new(
    2030,
    1,
    31,
    14,
    0,
    0,
  )
end
check("a count of one ends the series") do
  Recurrency.next_date(repeating("every_day", 1, "recurrency_count" => 1)).nil?
end
check("an end date in the past ends the series") do
  Recurrency.next_date(repeating("every_day", 1, "recurrency_end" => "2030-01-31")).nil?
end

puts "colors"
check("a palette key resolves") { Palette.hex("berry_red") == "#c42d78" }
check("an unknown key falls back") { Palette.hex("not-a-color") == "#1e63ec" }
check("an empty key falls back") { Palette.hex("") == "#1e63ec" }

puts "priority"
check("P1 is red") { Item.new(priority: Item::PRIORITY_1).priority_color == "#ff7066" }
check("P4 uses the text colour") do
  Item.new(priority: Item::PRIORITY_4).priority_color == "@text_color"
end

puts
if @failures.zero?
  puts "all checks passed"
else
  puts "#{@failures} failed"
  exit 1
end
