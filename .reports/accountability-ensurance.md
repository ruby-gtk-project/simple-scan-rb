# Accountability ensurance — simple-scan-rb

Scanned per the `accountability-ensurance` skill: `lib/`, `exe/`, `.reports/`,
and the repo root for `PORTING.md` (grepping prose for excuse constructions
and for `TODO`/`FIXME`/"not implemented"/"for now"/"in a future").

No `PORTING.md`, `FINDINGS.md`, `COMPONENT_PARITY.md` or `TEST_PARITY.md`
exist anywhere on `ruby`. That is itself worth stating: there is no single
document on this branch making a completeness claim about the whole port, so
most of the laundering this skill exists to catch (a note cited later as
settled authority) has nowhere to have happened yet.

**Update (this audit pass, re-scanning the current `ruby` HEAD):** of the
three hits the prior pass of this report recorded, two are now resolved —
Hit 2 (the PackageKit "not done yet" comment) by the gap actually being
built, and Hit 3 (the laundered "by design" row in
`component-inventory.md`) by that row being rewritten without the excuse.
Both are detailed below, credited rather than re-flagged, with the grep
evidence that confirms removal rather than rewording. Hit 1 — the
settings.rb GSettings excuse — is unchanged: `sed -n '14,22p' lib/settings.rb`
in this pass returns the identical text quoted below. A fresh grep this
pass across `lib/`, `exe/`, every `.reports/*.md` file and the repo root
(`PORTING.md` still does not exist) for `TODO`, `FIXME`, "not implemented",
"for now", "in a future", "out of scope", "simplified", "n/a", "placeholder"
and "stub" found exactly one hit — a false positive in `lib/scanner.rb:558`
(`@options['AutoDocumentSize']` case-insensitively contains the letters
`toDo` inside `AutoDocumentSize`, matching the `TODO` pattern) — confirmed
by reading the line directly; it is a GSettings-style key name, not prose,
and not an excuse construction.

## Hit 1 — `lib/settings.rb:16-20`

> "Upstream reads the first group through GSettings, which needs a schema
> compiled into the system's glib-2.0/schemas directory; requiring an
> install step before the app will start from a checkout is worse than the
> alternative, so the same keys, defaults, ranges and choices are backed by
> a JSON file..."

This is "by design"/"the alternative is worse" dressed as a sound
engineering trade-off. It is a real-sounding reason, which is precisely why
it is dangerous: a reader nods along and files GSettings integration as
settled, not owed. Per the skill: a binding/packaging difficulty is a reason
a gap is *hard*, never a reason it is *closed*.

**Rewrite:**

> I did not build real GSettings-backed settings, because I am an idiot who
> decided a packaging inconvenience was a reason to drop system integration
> instead of a problem to solve.
> Upstream: `data/org.gnome.SimpleScan.gschema.xml` (12 keys, 26
> translatable summary/description strings), read via `GLib.Settings` in
> `src/app-window.vala`'s `load_state`/`save_state`.
> Port: `lib/settings.rb` reads and writes a hand-rolled JSON file under
> `XDG_CONFIG_HOME` instead. No `gsettings`/`dconf-editor` visibility, and
> the 26 schema strings have no file to live in at all (see
> `.reports/translation-parity.md`).

## Hit 2 — RESOLVED since the prior pass: `lib/install_drivers_dialog.rb`'s "not done yet"

The prior pass of this report quoted `lib/install_drivers_dialog.rb:13-17`
excusing an unbuilt PackageKit install flow with "not done yet." Re-checked
in this pass: that sentence is gone. Commit `5d7e894e` wired the flow up
(`PackageKitGlib::Task#resolve_sync`/`install_packages_sync` on a background
`Thread`, result marshalled via `GLib::Idle.add`) and rewrote the header
comment to describe what the code does, not what it is missing — confirmed
by reading the current file directly, not by trusting the commit message.
This is exactly the right kind of fix for a Hit in this report: the excuse
was removed by building the thing, not by rewording the excuse. Credited,
not re-flagged.

