# Test parity — planify-rb

| | |
|---|---|
| Upstream | `main` @ `cc26aaed3` |
| Port | `ruby` @ `784980523` |
| Upstream tests | 34 |
| Ported | **0** |
| Gaps | **34** |
| Test command declared by the port | `make test` / `rake test` (per `CLAUDE.md`) |
| Test command that actually runs | **none — see Runtime gate below** |

## Runtime gate — the suite has never been executed, and currently cannot be

Ran, from a clean shell, exactly what `CLAUDE.md` says to run:

```
nix develop --command bash -c 'export BUNDLE_GEMFILE=$PWD/Gemfile; bundle install'
```

Result:

```
Fetching gem metadata from https://rubygems.org/.......
Resolving dependencies...
Could not find compatible versions
Because kettle-family >= 1.0.0 depends on Ruby >= 4.0.0
  and Gemfile depends on kettle-family >= 1.3.37, < 2.A,
  Ruby >= 4.0.0 is required.
So, because current Ruby version is = 3.4.9,
  version solving has failed.
```

`flake.nix` provisions `ruby_3_4` and the gemspec declares
`required_ruby_version = ">= 3.4"`, but the `Gemfile`/`Gemfile.lock` on this
branch now pin `kettle-dev`/`kettle-test` at versions whose own dependency
(`kettle-family >= 1.3.37`) requires Ruby >= 4.0.0. The dev shell and the
gem lockfile disagree about which Ruby this project runs on, and bundler
refuses to resolve. Nothing downstream of `bundle install` can run: not
`test/test_load.rb`, not `test/test_sync.rb`, not `test/test_cli.rb`, not
`test/drive_main.rb`, not `bundle exec rubocop`. This matches this round's
runtime gate exactly (`drive_ok=false`, 0 checks passed, 0 failed, 0
components covered) — that gate is not a flaky or partial result, it is the
whole suite being unable to start, confirmed by hand just now.

This is the condition the `test-parity` skill's own rule calls out
explicitly: *"A check you could not run is not a check that passed."* The
previous state of this repository (committed test files, a `make test`
target, 362 named `check(...)` call sites — see below) reads as a healthy,
green suite to anyone who does not try to run it. Treat that as the actual
failure mode here: a suite that **looks** executed and has never once been.

## Census

Upstream `main` has **4 test files and 34 test cases**:

- `test/cli/test-argument-parser.vala` — 14 cases
- `test/cli/test-task-validator.vala` — 10 cases
- `test/cli/test-priority-conversion.vala` — 1 case
- `test/core/test-item-sorting.vala` — 8 cases
- `test/test-caldav-integration.vala` — 1 case (CI-gated integration test)

The `ruby` branch has `test/test_load.rb`, `test/test_sync.rb`,
`test/test_cli.rb` and `test/drive_main.rb` (plus `test/gtk_driver.rb`, a
harness file, correctly excluded from the census). Censusing on `check(...)`
— the call that is this suite's actual assertion unit, confirmed by reading
`def check` in each file — finds **362** named cases.

Cross-checked every one of the 34 upstream identifiers
(`add_minimal`, `argument_parser`, `task_validator`, `item-sorting`,
`priority_conversion`, `caldav/login`, …) against the 362 port names: **zero
matches.** The port's suite was written independently of upstream's; it is
not a renaming of the same 34 cases, it is a different suite that happens to
cover some of the same application.

