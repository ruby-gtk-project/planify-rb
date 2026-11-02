# planify-rb — upstream component inventory

Survey of `origin/main` (Vala/GTK4/libadwaita) against `lib/` on the `ruby`
branch. Method: the `component-identification` skill — upstream extracted to a
scratch tree, `component-scan.sh` run on both sides, then every user-facing
file read or spot-read and joined to the port file that carries it.

## Totals

| | upstream | `ruby` branch |
|---|---:|---:|
| scan rows | 2927 | 708 |
| widget instances | 2830 | 666 |
| distinct widget types | 77 | 52 |
| distinct CSS classes | 100 | 34 |
| distinct signals | 201 | 33 |
| source files (`.vala`) | 228 | 80 (`.rb`) |

Upstream has exactly **one** declarative UI file — `data/resources/ui/shortcuts.ui`
(18 accelerators). Everything else is built in Vala, so the `.blp`/`.ui`
shortcut from Step 1 of the skill does not apply here; the widget trees had to
be read out of source.

User-facing upstream files (`src/{Dialogs,Layouts,Views,Widgets}`,
`src/MainWindow.vala`, `src/App.vala`, `core/{Widgets,Layouts}`): **142**.
Of those, **52** are named in a "ported from" comment in `lib/`, and reading
the port shows **~63** have a real counterpart class (some merged, some
renamed). **79 have none.**

## Non-code assets — all carried over verbatim, nothing to port

| Asset | Upstream | Port | Status |
|---|---|---|---|
| GSettings schema | `data/io.github.alainm23.planify.gschema.xml`, 61 keys | same path, same file | present; `lib/planify/settings.rb` is a typed accessor over it, not a re-declaration |
| GResource manifest | `data/io.github.alainm23.planify.gresource.xml`, 291 files | same path | present |
| Stylesheets | `data/resources/stylesheet/*.css`, 1105 lines | same path | present; `lib/planify/theme.rb` regenerates `variables.css` and the font-scale provider at runtime |
| Shortcuts window | `data/resources/ui/shortcuts.ui` | `lib/planify/dialogs/shortcuts.rb` | **rebuilt in code**, driven by `Services::ActionManager::GROUPS` rather than the `.ui` |
| `po/` catalogue | 84 LINGUAS, 167 `.po`, `POTFILES` with 218 entries | same, 167 `.po` | present; `POTFILES` still lists the 218 Vala paths and needs regenerating for `lib/**/*.rb` |
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
| `src/Layouts/FilterPaneRow.vala` | `lib/planify/widgets/filter_pane_row.rb` | row | **no** — name appears only in a comment in `filter_flow_box.rb` |
| `src/Layouts/FilterPaneChild.vala` | `lib/planify/widgets/filter_pane_row.rb` | child widget | **no** |
| `src/Layouts/ProjectContainerRow.vala` | `lib/planify/widgets/project_container_row.rb` | row | **no** — the collapsible project group with its nested children |
| `src/Layouts/ProjectRow.vala` | `lib/planify/widgets/project_row.rb` | row | yes |
| `src/Layouts/LabelRow.vala` | `lib/planify/widgets/label_row.rb` | row | **no** |
| `src/Widgets/MagicButton.vala` | `lib/planify/widgets/sidebar_widgets.rb` | floating button | yes |
| `src/Widgets/SyncButton.vala` | `lib/planify/widgets/sidebar_widgets.rb` | button | yes |
| `src/Widgets/MultiSelectToolbar.vala` | `lib/planify/widgets/sidebar_widgets.rb` | toolbar | yes |
| `core/Layouts/HeaderItem.vala` | `lib/planify/widgets/header_item.rb` | section container | **no** — the collapsible titled list container upstream reuses across every view (37 widget rows) |

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
| `src/Widgets/ReorderChild.vala` | `lib/planify/widgets/reorder_child.rb` | drag-and-drop wrapper | **no** — reordering wrapper used by every reorderable list |
| `src/Widgets/Attachments.vala` | `lib/planify/widgets/attachments.rb` | list | yes |
| `src/Widgets/AttachmentRow.vala` | `lib/planify/widgets/attachments.rb` | row | yes |
| `src/Widgets/LabelsSummary.vala` | `lib/planify/widgets/small.rb` | summary | yes |
| `core/Widgets/ItemLabels.vala` | `lib/planify/widgets/small.rb` | label strip | yes |
| `core/Widgets/ItemLabelChild.vala` | `lib/planify/widgets/small.rb` | chip | **no** — only referenced in a comment |
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
| `core/Widgets/TextView.vala` | `lib/planify/widgets/text_view.rb` | text view | **no** — placeholder-capable `Gtk.TextView` subclass |
| `src/Widgets/EditableTextView.vala` | `lib/planify/widgets/editable_text_view.rb` | inline editor | **no** — click-to-edit title/description |
| `core/Widgets/MarkdownEditor.vala` | `lib/planify/widgets/markdown_editor.rb` | editor | yes |
| `src/Widgets/ComboWrapRow.vala` | `lib/planify/widgets/combo_wrap_row.rb` | row | **no** |
| `src/Widgets/ScrolledWindow.vala` | `lib/planify/widgets/small.rb` | scroller | yes |
| `src/Widgets/FilterFlowBox.vala` | `lib/planify/widgets/filter_flow_box.rb` | flow box | yes |
| `src/Widgets/FilterFlowBoxChild.vala` | `lib/planify/widgets/filter_flow_box.rb` | child | **no** |
| `src/Widgets/PinnedItemsBox.vala` | `lib/planify/widgets/filter_flow_box.rb` | box | yes |
| `src/Widgets/SectionsOrderPopover.vala` | `lib/planify/widgets/sections_order_popover.rb` | popover | **no** |
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
| `src/Widgets/TranslationRow.vala` | `lib/planify/widgets/translation_row.rb` | row | **no** — the translation-credit row behind `data/translations_metrics.json` |

