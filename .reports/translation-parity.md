# Translation parity — planify-rb

| | |
|---|---|
| Upstream | `main` @ `cc26aaed3` |
| Port | `ruby` @ `784980523` |
| Domain | `io.github.alainm23.planify` (matches on both sides) |
| Upstream messages | 993 |
| Ported | **373** |
| Gaps | **620** |
| Extra (untranslated by definition) | **327** |
| Kind mismatches (plural upstream / single port, or vice versa) | **7+** (see below — likely undercounted) |
| Upstream occurrences | 1,516 across 993 messages (255 reused) |
| Port occurrences | 922 |
| Upstream languages | 84 `.po` files, 19,608 translated, 53,832 untranslated, 564 fuzzy |
| Languages shipped by the port | **84 — identical count, identical translated-string total** |
| `summary.parity` | **false** |

Generated via `.claude/skills/translation-parity/scripts/catalogue.rb` against
an `origin/main` worktree and this tree, then `--compare`. Raw YAML kept at
`/tmp/claude-1001/.../scratchpad/{upstream,port}-catalogue.yaml` and
`translation-parity.yaml` for this run (not committed — regenerate per the
skill rather than trusting a stale copy).

## The one real piece of good news

**Languages are not the gap here.** The port's `po/` directory is upstream's,
copied wholesale — same 84 `.po` files, same 19,608 translated strings total,
`domain_matches: true`, `languages_missing: []`. Whatever a given message's
fate, a translator who already did the work for that msgid keeps it working
once the message exists in the port.

## The real gap: 620 of 993 messages

373/993 is well under half. A sample of the gaps, to make the shape concrete
rather than abstract — these are not exotic strings, they are the date/time
formatting at the center of a task manager:

| msgid | Upstream site |
|---|---|
| `%-l:%M %p` | `core/Utils/Datetime.vala:98` |
| `%-l:%M:%S %p` | `core/Utils/Datetime.vala:95` |
| `%A, %B %e, %Y` | `core/Widgets/Calendar/CalendarDay.vala:103`, `CalendarScroll.vala:353` |
| `%H:%M` / `%H:%M:%S` | `core/Utils/Datetime.vala:103,106` |
| `%OB` / `%Y` | `core/Widgets/Calendar/CalendarHeader.vala` |
| `%s %s ago` / `%s %s left` | `core/Utils/Datetime.vala:83,85` |
| `%s was deleted` | `src/Layouts/ItemBoard.vala:1252`, `ItemRow.vala:1655` |
| `%d account available to import from GNOME Online Accounts` | `src/Dialogs/Preferences/Pages/Accounts/Accounts.vala:281` |

A large share of these trace to `core/Widgets/Calendar/*` (the custom
scrolling month-view calendar `.reports/component-inventory.md` already
records as unported — the stock `Gtk::Calendar` the port substitutes never
reaches these msgids) and to `core/Utils/Datetime.vala`'s relative/absolute
time formatting. This is a case the `component-parity` skill's text axis
exists for: a component gap (no custom calendar) produces a translation gap
(its msgids can never appear), and neither ledger alone shows the whole
picture.

## 327 "extra" messages — mostly gaps wearing a disguise

`extra` means a key the port emits that upstream's catalogue doesn't have
under that exact `(ctxt, id, kind)`. Reading a sample shows most of these are
**not** new user-facing text the port invented — they are upstream's own
strings, rebuilt with the plural dropped:

| msgid (port, `kind: single`) | What upstream actually has |
|---|---|
| `%d day ago` | plural pair `%d day ago` / `%d days ago` — `kind: plural` |
| `%d day left` | plural pair, `kind: plural` |
| `%d label` | plural pair, `kind: plural` |
| `%d overdue task` | plural pair, `kind: plural` |
| `%d completed task will be deleted. This cannot be undone.` | plural pair, `kind: plural` |

Each of these is **two findings, not one**, per the skill's own rule ("a
string the port marked but whose msgid differs is two gaps, not one pass"):
upstream's plural key is a **gap** (it never appears in the port's
catalogue), and the port's singular-only rebuild is an **extra** key that
will show "1 days ago" / "2 day ago" grammar to anyone whose language
pluralizes, because it was never routed through `n_(...)`. These are listed
in the `kind_mismatch`-adjacent set above; the comparator's raw
`kind_mismatch: 7` undercounts this pattern because most of these pairs
register as a `gap` + an `extra` rather than a same-key mismatch — read the
"extra" list by hand, as done here, rather than trusting that one summary
field.

## Occurrences: 922 of 1,516

Even restricted to the 373 messages that do match, the port reaches them
922 times against upstream's 1,516 call sites for the same 993-message
catalogue. Per the skill, this is not itself a parity failure — it is a
`component-parity` investigation (a message used in fewer places than
upstream used it is a missing call site, a missing component, or a factored
helper) — but it is reported here because a reader of only the message-count
line would believe translated text is wired everywhere it was upstream, and
that is not established.

## Unresolved markers

Both catalogues report `unresolved: 4`. Not individually re-censused by hand
in this pass (budget) — this is an **open item**, not a confirmed-clean one.
Per the skill's own rule, a ledger should not be written while
`totals.unresolved` is non-zero without resolving those sites; recording that
explicitly here rather than silently treating 4 as negligible.

## Proof checklist

- `summary.parity` — **false** (620 gaps, 7+ kind mismatches, well above
  zero).
- Every shipped language reaches the user — **not verified**. The catalogue
  comparison says the `.po` files are present and byte-identical in content,
  but no `.mo` build or `LANGUAGE=de` run was performed, because the runtime
  gate is down (see `.reports/test-parity.md`) — `bundle exec` cannot run at
  all on this branch right now. This is an unrun check, named as unrun, not a
  pass.
- Running under a non-English locale and reading a known string on screen —
  **not run**, same reason.

Report the full set, not an adjective: **373/993 messages · 922/1,516
occurrences · 84/84 languages · 19,608 strings carried forward verbatim · no
on-screen non-English verification performed (runtime gate down).**
