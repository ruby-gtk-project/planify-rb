# planify-rb — upstream component inventory

Survey of `origin/main` (Vala/GTK4/libadwaita) against `lib/` on the `ruby`
branch. Method: the `component-identification` skill — upstream extracted to a
scratch tree, `component-scan.sh` run on both sides, then every user-facing
file read or spot-read and joined to the port file that carries it. Upstream
splits nothing between a source file and a `.ui`, so each upstream row here is
one file.

## Totals

| | upstream | `ruby` branch |
|---|---:|---:|
| scan rows | 2927 | 809 |
| widget instances | 2830 | 724 |
| distinct widget types | 77 | 55 |
| distinct CSS classes (scan) | 100 | 47 |
| distinct CSS classes (direct grep) | 141 | 47 |
| distinct signals | 201 | 37 |
| source files (`.vala`) | 228 | 85 (`.rb`) |

Re-run on 2026-11-02, after `Port HeaderItem, ReorderChild, TextView and the
rows built on them`. The upstream figures are unchanged from the first survey;
the port's four columns are the nine classes that commit added. The scan's CSS
stream under-counts both sides because it reads only the first string of a
multi-element `css_classes = { "a", "b" }` initialiser, so the CSS section
below is computed by direct grep instead and the scan's CSS row is kept only
for continuity.

Upstream has exactly **one** declarative UI file — `data/resources/ui/shortcuts.ui`
(18 accelerators). Everything else is built in Vala, so the `.blp`/`.ui`
shortcut from Step 1 of the skill does not apply here; the widget trees had to
be read out of source.

User-facing upstream files (`src/{Dialogs,Layouts,Views,Widgets}`,
`src/MainWindow.vala`, `src/App.vala`, `core/{Widgets,Layouts}`,
`core/QuickAddCore.vala`): **143**.
Of those, **62** are now named in a "ported from" comment in `lib/`, and
reading the port shows **~74** have a real counterpart class — some their own
file, some merged into a sibling's, some renamed. **69 have none.**

## Non-code assets — all carried over verbatim, nothing to port

| Asset | Upstream | Port | Status |
|---|---|---|---|
| GSettings schema | `data/io.github.alainm23.planify.gschema.xml`, 61 keys | same path, same file | present; `lib/planify/settings.rb` is a typed accessor over it, not a re-declaration |
| GResource manifest | `data/io.github.alainm23.planify.gresource.xml`, 291 files | same path | present |
| Stylesheets | `data/resources/stylesheet/*.css`, 1105 lines | same path | present; `lib/planify/theme.rb` regenerates `variables.css` and the font-scale provider at runtime |
| Shortcuts window | `data/resources/ui/shortcuts.ui` | `lib/planify/dialogs/shortcuts.rb` | **rebuilt in code**, driven by `Services::ActionManager::GROUPS` rather than the `.ui` |
| `po/` catalogue | 84 LINGUAS, 167 `.po`, `POTFILES` with 218 entries | same, 167 `.po` | present; `POTFILES` still lists 212 Vala paths and no `.rb` file, so it needs regenerating for `lib/**/*.rb` |
| Icons, sounds, images, man pages, desktop files | `data/**` | same paths | present |

## Actions and accelerators

Upstream `src/Services/ActionManager.vala` installs 21 actions under the `win.`
prefix, split into `action_accelerators` (15, always live) and
`typing_accelerators` (6, suspended while a text field has focus), plus
`win.action_view_project(N)` parameterised for `<Control>1`..`<Control>9`.

`lib/planify/services/action_manager.rb` installs 24 actions under renamed
names (`win.go-today` for `action_view_today`, and so on) and is the source the
shortcuts dialog reads. **Gap:** the port has no equivalent of the
typing-accelerator suspend/resume pair (`disable_all_accels` /
`enable_all_accels`), and no parameterised `view-project(N)` action, so
`<Control>1`..`<Control>9` are unbound.

## Components

Order is the order a user meets them.

### Application and window shell

