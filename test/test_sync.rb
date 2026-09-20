# frozen_string_literal: true

# The sync layer without a server: iCalendar round trips, the Todoist JSON
# mapping, recurrence translation both ways, the offline queue, and the
# WebDAV multistatus reader.

require "tmpdir"
require_relative "../lib/planify"

include Planify
include Planify::Services

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
  store = Store.new(Database.new(File.join(dir, "sync.db")))
  Store.instance = store
  store.load

  local = Source.new(source_type: "local", display_name: "On This Computer")
  store.insert_source(local)
  project = Project.new(name: "Chores", source_id: local.id)
  store.insert_project(project)

  puts "sources"
  check("local source is found") { store.local_source == local }
  check("a local source queues nothing") { !SyncQueue.synced?(local.id) }

  todoist = Source.new(source_type: "todoist", display_name: "Todoist")
  todoist.merge_payload("access_token" => "t0ken", "sync_token" => "*")
  store.insert_source(todoist)
  check("payload reads back") { todoist["access_token"] == "t0ken" }
  check("payload defaults fill in") { todoist["api_version"] == "v1" }
  check("a synced source queues") { SyncQueue.synced?(todoist.id) }
  check("v9 needs migration") do
    Source.new(source_type: "todoist").tap { |s| s["api_version"] = "v9" }.needs_migration?
  end
  check("v1 does not") { !todoist.needs_migration? }

  puts "offline queue"
  synced_project = Project.new(name: "Work", source_id: todoist.id)
  store.insert_project(synced_project)
  check("creating queues a project_add") do
    SyncQueue.all(todoist.id).any? { |e| e.query == "project_add" }
  end
  check("the add carries a temp_id") do
    SyncQueue.all(todoist.id).find { |e| e.query == "project_add" }.temp_id.to_s != ""
  end

  synced_item = Item.new(content: "Ship it", project_id: synced_project.id)
  store.insert_item(synced_item)
  check("creating queues an item_add") do
    SyncQueue.all(todoist.id).any? { |e| e.query == "item_add" }
  end
  check("the item's args carry its content") do
    SyncQueue.all(todoist.id).find { |e| e.query == "item_add" }
             .arguments["content"] == "Ship it"
  end

  store.complete_item(synced_item, true)
  check("completing queues item_complete") do
    SyncQueue.all(todoist.id).any? { |e| e.query == "item_complete" }
  end

  local_item = Item.new(content: "Local only", project_id: project.id)
  store.insert_item(local_item)
  check("a local task queues nothing") { SyncQueue.all(local.id).empty? }

  puts "server id adoption"
  old_id = synced_item.id
  store.update_item_id(old_id, "9876543210")
  check("the item took the server id") { !store.item("9876543210").nil? }
  check("the old id is gone") { store.item(old_id).nil? }
  check("queued rows followed it") do
    SyncQueue.all(todoist.id).none? { |e| e.target_id == old_id }
  end

  puts "Todoist mapping"
  node = {
    "id"           => "111",
    "content"      => "Buy milk",
    "description"  => "2%",
    "project_id"   => synced_project.id,
    "section_id"   => "",
    "parent_id"    => "",
    "priority"     => 4,
    "child_order"  => 3,
    "checked"      => false,
    "completed_at" => nil,
    "added_at"     => "2030-01-01T00:00:00",
    "is_deleted"   => false,
    "due"          => {
      "date"         => "2030-05-01T09:30:00",
      "string"       => "every 2 weeks",
      "is_recurring" => true,
    },
    "deadline"     => { "date" => "2030-06-01" },
    "labels"       => ["urgent"],
  }
  Todoist.apply_item(todoist, node)
  imported = store.item("111")
  check("item imported") { !imported.nil? }
  check("content mapped") { imported.content == "Buy milk" }
  check("priority mapped") { imported.priority.to_i == Item::PRIORITY_1 }
  check("due date mapped") { imported.due_date == Time.new(
    2030,
    5,
    1,
    9,
    30,
    0,
  ) }
  check("recurrence mapped") { imported.due_hash["recurrency_type"] == "every_week" }
  check("interval mapped") { imported.due_hash["recurrency_interval"] == 2 }
  check("deadline mapped") { imported.deadline_date == "2030-06-01" }
  check("label created by name") { !store.label_by_name("urgent").nil? }
  check("label attached") { imported.label_ids == [store.label_by_name("urgent").id] }

  check("outgoing args round trip the content") do
    Todoist.item_args(imported)["content"] == "Buy milk"
  end
  check("outgoing args carry the recurrence string") do
    Todoist.item_args(imported)["due"]["string"] == "every 2 weeks"
  end
  check("outgoing labels are names") do
    Todoist.item_args(imported)["labels"] == ["urgent"]
  end

  puts "iCalendar"
  ical_item = Item.new(
    id:          "abc-123",
    content:     "Water, the plants; really",
    description: "Line one\nLine two",
    project_id:  project.id,
    priority:    Item::PRIORITY_2,
    child_order: 7,
  )
  ical_item.due_date = Time.new(
    2030,
    5,
    1,
    9,
    30,
    0,
  )
  ical_item.deadline_date = "2030-06-01"
  ical_item.label_ids = [store.label_by_name("urgent").id]
  store.insert_item(ical_item)

  text = Ical.from_item(ical_item)
  check("has a VTODO") { text.include?("BEGIN:VTODO") }
  check("folds long lines") { text.lines.all? { |line| line.bytesize <= 78 } }
  check("escapes commas and semicolons") { text.include?("Water\\, the plants\; really") }
  check("escapes newlines in the description") { text.include?("Line one\\nLine two") }
  check("writes the deadline") { text.include?("X-PLANIFY-DEADLINE") }
  check("writes categories") { text.include?("CATEGORIES:urgent") }

  parsed = Ical.to_item(text, project.id)
  check("uid round trips") { parsed.id == "abc-123" }
  check("summary unescapes") { parsed.content == "Water, the plants; really" }
  check("description unescapes") { parsed.description == "Line one\nLine two" }
  check("due round trips") { parsed.due_date == Time.new(
    2030,
    5,
    1,
    9,
    30,
    0,
  ) }
  check("priority round trips") { parsed.priority == Item::PRIORITY_2 }
  check("deadline round trips") { parsed.deadline_date == "2030-06-01" }
  check("child order round trips") { parsed.child_order.to_i == 7 }
  check("not completed") { !parsed.checked? }

  ical_item.checked = 1
  ical_item.completed_at = Time.new(
    2030,
    5,
    2,
    10,
    0,
    0,
  ).iso8601
  Ical.from_item(ical_item).then do |done_text|
    check("completed writes STATUS") { done_text.include?("STATUS:COMPLETED") }
    check("completed writes COMPLETED") { done_text.include?("COMPLETED:") }
    check("completed round trips") { Ical.to_item(done_text, project.id).checked? }
  end

  puts "all-day dates"
  allday = Item.new(id: "allday-1", content: "Birthday", project_id: project.id)
  allday.due_date = Time.new(2030, 7, 4)
  Ical.from_item(allday).then do |text2|
    check("writes VALUE=DATE") { text2.include?("DUE;VALUE=DATE:20300704") }
    check("reads back as all-day") do
      Ical.to_item(text2, project.id).due_date == Time.new(2030, 7, 4)
    end
    check("has no time") { !Datetime.has_time?(Ical.to_item(text2, project.id).due_date) }
  end
