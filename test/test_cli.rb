# frozen_string_literal: true

# The CLI against a scratch database: adding, listing, updating and the
# abbreviated-id lookup, plus the priority numbering that runs the opposite
# way from the stored value.

ENV["PLANIFY_TEST"] = "1"
ENV["GSETTINGS_BACKEND"] = "memory"

require "tmpdir"
require "stringio"
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

# The CLI prints; the tests care about what it printed as well as what it did.
def capture
  $stdout = StringIO.new
  status = yield
  [status, $stdout.string]
ensure
  $stdout = STDOUT
end

Dir.mktmpdir do |dir|
  store = Store.new(Database.new(File.join(dir, "cli.db")))
  Store.instance = store
  store.load
  Seed.install(store)
  CLI.instance_variable_set(:@store, store)

  puts "add"
  status, output = capture { CLI.run(["add", "Buy", "milk"]) }
  check("exits zero") { status.zero? }
  check("says what it added") { output.include?("Buy milk") }
  check("the task exists") { !store.items.find { |i| i.content == "Buy milk" }.nil? }
  check("it landed in the inbox") do
    store.items.find { |i| i.content == "Buy milk" }.project_id == store.inbox_project.id
  end

  puts "add with options"
  capture do
    CLI.run(
      ["add", "-c", "Pay rent", "--priority", "1", "--due", "tomorrow",
                   "-l", "bills,urgent", "--pinned",
      ],
    )
  end
  @paid = store.items.find { |i| i.content == "Pay rent" }
  check("priority 1 maps to the stored P1") { @paid.priority.to_i == Item::PRIORITY_1 }
  check("due tomorrow") { Datetime.tomorrow?(@paid.due_date) }
  check("pinned") { @paid.pinned? }
  check("two labels attached") { @paid.label_ids.size == 2 }
  check("a new label was created") { !store.label_by_name("bills").nil? }

  puts "add into a named project"
  capture { CLI.run(["add", "-c", "Ship it", "-p", "Meet Planify"]) }
  check("it went to that project") do
    store.items.find { |i| i.content == "Ship it" }.project.name == "Meet Planify"
  end

  status, output = capture { CLI.run(["add", "-c", "Nowhere", "-p", "No Such Project"]) }
  check("an unknown project is an error") { status == 1 }
  check("an unknown project creates nothing") do
    store.items.none? { |i| i.content == "Nowhere" }
  end

  status, = capture { CLI.run(["add"]) }
  check("an empty task is refused") { status == 1 }

  puts "list"
  _, output = capture { CLI.run(["list"]) }
  check("lists the tasks") { output.include?("Buy milk") }
  check("shows an unchecked box") { output.include?("[ ] ") }
  check("shows the priority") { output.include?("P1") }
  check("shows labels") { output.include?("@bills") }

  _, output = capture { CLI.run(["list", "-p", "Meet Planify"]) }
  check("filters by project") { output.include?("Ship it") }
  check("excludes other projects") { !output.include?("Buy milk") }

  puts "projects"
  _, output = capture { CLI.run(["projects"]) }
  check("lists the inbox") { output.include?("Inbox") }
  check("lists the tutorial project") { output.include?("Meet Planify") }

  puts "update"
  short = @paid.id.to_s[0, 8]
  status, output = capture { CLI.run(["update", "-i", short, "-c", "Pay the rent"]) }
  check("exits zero") { status.zero? }
  check("an abbreviated id resolves") { store.item(@paid.id).content == "Pay the rent" }
  check("says what it updated") { output.include?("Pay the rent") }

  capture { CLI.run(["update", "-i", short, "--complete"]) }
  check("completes") { store.item(@paid.id).checked? }
  check("stamps completed_at") { !store.item(@paid.id).completed_at.to_s.empty? }

  capture { CLI.run(["update", "-i", short, "--uncomplete"]) }
  check("uncompletes") { !store.item(@paid.id).checked? }
  check("clears completed_at") { store.item(@paid.id).completed_at.to_s.empty? }

  capture { CLI.run(["update", "-i", short, "--unpin", "--priority", "3"]) }
  check("unpins") { !store.item(@paid.id).pinned? }
  check("priority 3 maps to the stored P3") do
    store.item(@paid.id).priority.to_i == Item::PRIORITY_3
  end

  status, = capture { CLI.run(["update", "-i", "nosuchid", "-c", "x"]) }
  check("an unknown id is an error") { status == 1 }

  status, = capture { CLI.run(["update"]) }
  check("a missing id is an error") { status == 1 }

  puts "ambiguous ids"
  a = Item.new(id: "abcd1111", content: "One", project_id: store.inbox_project.id)
  b = Item.new(id: "abcd2222", content: "Two", project_id: store.inbox_project.id)
  store.insert_item(a)
  store.insert_item(b)
  status, = capture { CLI.run(["update", "-i", "abcd", "-c", "x"]) }
  check("an ambiguous prefix is refused") { status == 1 }
  check("neither task was touched") do
    store.item("abcd1111").content == "One" && store.item("abcd2222").content == "Two"
  end

  puts "backup"
  target = File.join(dir, "backup.json")
  status, output = capture { CLI.run(["backup", "-o", target]) }
  check("exits zero") { status.zero? }
  check("wrote the file") { File.exist?(target) }
  check("says where") { output.include?(target) }
  check("it is a Planify backup") do
    JSON.parse(File.read(target)).then { |p| p.key?("items") && p.key?("projects") }
  end

  puts "help and unknown commands"
  status, output = capture { CLI.run([]) }
  check("no arguments shows usage") { status.zero? && output.include?("Usage") }
  status, output = capture { CLI.run(["help"]) }
  check("help shows every command") do
    status.zero? && CLI::COMMANDS.keys.all? { |name| output.include?(name) }
  end
  status, = capture { CLI.run(["nonsense"]) }
  check("an unknown command is an error") { status == 1 }
end

puts "priority numbering"
check("CLI 1 is the stored P1") { CLI.priority_from_cli(1) == Item::PRIORITY_1 }
check("CLI 4 is the stored P4") { CLI.priority_from_cli(4) == Item::PRIORITY_4 }
check("it round trips") { CLI.priority_to_cli(CLI.priority_from_cli(2)) == 2 }

puts "due parsing"
check("today") { Datetime.today?(CLI.parse_due("today")) }
check("tomorrow") { Datetime.tomorrow?(CLI.parse_due("tomorrow")) }
check("an ISO date") { CLI.parse_due("2030-05-01") == Time.new(2030, 5, 1) }
check("nothing") { CLI.parse_due("").nil? }
check("nonsense") { CLI.parse_due("not a date").nil? }

puts
if @failures.zero?
  puts "all checks passed"
else
  puts "#{@failures} failed"
  exit 1
end
