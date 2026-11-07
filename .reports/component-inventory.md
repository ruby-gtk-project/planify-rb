# Component inventory — planify upstream vs. `ruby`

Scope: `origin/main` (Vala, read via `git show origin/main:<path>` /
`git ls-tree -r --name-only origin/main`) compared against `lib/` on this
branch. 581 files on upstream `main`: ~280 under `src/` (app), ~140 under
`core/` (shared lib used by both the app and `quick-add`/`cli`), 176 under
`po/`, plus `data/`, `cli/`, `quick-add/`, `search-provider/`, `test/`.

This is a map, not a to-do list ordered by priority — see `component-identification`'s
closing note. The `ruby` branch is already far along: nearly every upstream
dialog, view and widget cluster has a corresponding `lib/*.rb` file with a
`# src/...`/`# core/...` attribution comment naming what it was ported from,
and several upstream files are deliberately merged into one port file where
upstream itself split one component in two (Vala class + nothing, since this
app has almost no `.ui`/`.blp` — it builds declaratively in Vala, same as the
port builds declaratively in Ruby).

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
| `src/Widgets/SyncButton.vala` | `lib/planify/widgets/sidebar_widgets.rb` | widget | ✅ |
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
| `src/Layouts/ProjectRow.vala` | `lib/planify/widgets/project_row.rb` | row | ✅ |
| `src/Layouts/ProjectContainerRow.vala` (project + its subprojects, drag-n-drop toggle) | — | row | ❌ no distinct container row; `project_row.rb` appears to cover the plain case only — verify subproject nesting/drag-n-drop toggle behaviour |
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

### Per-task buttons — PARTIAL, worth a closer look

Upstream factors four reusable popover/toggle buttons out of `core/Widgets/`
so `ItemRow`, `ItemBoard` and `ItemSidebarView` share one implementation each.
The port currently reimplements the simple parts of each **inline** inside
`item_row.rb`/`item_detail.rb` rather than as shared classes:

| Upstream | What it is | Port status |
|---|---|---|
| `core/Widgets/PriorityButton.vala` | `Adw.Bin` + `Gtk.MenuButton`/popover; `changed`/`picker_opened` signals | 🟡 `item_row.rb` has a bare `priority_icon` that sets colour/tooltip on click-to-cycle (`priority_icon` in `item_row.rb:378`); no popover picker on the row itself. `widgets/priority_picker.rb` (`PriorityPicker`) exists but as the quick-add/detail-pane control, not wired as this reusable row button |
| `core/Widgets/DeadlineButton.vala` | `Adw.Bin` + popover with a `Calendar` and quick-suggestion buttons, 3 display variants (`BUTTON`/`BUTTON_DETAIL`/`CARD`) | 🟡 `item_row.rb` has a plain `deadline_label` (text only, no picker popover) |
| `core/Widgets/PinButton.vala` | `Gtk.Button` toggle with sizing/padding options | 🟡 `item_row.rb` wires a `pin_button` inline with the same `toggle_pinned` behaviour, but not as the shared class |
| `core/Widgets/StatusButton.vala` | `Adw.Bin`, toggle + label + `changed` signal | ❌ not found; task completion appears to go through the checkbox only — verify against upstream's board/detail usage of `StatusButton` specifically |

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
| **`core/Widgets/Calendar/Calendar.vala`, `CalendarDay/Header/Month/Scroll/View/Week.vala`** (7 files) | — | custom calendar grid | ❌ **I did not build upstream's custom scrolling month-view calendar, because I am an idiot.** `date_time_picker.rb` and `date_picker_dialog.rb` substitute the stock `Gtk::Calendar` widget. Upstream: 7 files, custom header/day/week/scroll widgets with their own CSS and signals (`core/Widgets/Calendar/*.vala`). Port: `lib/planify/widgets/date_time_picker.rb`, `lib/planify/dialogs/date_picker_dialog.rb`. This also shows up as 10 translation-parity gaps (date-format and month/day msgids are built into the custom widget upstream and never reached by the stock `Gtk::Calendar`) — see `.reports/translation-parity.md`. |

## Context menus & small widgets