end

puts "RRULE"
check("weekly with days becomes BYDAY") do
  Recurrency.to_rrule(
    "recurrency_type"     => "every_week",
    "recurrency_interval" => 2,
    "recurrency_weeks"    => "1,4",
  ) == "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,TH"
end
check("last day of month becomes BYMONTHDAY=-1") do
  Recurrency.to_rrule(
    "recurrency_type"              => "every_month",
    "recurrency_interval"          => 1,
    "recurrency_last_day_of_month" => true,
  ) == "FREQ=MONTHLY;BYMONTHDAY=-1"
end
check("count becomes COUNT") do
  Recurrency.to_rrule(
    "recurrency_type"     => "every_day",
    "recurrency_interval" => 1,
    "recurrency_count"    => 5,
  ) == "FREQ=DAILY;COUNT=5"
end
check("an unknown type has no rule") do
  Recurrency.to_rrule("recurrency_type" => "none").nil?
end
check("BYDAY parses back") do
  Recurrency.from_rrule("FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,TH")["recurrency_weeks"] == "1,4"
end
check("interval parses back") do
  Recurrency.from_rrule("FREQ=WEEKLY;INTERVAL=2")["recurrency_interval"] == 2
end
check("a missing interval defaults to one") do
  Recurrency.from_rrule("FREQ=DAILY")["recurrency_interval"] == 1
end
check("frequency parses back") do
  Recurrency.from_rrule("FREQ=MONTHLY")["recurrency_type"] == "every_month"
end

puts "Todoist recurrence strings"
check("'every 3 days' parses") do
  Recurrency.parse_string("every 3 days") == ["every_day", 3, ""]
end
check("'every week' parses") do
  Recurrency.parse_string("every week") == ["every_week", 1, ""]
end
check("'every mon,thu' parses to weekdays") do
  Recurrency.parse_string("every mon,thu") == ["every_week", 1, "1,4"]
end
check("'every weekday' parses to Mon-Fri") do
  Recurrency.parse_string("every weekday") == ["every_week", 1, "1,2,3,4,5"]
end
check("an unparseable string is not recurring") do
  Recurrency.parse_string("sometime soon") == ["none", 0, ""]
end

def recurring_item(fields)
  Item.new.tap { |item| item.due = JSON.generate(fields) }
end

check("weekly-with-days serialises without the unit word") do
  Recurrency.to_todoist_string(
    recurring_item(
      "date"                => "2030-01-07",
      "is_recurring"        => true,
      "recurrency_type"     => "every_week",
      "recurrency_interval" => 1,
      "recurrency_weeks"    => "1,4",
    ),
  ) == "every mon,thu"