| # | Upstream test | Purpose | Port test | State |
|---|---|---|---|---|
| 1 | `/cli/argument_parser/add_minimal` | `add` with only `--content` fills defaults | — | **gap** |
| 2 | `/cli/argument_parser/add_full` | `add` with every flag set | — | **gap** |
| 3 | `/cli/argument_parser/add_full_with_time` | `add` with a date that includes a time component | — | **gap** |
| 4 | `/cli/argument_parser/no_command` | invoking the CLI with no subcommand is an error | — | **gap** |
| 5 | `/cli/argument_parser/unknown_command` | an unrecognised subcommand is an error | — | **gap** |
| 6 | `/cli/argument_parser/unknown_option` | an unrecognised flag is an error, not silently ignored | — | **gap** |
| 7 | `/cli/argument_parser/missing_required_arg` | a required arg left out is an error | — | **gap** |
| 8 | `/cli/argument_parser/invalid_pin_value` | `--pin` rejects anything but true/false | — | **gap** |
| 9 | `/cli/argument_parser/invalid_complete_value` | `--complete` rejects anything but true/false | — | **gap** |
| 10 | `/cli/argument_parser/list_projects` | `list` enumerates projects | — | **gap** |
| 11 | `/cli/argument_parser/list_with_project` | `list` scoped to one project by name | — | **gap** |
| 12 | `/cli/argument_parser/list_with_project_id` | `list` scoped to one project by id | — | **gap** |
| 13 | `/cli/argument_parser/update_minimal` | `update` with the smallest valid arg set | — | **gap** |
| 14 | `/cli/argument_parser/update_completion` | `update --complete` flips completion state | — | **gap** |
| 15 | `/cli/priority_conversion` | CLI priority ints map correctly to the app's priority enum | — | **gap** |
| 16 | `/cli/task_validator/content_required` | a task with no content is rejected | — | **gap** |
| 17 | `/cli/task_validator/content_empty` | an empty-string content is rejected | — | **gap** |
| 18 | `/cli/task_validator/content_valid` | ordinary content passes | — | **gap** |
| 19 | `/cli/task_validator/priority_range` | priority outside 1-4 is rejected | — | **gap** |
| 20 | `/cli/task_validator/date_format_valid` | accepted date formats parse | — | **gap** |
| 21 | `/cli/task_validator/date_format_invalid` | malformed dates are rejected | — | **gap** |
| 22 | `/cli/task_validator/date_null_or_empty` | null/empty date is accepted (no due date) | — | **gap** |
| 23 | `/cli/task_validator/date_with_time` | date+time together parse | — | **gap** |
| 24 | `/cli/task_validator/date_with_timezone` | date+time+offset parses | — | **gap** |
| 25 | `/cli/task_validator/date_without_timezone` | date+time with no offset assumes local | — | **gap** |
| 26 | `/item-sorting/orders-by-priority-within-the-same-project` | sort stability within one project | — | **gap** |
| 27 | `/item-sorting/breaks-a-priority-tie-by-date-added` | tie-break rule on equal priority | — | **gap** |
| 28 | `/item-sorting/groups-projects-alphabetically-when-ascending` | project grouping order | — | **gap** |
| 29 | `/item-sorting/keeps-priority-highest-first-when-descending` | descending sort keeps highest priority first | — | **gap** |
| 30 | `/item-sorting/never-interleaves-two-projects-sharing-a-name` | same-named projects don't merge in sort | — | **gap** |
| 31 | `/item-sorting/sorts-an-orphaned-task-against-one-with-a-project` | tasks with no project sort correctly against ones that have one | — | **gap** |
| 32 | `/item-sorting/sorts-orphaned-tasks-by-priority-without-dereferencing-null` | null-project tasks don't crash the comparator | — | **gap** |
| 33 | `/item-sorting/returns-zero-only-when-comparing-an-item-with-itself` | comparator reflexivity / no false ties | — | **gap** |
| 34 | `/caldav/login` | CalDAV login flow against a real/test server | — | **gap** |

Every row's **behaviour still owed** is in its Purpose column above; none of
the 34 properties upstream pinned have a Ruby test pinning them, independent
of whether the underlying Ruby code happens to behave correctly.

## Extra

- `test/test_load.rb` — loads every file and asserts the app's object graph constructs; not a port of any upstream test.
- `test/test_sync.rb` — exercises the Todoist/CalDAV sync services; not a port of any upstream test.
- `test/test_cli.rb` — exercises the Ruby CLI end to end; not a port of any upstream test, and does not subsume the 25 `argument_parser`/`task_validator`/`priority_conversion` cases above, because none of those 25 properties is named or asserted by identifier anywhere in it (confirmed: zero of the 34 upstream identifiers appear in the port's 362).
- `test/drive_main.rb` — headless GTK driver; 362 `check(...)` sites total across the four files above, none named after an upstream test.

**The port's suite being five-to-ten times the size of upstream's is not
partial credit.** None of the 362 checks were written from an upstream test;
they are extra, they stay extra, and — per the Runtime gate section above —
none of them has ever actually been run to completion on this branch either.

## Proof checklist

- [ ] Counts equal — 0 vs 34.
- [ ] Mapping is a bijection — 0 of 34 mapped.
- [ ] Each pair tests the same thing — N/A, no pairs exist.
- [ ] Suite passes under its own test target — **it cannot currently run at
  all** (bundler dependency resolution failure, see Runtime gate).

Parity is **0/34**, the suite has **0 proven-passing runs** on this branch
right now, and the correct status of this axis is: broken, not green.
