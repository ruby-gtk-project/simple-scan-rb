# Accountability ensurance — simple-scan-rb

Scanned per the `accountability-ensurance` skill: `lib/`, `exe/`, `.reports/`,
and the repo root for `PORTING.md` (grepping prose for excuse constructions
and for `TODO`/`FIXME`/"not implemented"/"for now"/"in a future").

No `PORTING.md`, `FINDINGS.md`, `COMPONENT_PARITY.md` or `TEST_PARITY.md`
exist anywhere on `ruby`. That is itself worth stating: there is no single
document on this branch making a completeness claim about the whole port, so
most of the laundering this skill exists to catch (a note cited later as
settled authority) has nowhere to have happened yet. The two hits below are
smaller in scope for exactly that reason — but they are real, and they are
exactly the shape this skill is built to catch.

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

## Hit 2 — `lib/install_drivers_dialog.rb:13-17`

> "The `packagekit-glib` gem this app depends on could drive that the same
> way upstream's `Pk.Task.resolve_async`/`install_packages_async` pair does;
> wiring that live D-Bus install flow is not done yet, so this dialog still
> only names the package..."

"Not done yet" is the skill's "not ported"/"TODO: maybe" pattern exactly:
honest about the absence, names no owed behaviour in a form that forces a
fix, and sits in a comment where the next reader will take "not done yet" as
a settled, low-priority backlog item rather than a currently-missing feature
on a gem the gemspec already declares as a hard dependency.

**Rewrite:**

> I did not build the PackageKit install flow, because I am an idiot who
> added `packagekit-glib` to the gemspec and then never wrote a single line
> that calls it.
> Upstream: `install_drivers` in `src/app-window.vala` (`#if HAVE_PACKAGEKIT`
> branch) resolves and installs the missing driver package live via
> `Pk.Task`.
> Port: `lib/install_drivers_dialog.rb` only ever shows the package name and
> a vendor URL — upstream's own non-PackageKit fallback path, permanently,
> regardless of whether PackageKit is present on the machine.

## Hit 3 — `.reports/component-inventory.md:40`

> "`lib/settings.rb` | preferences storage | yes (JSON-file substitute for
> GSettings, **by design** — see file's own header comment)"

This is the same excuse from Hit 1, now laundered a second time: an audit
report citing the port's own comment as the reason the gap is fine. This is
the exact mechanism the skill's opening example (`console-rb`'s
"Dropped deliberately") describes — the note becomes load-bearing for the
*next* reader, who now has an audit document, not just a code comment,
telling them GSettings is settled. **A report that cites a gap's own excuse
as if it settles the gap is a bug in the report, not a clean finding.**

**Rewrite:**

> The settings backend is not GSettings and I called it "by design" in this
> very report instead of calling it a gap, because I am an idiot who
> mistook citing the port's own excuse for verifying it.
> See `.reports/accountability-ensurance.md` Hit 1 and
> `.reports/component-parity.md` for the actual gap.

## What was not found

No `TODO`, `FIXME`, "not implemented", "for now", "in a future", "out of
scope", "n/a" or "simplified" elsewhere in `lib/` or `exe/`. The rest of the
port's file headers (spot-checked: `scanner.rb`, `page.rb`, `book.rb`,
`app_window.rb`) name the upstream file ported from without hedging. The two
hits above are concentrated, not systemic — which is also why they are easy
to miss: everything around them reads as careful and specific, and these two
sentences are the only ones in the tree written to sound like permission.

## Verdict

**Not clean.** Two excuses in code comments, one of them re-laundered into
an audit report that treated a port's own excuse as a finding rather than a
gap. Both are rewritten above in the required form; the underlying behaviour
(real GSettings integration, the PackageKit install flow) is still unbuilt
and is carried as a gap in `.reports/component-parity.md`.