end
check("an interval serialises with a plural unit") do
  Recurrency.to_todoist_string(
    recurring_item(
      "date"                => "2030-01-07",
      "is_recurring"        => true,
      "recurrency_type"     => "every_day",
      "recurrency_interval" => 3,
    ),
  ) == "every 3 days"
end
check("a time is appended") do
  Recurrency.to_todoist_string(
    recurring_item(
      "date"                => "2030-01-07T09:30:00",
      "is_recurring"        => true,
      "recurrency_type"     => "every_day",
      "recurrency_interval" => 1,
    ),
  ) == "every day at 09:30"
end
check("an end date is appended") do
  Recurrency.to_todoist_string(
    recurring_item(
      "date"                => "2030-01-07",
      "is_recurring"        => true,
      "recurrency_type"     => "every_day",
      "recurrency_interval" => 1,
      "recurrency_end"      => "2030-03-01",
    ),
  ) == "every day until 2030-03-01"
end
check("a non-recurring item serialises as its date") do
  Recurrency.to_todoist_string(recurring_item("date" => "2030-01-07")) == "2030-01-07"
end

puts "WebDAV multistatus"
MULTISTATUS = <<~XML
  <?xml version="1.0" encoding="utf-8"?>
  <d:multistatus xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav"
                 xmlns:ical="http://apple.com/ns/ical/">
    <d:response>
      <d:href>/remote.php/dav/calendars/nathan/personal/</d:href>
      <d:propstat>
        <d:prop>
          <d:displayname>Personal</d:displayname>
          <d:sync-token>http://sabre.io/ns/sync/42</d:sync-token>
          <ical:calendar-color>#ff0000ff</ical:calendar-color>
          <cal:supported-calendar-component-set>
            <cal:comp name="VTODO"/>
          </cal:supported-calendar-component-set>
        </d:prop>
        <d:status>HTTP/1.1 200 OK</d:status>
      </d:propstat>
    </d:response>
    <d:response>
      <d:href>/remote.php/dav/calendars/nathan/events/</d:href>
      <d:propstat>
        <d:prop>
          <d:displayname>Events</d:displayname>
          <cal:supported-calendar-component-set>
            <cal:comp name="VEVENT"/>
          </cal:supported-calendar-component-set>
        </d:prop>
        <d:status>HTTP/1.1 200 OK</d:status>
      </d:propstat>
    </d:response>
  </d:multistatus>
XML

resources = WebDAV.resources(MULTISTATUS)
check("both responses parse") { resources.size == 2 }
check("href is read") { resources.first.href == "/remote.php/dav/calendars/nathan/personal/" }
check("displayname is read") { resources.first.prop("displayname").text == "Personal" }
check("status is read") { resources.first.ok? }
check("namespace prefixes are ignored") { !resources.first.prop("sync-token").nil? }
check("only VTODO collections are task lists") do
  resources.select { |r| CalDAV.task_list?(r) }.size == 1
end
check("the VTODO one is the task list") do
  resources.find { |r| CalDAV.task_list?(r) }.prop("displayname").text == "Personal"
end
check("the colour drops its alpha") do
  CalDAV.calendar_color(resources.first, "blue") == "#ff0000"
end
check("a calendar id is stable") do
  CalDAV.calendar_id(resources.first) == CalDAV.calendar_id(resources.first)
end
check("different calendars get different ids") do
  CalDAV.calendar_id(resources[0]) != CalDAV.calendar_id(resources[1])
end
check("unparseable XML yields nothing") { WebDAV.resources("not xml at all").empty? }

puts "CalDAV URLs"
caldav = Source.new(source_type: "caldav")
caldav.merge_payload("server_url" => "https://cloud.example.com", "username" => "nathan")
check("server url gains a trailing slash") { caldav.server_url == "https://cloud.example.com/" }
check("calendar home defaults conventionally") do
  caldav.calendar_home_url == "https://cloud.example.com/calendars/nathan/"
end
check("deck base url is derived from the host") do
  caldav.deck_base_url == "https://cloud.example.com/index.php/apps/deck/api/v1.0"
end
check("an absolute href is left alone") do
  WebDAV.absolute(caldav, "https://other.example.com/x") == "https://other.example.com/x"
end
check("a relative href is resolved") do
  WebDAV.absolute(caldav, "/dav/cal/") == "https://cloud.example.com/dav/cal/"
end

puts "priority mapping"
check("ical 1 is P1") { Ical.priority_from_ical(1) == Item::PRIORITY_1 }
check("ical 5 is P2") { Ical.priority_from_ical(5) == Item::PRIORITY_2 }
check("ical 9 is P3") { Ical.priority_from_ical(9) == Item::PRIORITY_3 }
check("ical 0 is none") { Ical.priority_from_ical(0) == Item::PRIORITY_4 }
check("P1 writes as 1") { Ical.priority_to_ical(Item::PRIORITY_1) == 1 }
check("none writes as 0") { Ical.priority_to_ical(Item::PRIORITY_4) == 0 }

puts
if @failures.zero?
  puts "all checks passed"
else
  puts "#{@failures} failed"
  exit 1
end