### Calendar events

| Upstream | → port | Kind | Present |
|---|---|---|---|
| `src/Widgets/EventsList.vala` | `lib/planify/widgets/misc.rb` | list | yes |
| `src/Widgets/EventRow.vala` | `lib/planify/widgets/misc.rb` | row | yes |

## CSS classes upstream applies that the port never does (40)

`accent`, `activatable`, `bg-transparent`, `border-radius-6`,
`checkbutton-label`, `color-primary`, `completed-color`,
`completed-image-color`, `destructive-action`, `dimmed`, `dimming-bg`,
`font-bold`, `h4`, `hidden-button`, `item-label-child`,
`listbox-background`, `listbox-separator-3`, `menu-button-no-padding`,
`no-font-bold`, `no-padding`, `opened`, `pinboard-color`,
`popover-contents`, `primary-color`, `priority-1-button`,
`priority-1-color`, `priority-2-button`, `priority-2-color`,
`priority-3-button`, `priority-3-color`, `priority-4-color`,
`priority-pulse-animation`, `row`, `separator-lines`,
`suggested-button-selected`, `switch-min`, `today`, `transition`, `view`.

All 40 are defined in the stylesheets the port already ships, so these are
missing *applications*, not missing CSS. The `priority-*` set and
`item-label-child` land on the unported buttons and chips above;
`destructive-action` and `suggested-button-selected` are plain omissions on
buttons that do exist.

## Where the work is

1. **`core/Widgets` pickers** — 605 widget rows upstream, roughly 100 in the
   port. Every picker exists as its popover but not as its button, row or
   core list, which is why the port has pickers you cannot open from a row.
2. **The custom calendar** — 7 files, nothing ported.
3. **Shared structural widgets** — `HeaderItem`, `HeaderBar`, `ItemBase`,
   `ReorderChild`, `TextView`, `EditableTextView`. Five of these are reused
   across the whole app, so each one unblocks several views at once.
4. **Accounts setup** — Nextcloud, InboxPage, SourceView and the two SSL/
   resolve switch rows.
5. **Preferences sub-pages** — three pages collapsed into General.
6. **Accelerator behaviour** — typing-accelerator suspend/resume and
   `<Control>1..9` project switching.
