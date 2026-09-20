# Planify (Ruby port)

Forget about forgetting things.

This is the Ruby GTK4 / Libadwaita port of
[Planify](https://github.com/alainm23/planify). The original Vala
implementation is on this fork's `main` branch.

It reads and writes Planify's own SQLite database at
`~/.local/share/io.github.alainm23.planify/database.db`, using the same schema,
and its own `io.github.alainm23.planify` GSettings schema. An existing Planify
install opens here untouched, and its backups import and export in the same
JSON both builds read.

## Running it

```sh
nix develop        # or: direnv allow
bundle install
make run
```

`make test` runs RuboCop, the logic checks, and a headless drive of the real
window that screenshots each step into `tmp/shots/`.

## What is here

**Views** — Inbox, Today (with its overdue banner), Scheduled, Pinboard,
Completed, Anytime, Repeating, Unlabeled, Tomorrow, the Labels list, a
per-label view, and the project view in both list and board layouts.

**Tasks** — create, edit, complete, uncomplete, duplicate, move between
projects and sections, pin, trash with undo, subtasks that complete with their
parent, descriptions, deadlines, priorities, labels, and recurrence (minutely
through yearly, including last-day-of-month, with end-after-N and end-on-date).

**Projects and sections** — create, edit, duplicate, archive, delete, colour,
emoji or progress-ring icon, subprojects, favourites, per-project completed
visibility.

**Labels** — create, edit, delete (detaching from every task that carried it),
colour, per-label filtering.

**Synchronisation** — Todoist over its v1 sync API, and CalDAV, both with an
offline write queue: a change made with no network reaches the server on the
next sync, in the order it was made. Nextcloud is a CalDAV account with
optional Deck sync, where boards become projects, stacks sections and cards
tasks. Todoist signs in by OAuth or by a personal API token.

**Descriptions** are Markdown, styled as you type rather than rendered, so the
source stays editable: bold, italic, underline, code, links, headings, quotes,
bullets, numbered lists and checkboxes, with Ctrl+B/I/U and list continuation.

**Reminders and calendars** — absolute and relative reminders that fire as
desktop notifications, a midnight monitor that rolls the day over, and the
system's own calendar events shown beside the day's tasks through Evolution
Data Server.

**Elsewhere** — quick add with natural-language parsing (`buy milk tomorrow p1
@home`), quick find across tasks, projects and labels, a productivity report
with goals, streak and a year-long heat map, per-task change history recorded
by the database itself, attachments, preferences across six pages, the full
keyboard shortcut set, JSON backup export, import and automatic daily backups,
import from a Planner-era database, the tutorial project and default labels on
first run, and all three appearances (light, dark, dark blue) with the system
accent colour.

**Beyond the window** — `planify-cli` adds, lists, updates and backs up from a
terminal and tells a running window over DBus; `planify-quick-add` is a
standalone capture window for a desktop shortcut; and the GNOME Shell search
provider answers overview searches.

## What is not here

**Google Tasks.** Upstream carries a `GOOGLE_TASKS` source type and the GNOME
Online Accounts plumbing for it, but no client; there is nothing to port.

**Drag-and-drop reordering inside a list.** Cards drag between board columns;
reordering a list is done from Manage Projects and Section Order instead.

## License

GPL-3.0-or-later, as upstream. See `LICENSE`.