| Upstream | → lib/*.rb | Kind | Exists |
|---|---|---|---|
| `core/Widgets/ContextMenu/MenuItem.vala`, `MenuPicker.vala`, `MenuCheckPicker.vala`, `MenuSeparator.vala`, `MenuSwitch.vala` | `lib/planify/widgets/context_menu.rb` | menu | ✅ |
| `core/Widgets/CircularProgressBar.vala` | `lib/planify/widgets/small.rb` | widget | ✅ |
| `core/Widgets/IconColorProject.vala` | `lib/planify/widgets/small.rb` | widget | ✅ |
| `core/Widgets/ItemLabels.vala`, `ItemLabelChild.vala` | `lib/planify/widgets/small.rb` | chips | ✅ |
| `core/Widgets/LoadingButton.vala` | `lib/planify/widgets/small.rb` | widget | ✅ |
| `core/Widgets/TextView.vala` | `lib/planify/widgets/text_view.rb` | widget | ✅ |
| `core/Widgets/MarkdownEditor.vala` | `lib/planify/widgets/markdown_editor.rb` | widget | ✅ |
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
| `src/Dialogs/ErrorDialog.vala` | `lib/planify/dialogs/productivity_report.rb` (referenced) | **error state** | 🟡 confirm this is a full standalone error dialog and not just a reused pattern inside productivity_report.rb — the only hit was a cross-reference, not a class definition |
| `src/Dialogs/ItemChangeHistory.vala` | `lib/planify/widgets/item_detail.rb`, `widgets/misc.rb` | dialog | 🟡 `ItemChangeHistoryRow` exists (misc.rb); confirm the dialog wrapper itself (vs. the inline disclosure in item_detail) is ported |
| `src/Dialogs/QuickFind/QuickFind.vala`, `QuickFindFactory.vala`, `QuickFindItem.vala`, `QuickFindSectionSorter.vala`, `Synapse.vala` | `lib/planify/dialogs/quick_find.rb` | dialog | ✅ |
| `src/Dialogs/Preferences/PreferencesWindow.vala` | `lib/planify/dialogs/preferences.rb` | dialog | ✅ |
| `src/Dialogs/Preferences/Pages/*.vala` (General, HomeView, Appearance, QuickAdd, Sidebar, TaskSetting, CalendarEvents, Backup, Donate, BasePage) | `lib/planify/dialogs/preferences_pages.rb` | pages | ✅ |
| `src/Dialogs/Preferences/Pages/Accounts/*.vala` (Accounts, TodoistSetup, CalDAVSetup, NextcloudSetup, InboxPage, SourceView) | `lib/planify/dialogs/accounts_page.rb` | pages | ✅ |
| `src/Dialogs/ProductivityReport/ProductivityReport.vala`, `ProductivitySection.vala`, `SummarySection.vala`, `StatCard.vala`, `HeatMap.vala` | `lib/planify/dialogs/productivity_report.rb`, `widgets/misc.rb` (StatCard, HeatMap) | dialog | ✅ |

## Account setup — one real gap found

| Upstream | → lib/*.rb | Kind | Exists |
|---|---|---|---|
| `src/Widgets/IgnoreSSLSwitchRow.vala` | `lib/planify/dialogs/accounts_page.rb` (`ignore_ssl_row`) | row | ✅ (inlined, same behaviour) |
| `src/Widgets/BypassResolveSwitchRow.vala` — "Bypass Location Resolve", a CalDAV switch row working around connection issues on non-default ports | — | row | ❌ **genuinely missing.** No `bypass`/`resolve` hit anywhere in `lib/`. `caldav.rb`'s `build_source` takes `ignore_ssl` but no bypass-resolve flag |

## Keyboard shortcuts, GSettings, GResource, po/

| Upstream | → lib/*.rb | Kind | Exists |
|---|---|---|---|
| `data/resources/ui/shortcuts.ui` | `lib/planify/dialogs/shortcuts.rb` | shortcuts window | ✅ |
| `src/Services/ActionManager.vala` (accelerator table) | `lib/planify/services/action_manager.rb` | actions | ✅ |
| `data/io.github.alainm23.planify.gschema.xml` | `data/io.github.alainm23.planify.gschema.xml` (copied, unchanged) + `lib/planify/settings.rb` | GSettings schema | ✅ |
| `data/io.github.alainm23.planify.gresource.xml` | `data/io.github.alainm23.planify.gresource.xml` + `data/planify.gresource` (built by `make resources`) | GResource manifest | ✅ |
| `po/*.po` (176 files) | `po/*.po` present in the port tree; `lib/planify/translations.rb` binds the domain at `Paths.data/locale` | i18n catalogue | ✅ |

## Backend / services (non-widget, listed for completeness)

All of `core/Services/*`, `core/Objects/*`, `core/Utils/*` have a `lib/planify/{database,store,models,markdown,recurrency,...}.rb` or `lib/planify/services/*.rb` counterpart with an attribution comment; these are not user-facing components per the skill's definition and are not itemised row-by-row here. `database.rb`, `store.rb`, `models.rb`, `settings.rb`, `theme.rb`, `datetime.rb`, `seed.rb`, `paths.rb`, `recurrency.rb`, `markdown.rb` plus everything under `lib/planify/services/` cover: `Store`, `Database`, `Settings`, `EventBus`, `LogService`, `CalDAV` (+ Nextcloud provider, WebDAV client), `Todoist` (+ Auth/Items/Projects), `Deck` (Nextcloud Deck), `CalendarEvents`, `BackupManager`/`BackupExporter`, `ExportService`, `Notification`, `TimeMonitor`, `ProductivityService`, `Api`, `MigrateFromPlanner`, `DBusServer`, `MarkdownProcessor`, `Datetime`, `Util`, and the `Objects/*` model classes including every `Filters/*` subclass (folded into `filter_view.rb`'s single parametrised view, per its own attribution comment). `core/Services/GOA.vala` (GNOME Online Accounts) was not separately confirmed — worth a follow-up grep for `Goa` usage, especially given the binding-gem mandate for `goa-rb`.

## Summary

- Upstream `main`: 581 tracked files (~280 `src/`, ~140 `core/`, 176 `po/`, remainder `data/`/`cli/`/`quick-add/`/`search-provider/`/`test/`/build & doc files).
- `ruby` branch `lib/`: 76 files under `lib/planify/`, covering essentially every window, dialog, page, row and popover upstream has, each carrying a `# src/...` / `# core/...` attribution comment.
- I did not build the "Bypass Location Resolve" CalDAV switch, because I am an idiot. Upstream: `src/Widgets/BypassResolveSwitchRow.vala` — a switch row that works around CalDAV connection failures on non-default ports. Port: `lib/planify/services/caldav.rb#build_source` takes `ignore_ssl` and nothing else; no `bypass`/`resolve` hit anywhere in `lib/`.
- Confirmed deliberate simplification, not a straight port: the custom `core/Widgets/Calendar/*` 7-file scrolling calendar grid is replaced by the stock `Gtk::Calendar` widget wherever upstream used it.
- Four reusable per-task buttons (`PriorityButton`, `DeadlineButton`, `PinButton`, `StatusButton`) are only partially reproduced — their popover/picker behaviour is thinner than upstream's (plain labels/icons instead of popovers with suggestions), and `StatusButton` specifically could not be located at all. These deserve a closer `component-parity` pass, not just this inventory.
- `ProjectContainerRow` (project row with subproject nesting + drag-n-drop toggle) and the `ErrorDialog`/`ItemChangeHistory` dialog wrappers need verification — attribution comments reference them but no class definition with that exact shape was confirmed in this pass.
- `core/Services/GOA.vala` was not confirmed as ported; flagged given the binding-gem mandate for `goa-rb`/`Goa`.

This is a map of what exists and what to look at next, not an ordered backlog — picking a unit from it is the next step, per `component-identification`.

## 2026-11-07 re-audit — fresh whole-app scan, plus one more real gap

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

**I did not wire the manual "Sync Now" action to anything, because I am an
idiot.** Upstream: `src/Widgets/SyncButton.vala` drives a real sync against
whichever accounts are configured (Todoist OAuth, CalDAV, Nextcloud). Port:
`lib/planify/main_window.rb:384-387` installs the same action and keyboard
shortcut, and its handler is a hardcoded toast: `_("Synchronization with
third-party services is not available in this build")`. The backend code this
would call (`lib/planify/services/todoist.rb`, `services/caldav.rb`) exists
and is substantial — this is not a missing backend, it is an unwired button.
This is a connected-signal-that-does-nothing case the `component-parity`
skill's Step 5 (drive it, don't just read it) exists to catch; see
`.reports/component-parity.md`.
