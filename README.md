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

**Elsewhere** — quick add with natural-language parsing (`buy milk tomorrow p1
@home`), quick find across tasks, projects and labels, preferences (general,
appearance, backups), keyboard shortcuts, JSON backup export and import, the
tutorial project and default labels on first run, and all three appearances
(light, dark, dark blue) with the system accent colour.

## What is not here

**Synchronisation.** Todoist, Nextcloud, CalDAV and Google Tasks are not
ported. That is roughly a third of the upstream source — four service clients,
OAuth, an offline write queue and conflict resolution — and it is its own
piece of work rather than part of the initial port. The `Sync` action and menu
item exist and say so; the database keeps its `Sources`-shaped columns so a
later sync port has nothing to migrate.

Also not ported: system calendar event display, desktop reminder
notifications, the DBus server and its search provider, the quick-add
standalone binary, drag-and-drop reordering, and the Markdown editor (task
descriptions are plain text).

## License

GPL-3.0-or-later, as upstream. See `LICENSE`.
