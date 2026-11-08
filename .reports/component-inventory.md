# Component inventory — planify upstream vs. `ruby`

## 2026-11-08 re-audit — StatusButton, ErrorDialog and ItemChangeHistory confirmed dead code

Re-checked at `HEAD` = `505d4c1dc` (origin/main unchanged at `cc26aaed3`).
`grep -rn "StatusButton" lib/` finds exactly one hit: the class definition
itself (`lib/planify/widgets/status_button.rb:8`). No file anywhere under
`lib/` instantiates it. The prior pass below marked this row "✅ ported;
verify its call sites" — that verification is now done, and the answer is
**no call sites exist at all**. `StatusButton` is not "thinner than upstream"
or partially wired; it is a class that exists and is never used. Corrected
row: `core/Widgets/StatusButton.vala` → `lib/planify/widgets/status_button.rb`
→ 🟡 **class exists, zero call sites — dead code, not reachable from any
window.**

Same check for the two dialogs the prior pass could only "cross-reference":
`Dialogs::ItemChangeHistory` and `Dialogs::ErrorDialog` are both now real,
named classes in `lib/planify/dialogs/productivity_report.rb:231` and `:292`
respectively — that part of the prior note is resolved. But
`grep -rn "ErrorDialog.new\|ItemChangeHistory.new" lib/` finds **zero**
matches anywhere in the tree. Neither class is ever instantiated. Upstream's
`ErrorDialog` is what a failed sync or corrupt database shows the user
(`src/Dialogs/ErrorDialog.vala`); the port's actual error path
(`main_window.rb`'s `#sync`) shows a toast instead and never reaches this
class. Upstream's `ItemChangeHistory` is a dedicated dialog opened from a
task's detail pane; the port only shows the equivalent rows inline
(`item_detail.rb:248`), never through the dialog shape that exists for it.
Corrected rows:

| Upstream | → lib/*.rb | Kind | Exists |
|---|---|---|---|
| `src/Dialogs/ErrorDialog.vala` | `lib/planify/dialogs/productivity_report.rb` (`ErrorDialog` class) | **error state** | 🟡 class exists, zero call sites anywhere in `lib/` — no error path opens it, so no user ever sees the error dialog upstream ships |
| `src/Dialogs/ItemChangeHistory.vala` | `lib/planify/dialogs/productivity_report.rb` (`ItemChangeHistory` class) | dialog | 🟡 class exists, zero call sites anywhere in `lib/` — the detail pane shows the same rows inline (`item_detail.rb:248`) but nothing ever opens this dialog |

This is the same failure mode `component-parity.md` records for `SyncButton`
(a connected-looking shape that does nothing when reached) one level up: here
the shape is not even reached. A grep for the class name is not enough to
call a component ported; `grep -c '\.new'` on it is the next check, and these
three rows failed it.

## 2026-11-08 — runtime gate re-verified, corrects a false claim made one layer up

`.reports/component-parity.md` and `.reports/test-parity.md`, as they stood
before this pass, both say the runtime gate is down and `bundle install`
cannot resolve. That was true of the command they ran
(`BUNDLE_GEMFILE=$PWD/Gemfile bundle install`, which targets the repo-root
`Gemfile` — the `kettle-jem` development bundle, not the app's runtime
dependencies) but it is not true of the command the dev shell and `CLAUDE.md`
actually run: entering `nix develop` sets `BUNDLE_GEMFILE` to `nix/Gemfile`
(the generated runtime gemset — `adwaita`, `gtk4`, `ashpd`, `edataserver`,
`goa-rb`, `libspelling`, `soup3`, `sqlite3`, `gettext`, `base64`, `rexml`,
nothing from the kettle-dev stack), and under that Gemfile `bundle check`
reports "The Gemfile's dependencies are satisfied" and
`GSETTINGS_SCHEMA_DIR=$PWD/data nix develop --command xvfb-run -a bundle exec
ruby test/drive_main.rb` runs to completion: **107 of 107 checks passed,
DRIVE OK**, matching this round's runtime gate exactly. `test_load.rb`,
`test_sync.rb` and `test_cli.rb` also pass in full under the same shell. See
`.reports/accountability-ensurance.md` for this corrected as a finding
against the audit, not just the code — the prior reports' "nothing can run"
conclusion was itself wrong, not a flaky observation.

**What is still actually broken, confirmed independently**: `make test` — the
one command `CLAUDE.md` and the dev shell's own banner both name as "check it
all" — fails immediately: `bundle exec rubocop` exits "command not found:
rubocop", because `rubocop` lives only in the root `Gemfile` (the
kettle-dev/style bundle), not in `nix/Gemfile` (the runtime gemset the dev
shell's `BUNDLE_GEMFILE` points at). The documented single entrypoint for
verifying a change does not run end to end in the shell `CLAUDE.md` tells a
contributor to use. See `.reports/test-parity.md`.

Scope: `origin/main` (Vala, read via `git show origin/main:<path>` /
`git ls-tree -r --name-only origin/main`) compared against `lib/` on this
branch, as of `HEAD` = `ce4a3dc00` ("Add drive checks that exercise ashpd and
libspelling directly"). 581 files on upstream `main`: ~280 under `src/` (app),
~140 under `core/` (shared lib used by both the app and `quick-add`/`cli`),
176 under `po/`, plus `data/`, `cli/`, `quick-add/`, `search-provider/`,
`test/`.

This is a map, not a to-do list ordered by priority — see
`component-identification`'s closing note. The `ruby` branch is far along:
every upstream dialog, view and widget cluster has a corresponding
`lib/*.rb` file with a `# src/...`/`# core/...` attribution comment naming
what it was ported from, and several upstream files are deliberately merged
into one port file where upstream itself split one component across several
(this app has almost no `.ui`/`.blp` — it builds declaratively in Vala, same
as the port builds declaratively in Ruby).

**This supersedes the earlier pass recorded lower in this file (dated
2026-11-07, before commit `82bf29cf4`).** Three items flagged there as gaps
have since been closed and are corrected below:
`src/Layouts/ProjectContainerRow.vala`, `src/Widgets/BypassResolveSwitchRow.vala`,
and the four per-task popover buttons (`PinButton`, `PriorityButton`,
`DeadlineButton`, `StatusButton`). The historical record is left intact
underneath for the audit trail; treat the tables below as current.

Legend: ✅ exists and attributed · 🟡 exists but folded/simplified (see note)
· ❌ no corresponding code on `ruby`.

## Windows & application

| Upstream | → lib/*.rb | Kind | Exists |
|---|---|---|---|
| `src/App.vala` | `lib/planify/application.rb` | window/app | ✅ |
| `src/MainWindow.vala` | `lib/planify/main_window.rb` | window | ✅ |
| `src/Layouts/HeaderBar.vala` | `lib/planify/main_window.rb` (inline) | widget | 🟡 folded into `MainWindow`'s own header, not a standalone reusable class |
| `quick-add/App.vala`, `quick-add/MainWindow.vala`, `quick-add/Services/DBusClient.vala` | `lib/planify/quick_add_application.rb` | window/app | ✅ |
| `cli/*.vala` (6 files) | `lib/planify/cli.rb` | CLI | ✅ |
| `search-provider/*.vala` | `lib/planify/services/dbus_server.rb` | GNOME Shell search provider | ✅ (noted in attribution comment) |

## Sidebar

| Upstream | → lib/*.rb | Kind | Exists |
|---|---|---|---|
| `src/Layouts/Sidebar.vala` | `lib/planify/sidebar.rb` | page | ✅ |
| `src/Layouts/SidebarSourceRow.vala` | `lib/planify/widgets/sidebar_widgets.rb` | row | ✅ |
| `src/Widgets/SyncButton.vala` | `lib/planify/widgets/sidebar_widgets.rb` | widget | 🟡 built and wired to `win.sync`, but the handler (`main_window.rb`'s `#sync`) is a hardcoded "not available in this build" toast — see Backend note below |
| `src/Widgets/MagicButton.vala` | `lib/planify/widgets/sidebar_widgets.rb` | widget (floating add button) | ✅ |
| `src/Widgets/MultiSelectToolbar.vala` | `lib/planify/widgets/sidebar_widgets.rb`, `lib/planify/main_window.rb` | widget/mode | ✅ |
| `src/Widgets/NewVersionPopup.vala` | `lib/planify/widgets/misc.rb` | empty/notice state | ✅ |
| `src/Layouts/FilterPaneRow.vala`, `FilterPaneChild.vala` | `lib/planify/widgets/filter_flow_box.rb` | row/tile | ✅ |
| `src/Widgets/FilterFlowBox.vala`, `FilterFlowBoxChild.vala` | `lib/planify/widgets/filter_flow_box.rb` | widget | ✅ |

## Views

| Upstream | → lib/*.rb | Kind | Exists |
|---|---|---|---|
| `src/Views/Today.vala` | `lib/planify/views/today_view.rb` | page | ✅ |
| `src/Views/Filter.vala` (+ Pinboard/label filter reuse) | `lib/planify/views/filter_view.rb` | page | ✅ |
| `src/Views/Project/Project.vala`, `Board.vala`, `List.vala` | `lib/planify/views/project_view.rb` | page | ✅ |
| `src/Views/Scheduled/Scheduled.vala`, `ScheduledDay/Month/Overdue/Range/Section.vala` | `lib/planify/views/scheduled_view.rb` | page | ✅ |
| `src/Views/Label/Labels.vala`, `Label.vala`, `LabelSourceRow.vala` | `lib/planify/views/labels_view.rb` | page | ✅ |
| `lib/planify/views/base_view.rb`, `sorting.rb` | — | shared base/sort helper, no single upstream file (cross-cutting) | ✅ |

## Rows, boards & the task detail pane

| Upstream | → lib/*.rb | Kind | Exists |
|---|---|---|---|
| `src/Layouts/ItemRow.vala` | `lib/planify/widgets/item_row.rb` | row | ✅ |
| `src/Layouts/ItemBase.vala` (abstract base ItemRow/ItemBoard share) | `lib/planify/widgets/item_row.rb`, `section_board.rb` (inline) | base class | 🟡 no standalone Ruby module; shared bits duplicated across the two files |
| `src/Layouts/ItemBoard.vala` | `lib/planify/widgets/section_board.rb` | card | ✅ |
| `src/Layouts/SectionBoard.vala` | `lib/planify/widgets/section_board.rb` | column | ✅ |
| `src/Layouts/SectionRow.vala` | `lib/planify/widgets/section_row.rb` | row | ✅ |
| `src/Layouts/ProjectRow.vala` + `src/Layouts/ProjectContainerRow.vala` | `lib/planify/widgets/project_row.rb` | row | ✅ merged (per its own attribution comment): the reveal-in/hide-destroy slide animation `ProjectContainerRow` added is folded into `ProjectRow`, the same way `LabelRow` merges its own container |
| `src/Layouts/LabelRow.vala` | `lib/planify/widgets/label_row.rb` | row | ✅ |
| `src/Layouts/ItemSidebarView.vala` | `lib/planify/widgets/item_detail.rb` | detail pane | ✅ |
| `src/Widgets/SubItems.vala` | `lib/planify/widgets/item_detail.rb` | subtask list | ✅ |
| `src/Widgets/PinnedItemsBox.vala` | `lib/planify/views/project_view.rb`, `widgets/filter_flow_box.rb` | widget | ✅ |
| `src/Widgets/AttachmentRow.vala`, `Attachments.vala` | `lib/planify/widgets/attachments.rb` | row/widget | ✅ |
| `src/Widgets/EditableTextView.vala` | `lib/planify/widgets/editable_text_view.rb` | widget | ✅ |
| `src/Widgets/CompletedTaskRow.vala` | `lib/planify/widgets/misc.rb` | row | ✅ |
| `src/Widgets/ItemChangeHistoryRow.vala` | `lib/planify/widgets/misc.rb` | row | ✅ |
| `src/Widgets/ReorderChild.vala` | `lib/planify/widgets/reorder_child.rb` | wrapper | ✅ |
| `src/Widgets/SectionsOrderPopover.vala` | `lib/planify/widgets/sections_order_popover.rb` | popover | ✅ |

### Per-task buttons — now ported as standalone classes

Upstream factors four reusable popover/toggle buttons out of `core/Widgets/`
so `ItemRow`, `ItemBoard` and `ItemSidebarView` share one implementation each.
These were previously only reimplemented inline; they are now standalone
files, each with its own attribution comment, and the first three are wired
into `ItemRow`'s quick-edit actions:

| Upstream | → lib/*.rb | Kind | Exists |
|---|---|---|---|
| `core/Widgets/PriorityButton.vala` | `lib/planify/widgets/priority_button.rb` | popover button | ✅ wired into `item_row.rb` |
| `core/Widgets/DeadlineButton.vala` | `lib/planify/widgets/deadline_button.rb` | popover button | ✅ wired into `item_row.rb` |
| `core/Widgets/PinButton.vala` | `lib/planify/widgets/pin_button.rb` | toggle button | ✅ wired into `item_row.rb`, replacing the previously-inert pin icon |
| `core/Widgets/StatusButton.vala` | `lib/planify/widgets/status_button.rb` | card menu button | ✅ ported; verify its call sites (board/detail) match every place upstream uses `StatusButton` specifically, vs. the plain checkbox |

## Pickers

| Upstream | → lib/*.rb | Kind | Exists |
|---|---|---|---|
| `core/Widgets/DateTimePicker/DateTimePicker.vala`, `ScheduleButton.vala`, `TimePicker.vala` | `lib/planify/widgets/date_time_picker.rb` | popover | ✅ |
| `core/Widgets/DateTimePicker/RepeatConfig.vala` | `lib/planify/widgets/repeat_config.rb` | disclosure | ✅ |
| `core/Widgets/LabelPicker/LabelPicker.vala`, `LabelButton.vala`, `LabelQuickPicker.vala`, `LabelRow.vala`, `LabelsPickerCore.vala` | `lib/planify/widgets/label_picker.rb` | popover | ✅ |
| `core/Widgets/ProjectPicker/ProjectPickerCore.vala`, `ProjectPickerButton.vala`, `ProjectPickerPopover.vala`, `ProjectPickerRow.vala` | `lib/planify/widgets/project_picker.rb` | popover | ✅ |
| `core/Widgets/SectionPicker/SectionPicker.vala`, `SectionButton.vala`, `SectionPickerRow.vala` | `lib/planify/widgets/project_picker.rb` | popover | ✅ (merged into the same file as ProjectPicker, per its own attribution comment) |
| `core/Widgets/ReminderPicker/ReminderPicker.vala`, `ReminderButton.vala`, `ReminderRow.vala` | `lib/planify/widgets/reminder_picker.rb` | popover | ✅ |
| `core/Widgets/ColorPickerRow.vala` | `lib/planify/widgets/color_picker.rb` | row | ✅ |
| `lib/planify/widgets/emoji_picker.rb` | — | popover | ✅ (project icon; no single upstream file name recovered in this pass — likely `core/Widgets/IconColorProject.vala`'s picker half, worth confirming) |
| **`core/Widgets/Calendar/Calendar.vala`, `CalendarDay/Header/Month/Scroll/View/Week.vala`** (7 files) | — | custom calendar grid | ❌ **still not ported.** `date_time_picker.rb` and `date_picker_dialog.rb` substitute the stock `Gtk::Calendar` widget. Upstream: 7 files, custom header/day/week/scroll widgets with their own CSS and signals (`core/Widgets/Calendar/*.vala`). Port: `lib/planify/widgets/date_time_picker.rb`, `lib/planify/dialogs/date_picker_dialog.rb`. This also shows up as 10 translation-parity gaps (date-format and month/day msgids are built into the custom widget upstream and never reached by the stock `Gtk::Calendar`) — see `.reports/translation-parity.md`. |

## Context menus & small widgets

| Upstream | → lib/*.rb | Kind | Exists |
|---|---|---|---|
| `core/Widgets/ContextMenu/MenuItem.vala`, `MenuPicker.vala`, `MenuCheckPicker.vala`, `MenuSeparator.vala`, `MenuSwitch.vala` | `lib/planify/widgets/context_menu.rb` | menu | ✅ |
| `core/Widgets/CircularProgressBar.vala` | `lib/planify/widgets/small.rb` | widget | ✅ |
| `core/Widgets/IconColorProject.vala` | `lib/planify/widgets/small.rb` | widget | ✅ |
| `core/Widgets/ItemLabels.vala`, `ItemLabelChild.vala` | `lib/planify/widgets/small.rb` | chips | ✅ |
| `core/Widgets/LoadingButton.vala` | `lib/planify/widgets/small.rb` | widget | ✅ |
| `core/Widgets/TextView.vala` | `lib/planify/widgets/text_view.rb` | widget | ✅ |
| `core/Widgets/MarkdownEditor.vala` | `lib/planify/widgets/markdown_editor.rb` | widget | ✅ (now backed by `libspelling` for inline spellchecking, per its `require` and attribution comment) |
| `src/Widgets/ComboWrapRow.vala` | `lib/planify/widgets/combo_wrap_row.rb` | row | ✅ |
| `src/Widgets/LabelsSummary.vala` | `lib/planify/widgets/small.rb` | widget | ✅ |
| `src/Widgets/ScrolledWindow.vala` | `lib/planify/widgets/small.rb` | widget | ✅ |
| `src/Widgets/ErrorView.vala` | `lib/planify/widgets/small.rb` | **error state** | ✅ |
| `src/Widgets/EventRow.vala`, `EventsList.vala` | `lib/planify/widgets/misc.rb` | row/list | ✅ |
| `src/Widgets/TranslationRow.vala` | `lib/planify/widgets/translation_row.rb` | row | ✅ |
| `src/Widgets/ProductivityMiniWidget.vala` | `lib/planify/widgets/misc.rb` | widget | ✅ |

## Dialogs

| Upstream | → lib/*.rb | Kind | Exists |
|---|---|---|---|
| `src/Dialogs/DatePicker.vala` | `lib/planify/dialogs/date_picker_dialog.rb` | dialog | ✅ |
| `src/Dialogs/CalendarSync.vala` | `lib/planify/dialogs/date_picker_dialog.rb` (`CalendarSync` class) | dialog | ✅ |
| `src/Dialogs/ManageProjects.vala` | `lib/planify/dialogs/manage.rb` | dialog | ✅ |
| `src/Dialogs/ManageSectionOrder.vala` | `lib/planify/dialogs/manage.rb` (`ManageSectionOrder` class) | dialog | ✅ |
| `src/Dialogs/CompletedTasks.vala` | `lib/planify/dialogs/manage.rb` (`CompletedTasks` class) | dialog | ✅ |
| `src/Dialogs/Project.vala` | `lib/planify/dialogs/project_dialog.rb` | dialog | ✅ |
| `src/Dialogs/Section.vala` | `lib/planify/dialogs/section_dialog.rb` | dialog | ✅ |
| `src/Dialogs/Label.vala` | `lib/planify/dialogs/label_dialog.rb` | dialog | ✅ |
| `src/Dialogs/LabelPicker.vala`, `src/Dialogs/ProjectPicker.vala` (dialog-form pickers, vs. the popover core widgets above) | `lib/planify/widgets/label_picker.rb`, `widgets/project_picker.rb` | dialog variant | ✅ (per their attribution comments — "the same pickers as the popover, as a dialog") |
| `src/Dialogs/QuickAdd.vala` | `lib/planify/widgets/quick_add.rb` | dialog | ✅ (core widget + dialog shell merged) |
| `src/Dialogs/ErrorDialog.vala` | `lib/planify/dialogs/productivity_report.rb` (referenced) | **error state** | 🟡 still only a cross-reference found, not a standalone class definition with this exact shape — confirm whether a general-purpose error dialog exists or whether every error path uses an ad-hoc toast/banner instead |
| `src/Dialogs/ItemChangeHistory.vala` | `lib/planify/widgets/item_detail.rb`, `widgets/misc.rb` | dialog | 🟡 `ItemChangeHistoryRow` exists (misc.rb); confirm the dialog wrapper itself (vs. the inline disclosure in item_detail) is ported |
| `src/Dialogs/QuickFind/QuickFind.vala`, `QuickFindFactory.vala`, `QuickFindItem.vala`, `QuickFindSectionSorter.vala`, `Synapse.vala` | `lib/planify/dialogs/quick_find.rb` | dialog | ✅ |
| `src/Dialogs/Preferences/PreferencesWindow.vala` | `lib/planify/dialogs/preferences.rb` | dialog | ✅ |
| `src/Dialogs/Preferences/Pages/*.vala` (General, HomeView, Appearance, QuickAdd, Sidebar, TaskSetting, CalendarEvents, Backup, Donate, BasePage) | `lib/planify/dialogs/preferences_pages.rb` | pages | ✅ |
| `src/Dialogs/Preferences/Pages/Accounts/*.vala` (Accounts, TodoistSetup, CalDAVSetup, NextcloudSetup, InboxPage, SourceView) | `lib/planify/dialogs/accounts_page.rb` | pages | ✅ |
| `src/Dialogs/ProductivityReport/ProductivityReport.vala`, `ProductivitySection.vala`, `SummarySection.vala`, `StatCard.vala`, `HeatMap.vala` | `lib/planify/dialogs/productivity_report.rb`, `widgets/misc.rb` (StatCard, HeatMap) | dialog | ✅ |

## Account setup

| Upstream | → lib/*.rb | Kind | Exists |
|---|---|---|---|
| `src/Widgets/IgnoreSSLSwitchRow.vala` | `lib/planify/dialogs/accounts_page.rb` (`ignore_ssl_row`) | row | ✅ (inlined, same behaviour) |
| `src/Widgets/BypassResolveSwitchRow.vala` — "Bypass Location Resolve", a CalDAV switch row working around connection issues on non-default ports | `lib/planify/widgets/caldav_bypass_row.rb` | row | ✅ ported as a standalone class and wired into the CalDAV setup form; `services/caldav.rb#discover` honours the flag by skipping the principal/calendar-home PROPFIND chain |

## Keyboard shortcuts, GSettings, GResource, po/

| Upstream | → lib/*.rb | Kind | Exists |
|---|---|---|---|
| `data/resources/ui/shortcuts.ui` | `lib/planify/dialogs/shortcuts.rb` | shortcuts window | ✅ |
| `src/Services/ActionManager.vala` (accelerator table) | `lib/planify/services/action_manager.rb` | actions | ✅ |
| `data/io.github.alainm23.planify.gschema.xml` | `data/io.github.alainm23.planify.gschema.xml` (copied, unchanged) + `lib/planify/settings.rb` | GSettings schema | ✅ |
| `data/io.github.alainm23.planify.gresource.xml` | `data/io.github.alainm23.planify.gresource.xml` + `data/planify.gresource` (built by `make resources`) | GResource manifest | ✅ |
| `po/*.po` (176 files) | `po/*.po` present in the port tree; `lib/planify/translations.rb` binds the domain at `Paths.data/locale` | i18n catalogue | ✅ |

## Backend / services (non-widget, listed for completeness)

All of `core/Services/*`, `core/Objects/*`, `core/Utils/*` have a `lib/planify/{database,store,models,markdown,recurrency,...}.rb` or `lib/planify/services/*.rb` counterpart with an attribution comment; these are not user-facing components per the skill's definition and are not itemised row-by-row here. `database.rb`, `store.rb`, `models.rb`, `settings.rb`, `theme.rb`, `datetime.rb`, `seed.rb`, `paths.rb`, `recurrency.rb`, `markdown.rb` plus everything under `lib/planify/services/` cover: `Store`, `Database`, `Settings`, `EventBus`, `LogService`, `CalDAV` (+ Nextcloud provider, WebDAV client), `Todoist` (+ Auth/Items/Projects), `Deck` (Nextcloud Deck), `CalendarEvents` (now via `edataserver`/`EDataServer`), `BackupManager`/`BackupExporter`, `ExportService`, `Notification`, `TimeMonitor`, `ProductivityService`, `Api` (now via `soup3`/`Soup`), `MigrateFromPlanner`, `DBusServer`, `MarkdownProcessor`, `Datetime`, `Util`, and the `Objects/*` model classes including every `Filters/*` subclass (folded into `filter_view.rb`'s single parametrised view, per its own attribution comment). `core/Services/GOA.vala` is now confirmed ported as `lib/planify/services/goa.rb`, requiring `goa-rb` → `Goa`.

**One real behavioural gap remains, confirmed still present at `HEAD`:**
`src/Widgets/SyncButton.vala` drives a real sync against whichever accounts
are configured. The port's button and `win.sync` action exist
(`lib/planify/widgets/sidebar_widgets.rb`, `main_window.rb`), but the handler
(`main_window.rb`'s `#sync`, ~line 387) is a hardcoded toast —
`_("Synchronization with third-party services is not available in this
build")` — rather than calling into `services/todoist.rb` / `services/caldav.rb`,
which otherwise exist and are substantial. This is a connected-signal-that-
does-nothing case, the kind `component-parity`'s "drive it, don't just read
it" step exists to catch.

## Mandatory binding-gem wiring — re-checked at `HEAD`, holds

Per the task's gem-wiring mandate, re-verified at this commit:

| Gem | Required from | Namespace used |
|---|---|---|
| `ashpd` | `lib/planify/theme.rb` | `Ashpd` (dark-mode detection via xdg-desktop-portal Settings) |
| `edataserver` | `lib/planify/services/calendar_events.rb` | `EDataServer` |
| `goa-rb` | `lib/planify/services/goa.rb` | `Goa` |
| `libspelling` | `lib/planify/widgets/markdown_editor.rb` | `Spelling` |
| `soup3` | `lib/planify/services/http.rb` | `Soup` |

All five are declared in `planify-rb.gemspec` (lines 130–134) and all five are
`require`d from exactly the `lib/` file whose namespace needs them. No
undeclared-but-required or declared-but-unused gem found in this pass.
`sqlite3`, `gettext`, `base64` and `rexml` are also declared and required
(added in `82bf29cf4` after being found missing). This was not re-driven live
in this survey pass — see `ce4a3dc00`/`2025d868e` for the drive checks that
exercise `ashpd` and `libspelling` directly, and the earlier commits for the
others — this pass only re-reads the wiring for regression.

## Summary (current)

- Upstream `main`: 581 tracked files (~280 `src/`, ~140 `core/`, 176 `po/`,
  remainder `data/`/`cli/`/`quick-add/`/`search-provider/`/`test/`/build & doc
  files).
- `ruby` branch `lib/`: 85 files under `lib/planify/` (up from 76 at the last
  pass — the four per-task buttons and the CalDAV bypass row are now their
  own files), covering essentially every window, dialog, page, row and
  popover upstream has, each carrying a `# src/...` / `# core/...` attribution
  comment.
- **Closed since the last pass**: `ProjectContainerRow` (merged into
  `project_row.rb`), `BypassResolveSwitchRow` (`caldav_bypass_row.rb`), and
  all four per-task popover buttons (`pin_button.rb`, `priority_button.rb`,
  `deadline_button.rb`, `status_button.rb`), wired into `item_row.rb`.
- **Still open**: the custom 7-file scrolling `core/Widgets/Calendar/*` grid
  (deliberate simplification to stock `Gtk::Calendar`); the manual "Sync Now"
  action, which is wired to a hardcoded "not available" toast instead of the
  existing Todoist/CalDAV backends; `ErrorDialog` and `ItemChangeHistory`'s
  standalone dialog wrapper, both still only cross-referenced rather than
  confirmed as distinct classes; `StatusButton`'s call sites need checking
  against every upstream usage (board/detail), not just that the class now
  exists.

This is a map of what exists and what to look at next, not an ordered
backlog — picking a unit from it is the next step, per
`component-identification`.

---

## Historical record — earlier passes (superseded above, kept for the audit trail)

### 2026-11-07 re-audit — fresh whole-app scan, plus one more real gap

Re-ran `component-scan.sh` against `origin/main` @ `cc26aaed3` and this branch
@ `784980523`:

| Axis | Upstream distinct | Port distinct | In upstream, not in port |
|---|---:|---:|---:|
| Widget types | 77 | 59 | 24 |
| CSS classes | 100 | 47 | — (set, not count; see `component-parity`) |
| Signals (attachment sites) | 201 | 38 | 173 |

(The symbol-table GIR filter was not rebuilt for this pass — these are the
scanner's raw counts, a lead per `component-identification` Step 4, not a
verdict. The signal gap is large enough on its own that no plausible amount of
over-reporting closes it.)

At that pass, `src/Widgets/SyncButton.vala`'s manual "Sync Now" action was
found wired to a hardcoded toast rather than a real sync. **This finding is
unchanged** — see the current Backend section above; it is still true at
`HEAD`.

At that pass, the following were flagged as open gaps and have since been
closed (see the current tables above for their resolution):
`src/Layouts/ProjectContainerRow.vala`, `src/Widgets/BypassResolveSwitchRow.vala`,
and the `PriorityButton`/`DeadlineButton`/`PinButton`/`StatusButton` quartet.
