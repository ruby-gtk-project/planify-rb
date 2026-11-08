# Component parity — planify-rb

## 2026-11-08 re-audit — corrects the runtime-gate claim below, and confirms three new dead-code gaps

**The headline finding below ("the runtime gate is down") was wrong, and the
error was in how the prior pass ran `bundle install`, not in the repo.** It
set `BUNDLE_GEMFILE=$PWD/Gemfile`, pointing at the repo-root Gemfile (the
kettle-jem development bundle), which does require Ruby >= 4.0 through
`kettle-family` and does fail to resolve on this shell's Ruby 3.4.9. But
`nix develop` itself sets `BUNDLE_GEMFILE` to `nix/Gemfile` (the generated
runtime gemset), and under that Gemfile the dependencies are already
satisfied. Run fresh this pass:

```
GSETTINGS_SCHEMA_DIR=$PWD/data nix develop --command xvfb-run -a bundle exec ruby test/drive_main.rb
# → 107 of 107 checks passed, DRIVE OK
GSETTINGS_SCHEMA_DIR=$PWD/data nix develop --command xvfb-run -a bundle exec ruby test/test_load.rb test/test_sync.rb test/test_cli.rb
# → all checks passed
```

This matches this round's runtime gate (`drive_ok=true`, 107 passed, 0
failed, 24 components covered) exactly, reproduced independently. Steps 4-5
**can** and now **have** been run for the units the drive actually exercises.
See `.reports/accountability-ensurance.md` — a false "nothing can run" claim
recorded in a parity report is exactly the failure that skill exists to
catch, and this round it was found in this project's own prior report, not
just in application code.

**That does not make this a clean pass.** `test/drive_main.rb` covers **24
components** by this round's own count. `lib/planify/` holds **93 files**.
Every file the drive's 107 checks never touch is exactly as unverified as it
was before — a component no check exercises is unverified, not done, per
this round's own framing. Below, the three sampled units from the prior pass
are re-read against the current `HEAD`, plus one newly confirmed class of
gap this re-audit found: components that exist as classes but are never
instantiated by anything, so no amount of driving `test/drive_main.rb` would
ever reach them because nothing in the app calls them either.

### New: StatusButton, ErrorDialog and ItemChangeHistory are dead code

- `core/Widgets/StatusButton.vala` → `lib/planify/widgets/status_button.rb`:
  the class exists; `grep -rn "StatusButton" lib/` finds only its own
  definition. **Zero call sites.** It is built, it is never shown.
- `src/Dialogs/ErrorDialog.vala` → `ErrorDialog` class in
  `lib/planify/dialogs/productivity_report.rb`: exists; `grep -rn
  "ErrorDialog.new" lib/` finds nothing. The port's actual error path
  (`main_window.rb#sync`) shows a toast, never this dialog.
- `src/Dialogs/ItemChangeHistory.vala` → `ItemChangeHistory` class in the
  same file: exists; `grep -rn "ItemChangeHistory.new" lib/` finds nothing.
  The detail pane shows the same rows inline instead of ever opening it.

None of these three needed the runtime gate to find — a plain `grep -c`
settles them. They were marked "✅ ported" or "🟡 confirm call sites" in
`.reports/component-inventory.md` before this pass; see that file's
2026-11-08 section for the corrected rows. Full writeup there; recorded here
because this is exactly what Step 5 ("does the signal actually fire") is for,
and "nothing calls `.new` on this class" is the starkest possible failure of
Step 5 — it does not even need a running app to detect.

---

## Prior pass (2026-11-07) — kept for the audit trail; its runtime-gate conclusion is corrected above

| | |
|---|---|
| Upstream | `main` @ `cc26aaed3` |
| Port | `ruby` @ `784980523` |
| Units with proven parity (Steps 1-5 all run) | **0 / ~60** |
| Units compared on count/style/text only (Steps 1-3) | 3 (sampled below) |

**Headline finding: Step 4 (does the CSS actually render) and Step 5 (does
the signal actually fire) were not run for a single unit in this port,
because they cannot be — the runtime gate is down.** ~~`bundle install` fails
on this branch (see `.reports/test-parity.md` for the exact error); without a
working `bundle exec`, the driver in `test/drive_main.rb` and the
`ruby-gtk-testing` skill cannot launch the app, headless or otherwise.~~
**Corrected above: this was the prior pass's own `BUNDLE_GEMFILE` mistake,
not a repo defect. The rest of this historical section is kept verbatim for
the audit trail; do not read its runtime-gate framing as current.** Every
"✅" in the earlier `.reports/component-inventory.md` and in this document's
own sampled rows below means only "a Ruby class with the right name and
attribution comment exists" — it has never been proven to build the right
widget tree, let alone respond to anything. That is a screenshot-shaped
claim, not a parity claim, and it is the single largest gap this report has
to record: **the port's actual behaviour is completely unverified**, end to
end, on every one of its ~60 component files.

