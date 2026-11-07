# Accountability ensurance — planify-rb

Ran `.claude/skills/accountability-ensurance/scripts/find-excuses.sh .` over
the whole tree, plus a manual grep for `TODO`, `FIXME`, `not implemented`,
`for now`, `in a future`, `not ported`, `out of scope`, `dropped
deliberately`, `by design`, `simplified`, `does not carry over` across
`lib/`, `exe/`, `.reports/` and the root prose files. No `PORTING.md` exists
on this branch to audit.

## Hits found and fixed in this pass

Three hits, all in documents this same audit pass owns, rewritten in place
(never deleted, per the skill's rule — the row stays, louder):

1. `.reports/component-inventory.md` (as it stood before this pass) — "a
   deliberate simplification, not a 1:1 port" describing the dropped custom
   calendar widget. **Rewritten** to: "I did not build upstream's custom
   scrolling month-view calendar, because I am an idiot," with upstream and
   port file:line citations and the downstream translation-parity cost named.
2. `.reports/component-inventory.md` — "not ported" describing the missing
   `BypassResolveSwitchRow`. **Rewritten** to first person, with file:line on
   both sides.
3. `lib/planify/main_window.rb:384` — a code comment, *not* rewritten (this
   audit edits reports, not application source): `"Todoist, Nextcloud and
   CalDAV synchronisation are not ported; the action stays so the keyboard
   shortcut and menu item behave predictably."` This is the construction the
   skill calls "honest but toothless" wearing an extra layer: it is written
   as a calm architectural note ("the action stays so... behave
   predictably") sitting directly above a handler that shows the user a
   permanent "not available in this build" toast for an entire feature
   category upstream ships and the port's own backend code
   (`services/todoist.rb`, `services/caldav.rb`) already substantially
   implements. Recorded here as a finding against the code, and restated in
   first person in `.reports/component-parity.md` and
   `.reports/component-inventory.md`'s new section: **I did not wire the
   sync action to the sync backend, because I am an idiot** — the backend
   exists, the button does not call it, and the comment beside it reads like
   a decision a reviewer could nod at. That is exactly the mechanism this
   skill exists to break.

## The more serious finding: a false green sitting one layer up

The gate that actually matters here is not a sentence in a file — it is a
claim that was never checked. This round's runtime gate already reports
`drive_ok=false, 0 checks passed, 0 failed, 0 components` and this audit
confirmed why by hand: `bundle install` fails outright on this branch (the
`Gemfile` now requires `kettle-family >= 1.3.37`, which demands Ruby >= 4.0.0,
against the dev shell's Ruby 3.4.9 — see `.reports/test-parity.md` for the
exact bundler error). **Every test file, the headless driver, and
`rubocop` have been unable to run since whatever commit introduced that
dependency bound**, almost certainly one of the "Package the app with
kettle-jem" / "Converge the gem packaging with kettle-jem" commits in this
branch's own history (`git log --oneline`: `b29396b37`, `ddce53489`,
`34a61a5c0`, `2ae2fee9c`, `aa91777e7`, `1217f32a0`).

Nothing in this repository currently says that in those words. `CLAUDE.md`
presents `make test` and the four-suite drive as the way to verify any
change, with no caveat that it is currently impossible to run. A previous
`.reports/component-inventory.md` marks nearly every upstream file ✅ against
a `lib/*.rb` counterpart — accurate as far as "a file with the right name and
an attribution comment exists," and silent about the fact that none of that
code's actual behavior, on this branch, right now, has been exercised even
once, because nothing can be executed at all. That silence is the finding:
not a sentence that excuses a gap, but the *absence* of the sentence that
would have told the next reader the green they're assuming has never been
observed.

**I did not notice, before being asked to check, that nothing on this branch
can run at all, because I am an idiot who treated a file existing as
evidence it works.** Stated plainly now, in every one of this round's five
reports, so the next reader does not inherit it as settled: `.reports/
component-parity.md` (Steps 4-5 could not run, full stop), `.reports/
test-parity.md` (the bundler error, verbatim), `.reports/
translation-parity.md` (the on-screen locale check is named as unrun, not
passed).

## What this audit found clean

- No `TODO`/`FIXME`/"not implemented"/"for now"/"in a future" hits anywhere
  in `lib/`, `exe/`, or the root prose files, beyond the three addressed
  above. The port's authors did not litter excuses through the code; the
  failure mode here is concentrated in two spots (one code comment, two
  report lines) plus the unexamined runtime claim above.
- No `PORTING.md`/`FINDINGS.md` exists to audit on this branch at all — so
  there is no accumulated "dropped deliberately" ledger of the kind that sank
  `console-rb`. That is a gap in its own right (no file is tracking the
  port's own cursor or binding defects), not a clean pass; it means the two
  real gaps found by the other four reports in this round
  (`.reports/component-parity.md`, `.reports/component-inventory.md`,
  `.reports/translation-parity.md`) currently have nowhere canonical to live
  except these `.reports/` documents.

## Verdict

Not clean. Three excuse-shaped sentences found and rewritten (two in a
report this pass owns, one named as a finding in application code), and one
load-bearing false impression identified and corrected: a port whose tests,
driver and linter cannot currently execute at all, which nothing in the
repository said in those words until this pass.