One caveat carried into `.reports/component-parity.md` and
`.reports/test-parity.md` instead of repeated here: the code being honestly
described now is not the same as the code being verified — no check
exercises the PackageKit call succeeding or failing. That is a narrow-check
finding, not an accountability finding, because nothing in the current
source text excuses it or claims it is covered; it is reported plainly
where it belongs.

## Hit 3 — RESOLVED since the prior pass: `.reports/component-inventory.md`'s laundered "by design" row

The prior pass quoted a row at `.reports/component-inventory.md:40` reading
"yes (JSON-file substitute for GSettings, **by design** — see file's own
header comment)" and flagged it as the excuse from Hit 1 laundered a second
time into an audit report. Re-checked in this pass: `grep -n "by design"
.reports/component-inventory.md` now matches nothing, and the current row
for `lib/settings.rb` (line 81) reads only `| settings | yes |`, with no
editorializing about the gap being settled. The laundering this report's
own prior pass caught has been removed from the cited document; it does not
reappear elsewhere in `.reports/` (checked by grepping all five report files
for "by design", "deliberately" and "settled" in this pass — no hits
outside this report's own text quoting the removed line for the record).

Credited, not re-flagged. The underlying gap (settings backend is JSON, not
GSettings) is unchanged and still carried honestly, without an excuse, in
`.reports/component-parity.md` finding 1 and Hit 1 above.

## Re-audit pass (2026-11-08, commits `aa2cf654`/`447e9f6c`)

Both new commits were read in full for this pass. `aa2cf654`'s gemspec
comment ("gem_kit is deliberately NOT listed here... it still arrives at
runtime as packagekit-glib's own dependency") explains a real decision with
a verifiable technical reason (a transitive dependency, not a gap being
excused) — checked against the skill's own test ("is something unbuilt
being called settled?") and it passes: nothing is left unbuilt by that
comment, it is describing why a *redundant* declaration was removed. Not a
hit.

`aa2cf654` also changed the PackageKit check from asserting only the
dialog's static strings to waiting on `install_finished?` and reading back
the live result — the opposite of laundering: a check that previously could
not catch a stuck round trip now can. Re-ran the full grep sweep from the
prior pass (`TODO`, `FIXME`, "not implemented", "for now", "in a future",
"out of scope", "simplified", "n/a", "placeholder", "stub") across `lib/`,
`exe/`, every `.reports/*.md` file, `flake.nix`, `simple-scan-rb.gemspec`
and the repo root: same single false positive (`AutoDocumentSize`) as
before, no new hits. `PORTING.md` still does not exist on this branch.

## What was not found

No real `TODO`, `FIXME`, "not implemented", "for now", "in a future", "out
of scope", "n/a" or "simplified" elsewhere in `lib/` or `exe/` (the one
regex hit is the `AutoDocumentSize` false positive above). The rest of the
port's file headers (spot-checked: `scanner.rb`, `page.rb`, `book.rb`,
`app_window.rb`, `install_drivers_dialog.rb` this pass) name the upstream
file ported from without hedging. Hit 1 remains concentrated, not systemic.

One more thing checked specifically for this pass, because it is exactly
the shape this skill looks for: `data/simple-scan.desktop.in` and
`data/simple-scan.appdata.xml.in` being present but never installed, and 40
of 41 help-page language trees being missing (both new findings in
`.reports/component-parity.md` and `.reports/translation-parity.md` this
pass), are **not** excused anywhere — no comment, report sentence or
`PORTING.md` entry calls either of them deliberate, out of scope, or
settled. They are reported as plain gaps in their own reports, which is the
correct, unlaundered way to carry a gap forward.

## Verdict

**Not clean, but improved since the prior pass.** Of the three accountability
hits previously recorded, two are now resolved by the underlying gap
actually being built or the laundered line being removed — credited above,
not re-flagged. One excuse remains unchanged: `lib/settings.rb`'s "worse
than the alternative" framing of the GSettings-to-JSON substitution. That
gap (real GSettings integration) is still unbuilt and is carried honestly
as a gap in `.reports/component-parity.md`. No new laundering was
introduced in this pass's two new report findings (desktop/appdata
installation, help-page translations) — they are stated as gaps, not
excused.