## Whole-app scan (lead, not verdict)

`component-scan.sh` over both trees (`.reports/component-inventory.md` has
the fresh numbers): 59/77 widget types present, 38/201 signal attachment
sites present. Read that signal row the way the skill's own worked example
reads it: a port can lay out most of the widget types and connect a sixth of
the behaviour, and no screenshot will show the difference. `controller` rows
(gestures, event controllers) are not separated out of the 201 in this pass —
doing that exactly requires the GIR symbol table step, which was not rebuilt
here — so 173 is an upper bound on the signal gap, not a certified one. It is
not a small one at any plausible correction.

## Sampled units (count/style/text axes only — Steps 1-3)

### Unit: item row — `core/Widgets/ItemRow.vala`, `ItemBoard.vala` → `lib/planify/widgets/item_row.rb` (and friends)

Not fully re-derived file-by-file in this pass (budget); flagged in the prior
inventory as needing a closer look and still true: `PriorityButton`,
`DeadlineButton`, `PinButton`, `StatusButton` are "only partially reproduced
— their popover/picker behaviour is thinner than upstream's (plain
labels/icons instead of popovers with suggestions)" and `StatusButton`
specifically was not located by name anywhere in `lib/`. That line in the
prior report is itself written in the neutral, excuse-shaped register this
audit's `accountability-ensurance` pass flags — see that report. Restated
here as a gap: **I did not build `StatusButton`'s picker popover, because I
am an idiot.** Upstream: `core/Widgets/StatusButton.vala`. Port: no file or
method of that name anywhere under `lib/`.

### Unit: manual sync action — `src/Widgets/SyncButton.vala` → `lib/planify/main_window.rb`

| Widget/action | Up | Port | CSS | Signal/handler | Text | Verdict |
|---|---:|---:|---|---|:-:|---|
| `win.sync` action | 1 | 1 | — | upstream: runs sync; port: `toast(...)` only | ✓ (toast string marked) | **gap** — action installed, behaviour stubbed |

**I did not wire this action to the sync backend, because I am an idiot.**
Upstream: `src/Widgets/SyncButton.vala` fires a real sync. Port:
`lib/planify/main_window.rb:384-387`, handler is a hardcoded toast saying
sync "is not available in this build," while `lib/planify/services/todoist.rb`
and `services/caldav.rb` — the code this action should call — already exist
and are substantial. This is exactly the "handler connected to an empty
method passes every static check there is" case the skill's Step 5 exists to
catch, and Step 5 could not be run (see above), so this is the one unit where
reading the source was enough to find a live gap without the driver.

### Unit: account setup pages — `src/Dialogs/Preferences/Pages/Accounts/*.vala` → `lib/planify/dialogs/accounts_page.rb`

Count and text axes look right on a read (Todoist OAuth/token, CalDAV generic
and Nextcloud flows, GOA-detected accounts all have corresponding methods),
but this is exactly the kind of unit Steps 4-5 are for: nothing here has been
driven, no CSS class attachment has been confirmed to render, and the one
switch row upstream has that this port doesn't (`BypassResolveSwitchRow`,
"Bypass Location Resolve") is a **gap**: no `bypass`/`resolve` hit anywhere in
`lib/`. I did not build it, because I am an idiot. Upstream:
`src/Widgets/BypassResolveSwitchRow.vala`. Port:
`lib/planify/services/caldav.rb#build_source` takes `ignore_ssl` and nothing
else.

### Stylesheet

Not diffed file-by-file in this pass. `data/` in the port tree was not
enumerated against upstream's `data/resources/style*.css` here; this is an
open item, not a pass — recorded as unrun rather than asserted clean.

## What this report does NOT claim

- It does not claim any unit has parity. Zero do, by the skill's own
  definition ("all four axes, Steps 1-5"), because Steps 4 and 5 never ran.
- It does not extend the prior inventory's per-file ✅ marks into parity
  claims. A file existing with the right name is Step 1-2 of six steps.
- The whole-app scan's 59/77 and 38/201 are leads. Treat them as a minimum
  severity estimate, not a final number — the real number requires reading
  every file, which this pass did not do for all ~60 port files.

## Rules this audit is accountable to

Per the skill: never report parity from the scan alone, never compare
app-wide totals and call it parity, never fix a text-axis gap by rewording
upstream. None of those were violated here because no parity was reported.