| Upstream | → port | Kind | Present |
|---|---|---|---|
| `src/App.vala` | `lib/planify/application.rb` | application | yes |
| `src/MainWindow.vala` | `lib/planify/main_window.rb` | window | yes (12 widget rows vs upstream's much larger tree — thin) |
| `src/Layouts/HeaderBar.vala` | `lib/planify/widgets/header_bar.rb` | header bar | **no** — each view/dialog builds its own `Adwaita::HeaderBar` inline; the shared component with its title modes, sync button and view-style switcher does not exist |
| `src/Services/ActionManager.vala` | `lib/planify/services/action_manager.rb` | actions | yes (partial, see above) |
| `data/resources/ui/shortcuts.ui` | `lib/planify/dialogs/shortcuts.rb` | shortcuts window | yes |

### Sidebar

| Upstream | → port | Kind | Present |
|---|---|---|---|
| `src/Layouts/Sidebar.vala` | `lib/planify/sidebar.rb` | sidebar | yes |
| `src/Layouts/SidebarSourceRow.vala` | `lib/planify/widgets/sidebar_widgets.rb` | row | yes |
| `src/Layouts/FilterPaneRow.vala` | `lib/planify/widgets/filter_flow_box.rb` | row | merged — `filter_flow_box.rb` builds the list-view row itself, as the `listbox` half of its stack; no separate file, and the row's `filter-pane-row`/`view-icon` classes are not applied |
| `src/Layouts/FilterPaneChild.vala` | `lib/planify/widgets/filter_flow_box.rb` | child widget | merged — the grid tile, as the `flowbox` half; `filter-pane-child` not applied |
| `src/Layouts/ProjectContainerRow.vala` | `lib/planify/widgets/project_container_row.rb` | row | **no** — the collapsible project group with its nested children |
| `src/Layouts/ProjectRow.vala` | `lib/planify/widgets/project_row.rb` | row | yes |
| `src/Layouts/LabelRow.vala` | `lib/planify/widgets/label_row.rb` | row | yes — the row the labels view renders, reorderable, with its own menu |
| `src/Widgets/MagicButton.vala` | `lib/planify/widgets/sidebar_widgets.rb` | floating button | yes |
| `src/Widgets/SyncButton.vala` | `lib/planify/widgets/sidebar_widgets.rb` | button | yes |
| `src/Widgets/MultiSelectToolbar.vala` | `lib/planify/widgets/sidebar_widgets.rb` | toolbar | yes |
| `core/Layouts/HeaderItem.vala` | `lib/planify/widgets/header_item.rb` | section container | yes — the collapsible titled list container; wired as the sidebar's Favorites group |

### Views

| Upstream | → port | Kind | Present |
|---|---|---|---|
| `src/Views/Today.vala` | `lib/planify/views/today_view.rb` | page | yes |
| `src/Views/Scheduled/Scheduled.vala` | `lib/planify/views/scheduled_view.rb` | page | yes |
| `src/Views/Scheduled/ScheduledDay.vala` | `lib/planify/views/scheduled_view.rb` | section | yes (as `day_sections`) |
| `src/Views/Scheduled/ScheduledMonth.vala` | `lib/planify/views/scheduled_view.rb` | section | yes (as `month_sections`) |
| `src/Views/Scheduled/ScheduledRange.vala` | `lib/planify/views/scheduled_view.rb` | section | yes (as `month_title`/range bucket) |
| `src/Views/Scheduled/ScheduledOverdue.vala` | `lib/planify/views/scheduled_view.rb` | section | yes (as `overdue_section` + reschedule popover) |
| `src/Views/Scheduled/ScheduledSection.vala` | `lib/planify/views/scheduled_view.rb` | section | yes (as `section_box`) |
| `src/Views/Project/Project.vala` | `lib/planify/views/project_view.rb` | page | yes |
| `src/Views/Project/List.vala` | `lib/planify/views/project_view.rb` | layout | yes (stack page `"list"`) |
| `src/Views/Project/Board.vala` | `lib/planify/views/project_view.rb` | layout | yes (stack page `"board"`) |
| `src/Views/Label/Labels.vala` | `lib/planify/views/labels_view.rb` | page | yes |
| `src/Views/Label/Label.vala` | `lib/planify/views/label_view.rb` | page | **no** — the single-label task list; `labels_view.rb` only lists labels |
| `src/Views/Label/LabelSourceRow.vala` | `lib/planify/views/labels_view.rb` | row | **no** |
| `src/Views/Filter.vala` | `lib/planify/views/filter_view.rb` | page | yes |
| `src/Objects/Filters/*.vala` (13 files) | `lib/planify/views/filter_view.rb`, `lib/planify/models.rb` | filter objects | partial — `FilterItem` is attributed; the 12 concrete filters (Inbox, Today, Tomorrow, Anytime, Scheduled, Repeating, Completed, Labels, Unlabeled, Pinboard, Priority, AllItems) are not individually ported |

### Task rows and detail

| Upstream | → port | Kind | Present |
|---|---|---|---|
| `src/Layouts/ItemBase.vala` | `lib/planify/widgets/item_base.rb` | base class | **no** — the shared base `ItemRow`/`ItemBoard` both derive from |
| `src/Layouts/ItemRow.vala` | `lib/planify/widgets/item_row.rb` | row | yes (20 widget rows; upstream is the app's largest widget) |
| `src/Layouts/ItemBoard.vala` | `lib/planify/widgets/section_board.rb` | card | yes |
| `src/Layouts/SectionRow.vala` | `lib/planify/widgets/section_row.rb` | row | yes |
| `src/Layouts/SectionBoard.vala` | `lib/planify/widgets/section_board.rb` | board column | yes |
| `src/Layouts/ItemSidebarView.vala` | `lib/planify/widgets/item_detail.rb` | detail pane | yes |
| `src/Widgets/ItemDetailCompleted.vala` | `lib/planify/widgets/item_detail.rb` | detail variant | **no** — the read-only completed-task detail |
| `src/Widgets/SubItems.vala` | `lib/planify/widgets/attachments.rb` | subtask list | yes |
| `src/Widgets/CompletedTaskRow.vala` | `lib/planify/widgets/misc.rb` | row | yes |
| `src/Widgets/ProjectItemRow.vala` | `lib/planify/widgets/project_item_row.rb` | row | **no** |
| `src/Widgets/SectionItemRow.vala` | `lib/planify/widgets/section_item_row.rb` | row | **no** |
| `src/Widgets/ReorderChild.vala` | `lib/planify/widgets/reorder_child.rb` | drag-and-drop wrapper | yes — the drop strip travels as the record id on the row's widget name, since `Gdk::ContentProvider` carries only GObject values |
| `src/Widgets/Attachments.vala` | `lib/planify/widgets/attachments.rb` | list | yes |
| `src/Widgets/AttachmentRow.vala` | `lib/planify/widgets/attachments.rb` | row | yes |
| `src/Widgets/LabelsSummary.vala` | `lib/planify/widgets/small.rb` | summary | yes |
| `core/Widgets/ItemLabels.vala` | `lib/planify/widgets/small.rb` | label strip | yes |
| `core/Widgets/ItemLabelChild.vala` | `lib/planify/widgets/small.rb` | chip | merged — `ItemLabels` draws the chips inline under its own `label-chip` class; upstream's `item-label-child` is not applied |
| `src/Widgets/ItemChangeHistoryRow.vala` | `lib/planify/widgets/misc.rb` | row | yes |

### Pickers and inline controls (`core/Widgets` — 605 widget rows, the densest area)

| Upstream | → port | Kind | Present |
|---|---|---|---|
| `core/Widgets/DateTimePicker/DateTimePicker.vala` | `lib/planify/widgets/date_time_picker.rb` | popover picker | yes |
| `core/Widgets/DateTimePicker/TimePicker.vala` | `lib/planify/widgets/date_time_picker.rb` | time entry | **no** — the hour/minute/AM-PM control |
| `core/Widgets/DateTimePicker/ScheduleButton.vala` | `lib/planify/widgets/date_time_picker.rb` | button | **no** — the due-date button that hosts the picker |
| `core/Widgets/DateTimePicker/RepeatConfig.vala` | `lib/planify/widgets/repeat_config.rb` | dialog | yes |
| `core/Widgets/Calendar/Calendar.vala` | `lib/planify/widgets/calendar.rb` | calendar | **no** |
| `core/Widgets/Calendar/CalendarView.vala` | `lib/planify/widgets/calendar.rb` | calendar | **no** |
| `core/Widgets/Calendar/CalendarHeader.vala` | `lib/planify/widgets/calendar.rb` | header | **no** |
| `core/Widgets/Calendar/CalendarMonth.vala` | `lib/planify/widgets/calendar.rb` | grid | **no** |
| `core/Widgets/Calendar/CalendarWeek.vala` | `lib/planify/widgets/calendar.rb` | row | **no** |
| `core/Widgets/Calendar/CalendarDay.vala` | `lib/planify/widgets/calendar.rb` | cell | **no** |
| `core/Widgets/Calendar/CalendarScroll.vala` | `lib/planify/widgets/calendar.rb` | scroller | **no** — whole custom calendar (and `calendar.css`) unported; the port uses `Gtk::Calendar` |
| `core/Widgets/LabelPicker/LabelPicker.vala` | `lib/planify/widgets/label_picker.rb` | picker | yes |
| `core/Widgets/LabelPicker/LabelsPickerCore.vala` | `lib/planify/widgets/label_picker.rb` | core list | **no** |
| `core/Widgets/LabelPicker/LabelRow.vala` | `lib/planify/widgets/label_picker.rb` | row | **no** |
| `core/Widgets/LabelPicker/LabelButton.vala` | `lib/planify/widgets/label_picker.rb` | button | **no** |
| `core/Widgets/LabelPicker/LabelQuickPicker.vala` | `lib/planify/widgets/label_picker.rb` | quick picker | **no** |
| `core/Widgets/ProjectPicker/ProjectPickerCore.vala` | `lib/planify/widgets/project_picker.rb` | core list | **no** |
| `core/Widgets/ProjectPicker/ProjectPickerRow.vala` | `lib/planify/widgets/project_picker.rb` | row | **no** |
| `core/Widgets/ProjectPicker/ProjectPickerButton.vala` | `lib/planify/widgets/project_picker.rb` | button | **no** |
| `core/Widgets/ProjectPicker/ProjectPickerPopover.vala` | `lib/planify/widgets/project_picker.rb` | popover | **no** |
| `core/Widgets/SectionPicker/SectionPicker.vala` | `lib/planify/widgets/project_picker.rb` | picker | yes |
| `core/Widgets/SectionPicker/SectionPickerRow.vala` | `lib/planify/widgets/project_picker.rb` | row | **no** |
| `core/Widgets/SectionPicker/SectionButton.vala` | `lib/planify/widgets/project_picker.rb` | button | **no** |
| `core/Widgets/ReminderPicker/ReminderPicker.vala` | `lib/planify/widgets/reminder_picker.rb` | picker | yes |
| `core/Widgets/ReminderPicker/ReminderRow.vala` | `lib/planify/widgets/reminder_picker.rb` | row | **no** |
| `core/Widgets/ReminderPicker/ReminderButton.vala` | `lib/planify/widgets/reminder_picker.rb` | button | **no** |
| `core/Widgets/PriorityButton.vala` | `lib/planify/widgets/priority_picker.rb` | button | **no** — `PriorityPicker` exists, the button does not |
| `core/Widgets/PinButton.vala` | `lib/planify/widgets/small.rb` | button | **no** |
| `core/Widgets/DeadlineButton.vala` | `lib/planify/widgets/small.rb` | button | **no** |
| `core/Widgets/StatusButton.vala` | `lib/planify/widgets/small.rb` | button | **no** |
| `core/Widgets/LoadingButton.vala` | `lib/planify/widgets/small.rb` | button | yes |
| `core/Widgets/CircularProgressBar.vala` | `lib/planify/widgets/small.rb` | gauge | yes |
| `core/Widgets/IconColorProject.vala` | `lib/planify/widgets/small.rb` | icon | yes |
| `core/Widgets/ColorPickerRow.vala` | `lib/planify/widgets/color_picker.rb` | row | yes |
| `src/Widgets/ColorPickerRow.vala` | `lib/planify/widgets/color_picker.rb` | row | **no** — a second, `src`-side variant distinct from the `core` one |
| `core/Widgets/TextView.vala` | `lib/planify/widgets/text_view.rb` | text view | yes — placeholder written into the buffer at half opacity when unfocused and empty |
| `src/Widgets/EditableTextView.vala` | `lib/planify/widgets/editable_text_view.rb` | inline editor | yes — the project note, editable in place; abbreviates itself behind Show more in mobile mode |
| `core/Widgets/MarkdownEditor.vala` | `lib/planify/widgets/markdown_editor.rb` | editor | yes |
| `src/Widgets/ComboWrapRow.vala` | `lib/planify/widgets/combo_wrap_row.rb` | row | yes — the per-project Markdown override in the project dialog |
| `src/Widgets/ScrolledWindow.vala` | `lib/planify/widgets/small.rb` | scroller | yes |
| `src/Widgets/FilterFlowBox.vala` | `lib/planify/widgets/filter_flow_box.rb` | flow box | yes |
| `src/Widgets/FilterFlowBoxChild.vala` | `lib/planify/widgets/filter_flow_box.rb` | child | **no** |
| `src/Widgets/PinnedItemsBox.vala` | `lib/planify/widgets/filter_flow_box.rb` | box | yes |
| `src/Widgets/SectionsOrderPopover.vala` | `lib/planify/widgets/sections_order_popover.rb` | popover | yes — with `SectionsOrderItem`; behind the project's section button |
| `core/Widgets/ContextMenu/MenuItem.vala` | `lib/planify/widgets/context_menu.rb` | menu row | yes |
| `core/Widgets/ContextMenu/MenuSwitch.vala` | `lib/planify/widgets/context_menu.rb` | menu row | yes |
| `core/Widgets/ContextMenu/MenuPicker.vala` | `lib/planify/widgets/context_menu.rb` | menu row | yes |
| `core/Widgets/ContextMenu/MenuCheckPicker.vala` | `lib/planify/widgets/context_menu.rb` | menu row | yes |
| `core/Widgets/ContextMenu/MenuSeparator.vala` | `lib/planify/widgets/context_menu.rb` | separator | yes |

### Quick Add and Quick Find

| Upstream | → port | Kind | Present |
|---|---|---|---|
| `core/QuickAddCore.vala` | `lib/planify/widgets/quick_add.rb` | widget | yes |
| `src/Dialogs/QuickAdd.vala` | `lib/planify/widgets/quick_add.rb` | dialog | partial — the widget exists and `quick_add_application.rb` hosts the standalone mode, but the dialog wrapper is not attributed |
| `src/Dialogs/QuickFind/QuickFind.vala` | `lib/planify/dialogs/quick_find.rb` | dialog | yes |
| `src/Dialogs/QuickFind/QuickFindItem.vala` | `lib/planify/dialogs/quick_find.rb` | result row | **no** — `result_row` is a plain `ActionRow`, not the typed item |
| `src/Dialogs/QuickFind/QuickFindFactory.vala` | `lib/planify/dialogs/quick_find.rb` | list factory | **no** — the port uses a `ListBox`, not a `SignalListItemFactory` |
| `src/Dialogs/QuickFind/QuickFindSectionSorter.vala` | `lib/planify/dialogs/quick_find.rb` | sorter | **no** |
| `src/Dialogs/QuickFind/Synapse.vala` | `lib/planify/dialogs/quick_find.rb` | search backend | **no** |

### Dialogs

| Upstream | → port | Kind | Present |
|---|---|---|---|
| `src/Dialogs/Project.vala` | `lib/planify/dialogs/project_dialog.rb` | dialog | yes |
| `src/Dialogs/Section.vala` | `lib/planify/dialogs/section_dialog.rb` | dialog | yes |
| `src/Dialogs/Label.vala` | `lib/planify/dialogs/label_dialog.rb` | dialog | yes |
| `src/Dialogs/DatePicker.vala` | `lib/planify/dialogs/date_picker_dialog.rb` | dialog | yes |
| `src/Dialogs/ProjectPicker.vala` | `lib/planify/dialogs/date_picker_dialog.rb` | dialog | yes |
| `src/Dialogs/LabelPicker.vala` | `lib/planify/dialogs/date_picker_dialog.rb` | dialog | yes (`LabelPickerDialog`) |
| `src/Dialogs/CalendarSync.vala` | `lib/planify/dialogs/date_picker_dialog.rb` | dialog | yes |
| `src/Dialogs/ManageProjects.vala` | `lib/planify/dialogs/manage.rb` | dialog | yes |
| `src/Dialogs/ManageSectionOrder.vala` | `lib/planify/dialogs/manage.rb` | dialog | yes |
| `src/Dialogs/CompletedTasks.vala` | `lib/planify/dialogs/manage.rb` | dialog | yes |
| `src/Dialogs/ItemChangeHistory.vala` | `lib/planify/dialogs/productivity_report.rb` | dialog | yes |
| `src/Dialogs/ErrorDialog.vala` | `lib/planify/dialogs/productivity_report.rb` | error state | yes |
| `src/Widgets/ErrorView.vala` | `lib/planify/widgets/small.rb` | error state | yes |
| `src/Widgets/NewVersionPopup.vala` | `lib/planify/widgets/misc.rb` | popup | yes |

### Productivity report

| Upstream | → port | Kind | Present |
|---|---|---|---|
| `src/Dialogs/ProductivityReport/ProductivityReport.vala` | `lib/planify/dialogs/productivity_report.rb` | dialog | yes |
| `src/Dialogs/ProductivityReport/StatCard.vala` | `lib/planify/widgets/misc.rb` | card | yes |
| `src/Dialogs/ProductivityReport/HeatMap.vala` | `lib/planify/widgets/misc.rb` | heat map | yes |
| `src/Dialogs/ProductivityReport/SummarySection.vala` | `lib/planify/dialogs/productivity_report.rb` | section | **no** — the port inlines three `StatCard`s instead |
| `src/Dialogs/ProductivityReport/ProductivitySection.vala` | `lib/planify/dialogs/productivity_report.rb` | section | **no** |
| `src/Widgets/ProductivityMiniWidget.vala` | `lib/planify/widgets/misc.rb` | sidebar widget | yes |

### Preferences

| Upstream | → port | Kind | Present |
|---|---|---|---|
| `src/Dialogs/Preferences/PreferencesWindow.vala` | `lib/planify/dialogs/preferences.rb` | dialog | yes (7 pages) |
| `src/Dialogs/Preferences/Pages/BasePage.vala` | `lib/planify/dialogs/preferences_pages.rb` | base class | **no** — port uses a `Bindings` mixin instead; no shared page base |
| `src/Dialogs/Preferences/Pages/General.vala` | `lib/planify/dialogs/preferences_pages.rb` | page | yes |
| `src/Dialogs/Preferences/Pages/HomeView.vala` | `lib/planify/dialogs/preferences_pages.rb` | page | **no** — collapsed into a combo row on General |
| `src/Dialogs/Preferences/Pages/TaskSetting.vala` | `lib/planify/dialogs/preferences_pages.rb` | page | **no** — collapsed into `task_group` on General |
| `src/Dialogs/Preferences/Pages/QuickAdd.vala` | `lib/planify/dialogs/preferences_pages.rb` | page | **no** — collapsed into `quick_add_group` on General |
| `src/Dialogs/Preferences/Pages/Appearance.vala` | `lib/planify/dialogs/preferences_pages.rb` | page | yes |
| `src/Dialogs/Preferences/Pages/Sidebar.vala` | `lib/planify/dialogs/sidebar_page.rb` | page | yes |
| `src/Dialogs/Preferences/Pages/CalendarEvents.vala` | `lib/planify/dialogs/preferences_pages.rb` | page | yes |
| `src/Dialogs/Preferences/Pages/Backup.vala` | `lib/planify/dialogs/preferences_pages.rb` | page | yes (`Backups`) |
| `src/Dialogs/Preferences/Pages/Donate.vala` | `lib/planify/dialogs/donate_page.rb` | page | yes |
| `src/Dialogs/Preferences/Pages/Accounts/Accounts.vala` | `lib/planify/dialogs/accounts_page.rb` | page | yes |
| `src/Dialogs/Preferences/Pages/Accounts/TodoistSetup.vala` | `lib/planify/dialogs/accounts_page.rb` | setup flow | yes |
| `src/Dialogs/Preferences/Pages/Accounts/CalDAVSetup.vala` | `lib/planify/dialogs/accounts_page.rb` | setup flow | yes |
| `src/Dialogs/Preferences/Pages/Accounts/NextcloudSetup.vala` | `lib/planify/dialogs/accounts_page.rb` | setup flow | **no** — Nextcloud is named in the service layer but has no setup page |
| `src/Dialogs/Preferences/Pages/Accounts/InboxPage.vala` | `lib/planify/dialogs/accounts_page.rb` | page | **no** |
| `src/Dialogs/Preferences/Pages/Accounts/SourceView.vala` | `lib/planify/dialogs/accounts_page.rb` | page | **no** — per-source settings and removal |
| `src/Widgets/IgnoreSSLSwitchRow.vala` | `lib/planify/dialogs/accounts_page.rb` | row | **no** |
| `src/Widgets/BypassResolveSwitchRow.vala` | `lib/planify/dialogs/accounts_page.rb` | row | **no** |
| `src/Widgets/TranslationRow.vala` | `lib/planify/widgets/translation_row.rb` | row | yes — on the About page, reading completeness from the shipped `.po` catalogues |

### Companion binaries

Upstream ships three programs beside the window, each with its own `main`.
They are user-facing surfaces, so they belong in the inventory even where they
build no widgets.

| Upstream | → port | Kind | Present |
|---|---|---|---|
| `quick-add/App.vala` | `lib/planify/quick_add_application.rb` | application | yes — same shape: a resizeless window whose whole content is `QuickAddCore` |
| `quick-add/MainWindow.vala` | `lib/planify/quick_add_application.rb` | window | partial — the port presents `QuickAdd` as a dialog over a 1×1 hidden window rather than `set_content`ing the widget, and has no `can_close`/`parent_can_close` gate, so Escape can close the window mid-save |
| `quick-add/Services/DBusClient.vala` | `lib/planify/services/dbus_server.rb` | bus client | yes |
| `cli/Main.vala`, `ArgumentParser`, `TaskCreator`, `TaskValidator`, `OutputFormatter`, `DBusClient` (6 files) | `lib/planify/cli.rb` | CLI | yes — one module covers all six; `add`, `list`, `projects`, `update`, `backup`, `help` |
| `search-provider/search-provider.vala` | `lib/planify/services/dbus_server.rb` | GNOME Shell search provider | yes — `org.gnome.Shell.SearchProvider2` on `/io/github/alainm23/planify/SearchProvider` |
| `search-provider/search-repository.vala` | `lib/planify/services/dbus_server.rb` | search backend | yes |
| `search-provider/main.vala` | `exe/planify` | entry point | yes — the port serves the interface from the app process instead of a separate service binary |

Entry points on the port side: `exe/planify`, `exe/planify-cli`,
`exe/planify-quick-add`, `exe/planify-dev`.

### Calendar events

| Upstream | → port | Kind | Present |
|---|---|---|---|
| `src/Widgets/EventsList.vala` | `lib/planify/widgets/misc.rb` | list | yes |
| `src/Widgets/EventRow.vala` | `lib/planify/widgets/misc.rb` | row | yes |

## Widget types upstream uses that the port never instantiates (15)

`Adw.Avatar`, `Adw.BottomSheet`, `Adw.ButtonRow`, `Adw.NavigationPage`,
`Adw.NavigationView`, `Adw.Spinner`, `Adw.ToggleGroup`, `Adw.ViewStack`,
`Gtk.FlowBoxChild`, `Gtk.Frame`, `Gtk.ListView`, `Gtk.ProgressBar`,
`Gtk.Scale`, `Gtk.Text`, `Gtk.WindowHandle` — plus `GtkSource.Buffer`, which
only the Markdown editor needs and which the port replaces with a plain
`Gtk::TextBuffer`.

Four of these are structural rather than cosmetic and name real gaps above:
`Adw.NavigationView`/`NavigationPage` are how upstream's accounts and source
pages push and pop, `Adw.ViewStack` is upstream's view switcher, and
`Gtk.ListView` is the `SignalListItemFactory` quick-find is built on.
`Gtk.Scale` is the font-scale slider; `Adw.Spinner` and `Gtk.ProgressBar` are
the sync and backup progress states; `Adw.BottomSheet` is the mobile task
detail.

The port's `Adw.ShortcutsDialog` in place of upstream's `Gtk.ShortcutsWindow`
family is a deliberate modernisation, not a gap.

## CSS classes upstream applies that the port never does (110)

Counted by grepping every `add_css_class` / `css_classes` site on both sides
rather than from the scan, whose CSS stream reads only the first string of a
multi-element initialiser and so under-reports upstream badly. Upstream
applies **141** distinct classes; the port applies **47**, of which 31 are
upstream's.

`accent`, `activatable`, `add-button`, `animation`, `badge`, `bg-danger`,
`body`, `border-outline`, `border-radius-6`, `border-radius-9`, `br-12`,
`button-emoji-picker`, `calendar-day`, `checkbutton-label`, `circle-color`,
`circular-check`, `color-radio`, `complete`, `completed-color`, `completed-
grid`, `completed-image-color`, `date-flying-label`, `date-updated`,
`description-box`, `destructive-action`, `devel`, `dimmed`, `dimming-bg`,
`drop-target-list`, `error-message`, `event-bar`, `fancy-bounce-turn-
animation`, `fancy-turn-animation`, `filter-pane-child`, `filter-pane-row`,
`font-bold`, `font-weight-500`, `fw-600`, `header-item-button`, `heatmap-
cell-%d`, `heatmap-cell-today`, `hidden-button`, `icon-color`, `indicator`,
`is_loading`, `item-label-child`, `keep-adding-button`, `label-color`,
`line-through`, `listbox-background`, `listbox-separator-6`, `menu-button-
no-padding`, `menu-item-danger`, `min-height-0`, `monospace`, `no-font-
bold`, `opened`, `overdue-grid`, `padding-4`, `pane-due-button`, `pb-6`,
`pinboard-color`, `popover-contents`, `primary-color`, `priority-1-button`,
`priority-1-color`, `priority-1-icon`, `priority-2-button`,
`priority-2-color`, `priority-2-icon`, `priority-3-button`,
`priority-3-color`, `priority-3-icon`, `priority-4-color`, `priority-color`,
`priority-flying-label`, `priority-label-impact`, `priority-pulse-
animation`, `property`, `quick-find-list`, `see-more-icon-collapsed`, `see-
more-icon-expanded`, `selectable-item`, `shortcut-widget`, `sidebar`,
`sidebar-card`, `sidebar-row`, `small-button`, `source-calendar-color`,
`submit-spinner`, `suggested-button-selected`, `suggestion-chip`, `switch-
min`, `task-editing`, `task-item`, `text-color`, `theme-dark`, `theme-dark-
blue`, `theme-mode-image`, `title-2`, `title-4`, `today`, `today-grid`,
`transparent`, `upcoming-grid`, `version-popup`, `view`, `view-button`,
`view-icon`, `warning`

All of them are defined in the stylesheets the port already ships
(`data/resources/stylesheet/*.css`, carried over verbatim), so every one is a
missing *application*, not missing CSS. They cluster:

- **Priority** — `priority-{1..4}-color`, `priority-{1..3}-button`,
  `priority-{1..3}-icon`, `priority-color`, `priority-label-impact`,
  `priority-flying-label`, `priority-pulse-animation`. These land on
  `PriorityButton` and the flying labels, none of which is ported.
- **Theme previews** — `theme-dark`, `theme-dark-blue`, `theme-mode-image`
  are what Appearance's theme swatches paint themselves with.
- **Sidebar** — `sidebar`, `sidebar-card`, `sidebar-row`, `view-icon`,
  `view-button`, `filter-pane-row`, `filter-pane-child`. The port reaches the
  same widgets but leaves them in default Adwaita dress.
- **Scheduled and Today grids** — `today-grid`, `upcoming-grid`,
  `overdue-grid`, `completed-grid`.
- **Animation** — `animation`, `fancy-turn-animation`,
  `fancy-bounce-turn-animation`, `see-more-icon-{collapsed,expanded}`,
  `submit-spinner`.
- **Typography and spacing utilities** — `title-2`, `title-4`, `body`,
  `font-bold`, `no-font-bold`, `fw-600`, `font-weight-500`, `monospace`,
  `br-12`, `border-radius-6`, `border-radius-9`, `padding-4`, `pb-6`,
  `min-height-0`, `line-through`, `transparent`, `listbox-separator-6`.
- **Plain omissions on buttons and rows that do exist** —
  `destructive-action`, `suggested-button-selected`, `activatable`, `accent`,
  `warning`, `dimmed`, `hidden-button`, `switch-min`, `view`, `today`,
  `circular-check`, `selectable-item`, `menu-item-danger`.

The 16 classes the port applies that upstream does not —

`background`, `complete-animation`, `destructive`, `dragging`, `filter-
tile`, `item-board`, `item-row`, `label-chip`, `markdown-editor`, `menu-
listbox`, `navigation-sidebar`, `osd`, `project-row`, `section-board`,
`stat-card`, `toolbar`

— are the port's own names for widgets it builds in one file where upstream
used several, plus the Adwaita built-ins `background`, `destructive`,
`navigation-sidebar`, `osd` and `toolbar`. The port-specific ones appear in no
shipped stylesheet, so they style nothing today; each is either a rule to add
or a name to replace with upstream's.

## Where the work is

In rough order of how much each unblocks, after the nine classes the
`HeaderItem`/`ReorderChild`/`TextView` commit landed:

1. **`core/Widgets` pickers** — 605 widget rows upstream, roughly 100 in the
   port. Every picker exists as its popover but not as its button, row or
   core list, which is why the port has pickers no row can open:
   `LabelButton`, `LabelQuickPicker`, `LabelsPickerCore`, `LabelPicker/LabelRow`,
   `ProjectPickerCore`, `ProjectPickerRow`, `ProjectPickerButton`,
   `ProjectPickerPopover`, `SectionPickerRow`, `SectionButton`,
   `ReminderRow`, `ReminderButton`, `ScheduleButton`, `TimePicker`,
   `PriorityButton`, `PinButton`, `DeadlineButton`, `StatusButton`. 18 files.
2. **The custom calendar** — `core/Widgets/Calendar/` is 7 files and
   `calendar.css`, none of it ported; the port substitutes `Gtk::Calendar`,
   so the month scroller, the day cells and their dots are all absent.
3. **Shared structural widgets still missing** — `src/Layouts/HeaderBar.vala`
   (every view and dialog builds its own `Adwaita::HeaderBar` inline, so the
   title modes, sync button and view-style switcher exist nowhere) and
   `src/Layouts/ItemBase.vala` (the base `ItemRow` and `ItemBoard` share
   upstream; the port duplicates it in both). Both are reused app-wide.
4. **Row variants on top of rows that exist** —
   `src/Layouts/ProjectContainerRow.vala` (the collapsible project group with
   nested children), `src/Widgets/ProjectItemRow.vala`,
   `src/Widgets/SectionItemRow.vala`, `src/Widgets/ItemDetailCompleted.vala`,
   `src/Views/Label/Label.vala` with `LabelSourceRow.vala` (the single-label
   task list; `labels_view.rb` only lists labels), and the `src`-side
   `ColorPickerRow.vala` variant.
5. **Quick Find's real machinery** — `QuickFindItem`, `QuickFindFactory`,
   `QuickFindSectionSorter` and `Synapse`. The port's dialog is a `ListBox` of
   plain `ActionRow`s, so there is no sectioned, sorted, scored result list.
6. **Accounts setup** — `NextcloudSetup`, `InboxPage`, `SourceView` and the
   `IgnoreSSLSwitchRow` / `BypassResolveSwitchRow` pair. Without `SourceView`
   a configured account cannot be inspected or removed.
7. **Preferences sub-pages** — `BasePage`, `HomeView`, `TaskSetting`,
   `QuickAdd`. Three pages are collapsed into groups on General, which is a
   defensible merge, but `BasePage`'s shared chrome is what the rest of the
   pages lean on upstream.
8. **Productivity report sections** — `SummarySection` and
   `ProductivitySection`; the port inlines three `StatCard`s in their place.
9. **The 12 concrete filters** — `core/Objects/Filters/{Inbox,Today,Tomorrow,
   Anytime,Scheduled,Repeating,Completed,Labels,Unlabeled,Pinboard,Priority,
   AllItems}.vala`. `FilterItem` is attributed; the concrete filters, each with
   its own name, icon, colour and query, live as a literal table in
   `filter_flow_box.rb` and `filter_view.rb` rather than as objects.
10. **CSS applications** — 110 classes, all already defined in the shipped
    stylesheets. Cheap per class and the single biggest visual difference.
11. **Accelerator behaviour** — the typing-accelerator suspend/resume pair
    (`disable_all_accels` / `enable_all_accels`) and the parameterised
    `win.action_view_project(N)`, so `<Control>1`..`<Control>9` are unbound.
12. **Quick Add's close gate** — `can_close` / `parent_can_close`, so Escape
    cannot close the standalone window while a task is being written.
13. **`po/POTFILES`** — still lists 212 Vala paths and no `.rb` file, so none
    of the port's own strings are extractable even though all 167 `.po`
    catalogues and 84 LINGUAS are carried over.
