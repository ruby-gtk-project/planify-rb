# Planify — Ruby port

This branch is the Ruby GTK4 / Libadwaita port of Planify. The original Vala
implementation lives on this fork's `main` branch and is the spec — read it,
don't copy it. `README.md` covers what is ported, what is not, and how to run
it.

## Skills — use them

Two skills are installed in `.claude/skills/`. They are not optional reading.

- **ruby-gtk** — the house style for Ruby GTK4/Libadwaita: the declarative
  memoized-widget pattern, Adwaita binding quirks, worked examples. Load it
  before writing or reviewing ANY Ruby GTK code, including single widgets, and
  before planning a port. The bindings are quirky enough that code written from
  memory is unreliable.
- **ruby-gtk-testing** — run the app headlessly and drive its UI: click through
  dialogs, assert widget state, capture screenshots. Use it before claiming any
  GTK change works. `ruby -c` and a successful `require` prove nothing about a
  UI.

## Setup

`direnv allow` (or `nix develop`) gets Ruby, GTK4, Libadwaita, SQLite and the
introspection typelibs. Then `bundle install`.

Two generated files have to exist before the app runs, and `make resources`
builds both:

- `data/gschemas.compiled` — the settings schema. Planify reads its own
  `io.github.alainm23.planify` GSettings schema, unchanged from upstream.
- `data/planify.gresource` — the icon and stylesheet bundle. Planify's ~90
  symbolic icons only resolve through a resource path, because the source tree
  stores them flat rather than in an icon-theme layout.

Everything is run through the dev shell:

```sh
nix develop --command make resources
nix develop --command bundle exec rubocop
GSETTINGS_SCHEMA_DIR=$PWD/data nix develop --command bundle exec ruby test/test_load.rb
GSETTINGS_SCHEMA_DIR=$PWD/data nix develop --command \
  env -u DISPLAY -u WAYLAND_DISPLAY bundle exec ruby test/drive_main.rb
```

`bin/planify-dev` sets both paths and points `XDG_DATA_HOME` at `tmp/`, so a
development run cannot touch a real task database.

## Layout

- `lib/planify/` — `database.rb` and `store.rb` are the backend (upstream's
  `core/Services`), `models.rb` the objects, and everything under `widgets/`,
  `views/` and `dialogs/` the frontend (upstream's `src/`).
- `Store.instance` is the only writer to the database and the only source of
  change events; views subscribe with `store.on(:event, owner: self)` and
  unsubscribe by owner when they are dropped.
- `theme.rb` overrides the stylesheet's `@define-color` values at runtime, the
  way `Util.update_theme` does upstream. Without it the shipped stylesheet
  paints a light window under a dark theme.

## Style

`.rubocop.yml` plus the custom cops in `cops/` are enforced: no `return`, no
modifier `if`, no conditional assignment, `tap` where it applies, and fixed
multi-line argument/hash layout. Run `bundle exec rubocop` before committing.
