# Component parity — simple-scan-rb

| | |
|---|---|
| Upstream | `origin/main` |
| Port | `ruby` |
| Units with full four-axis parity | not established — see below |

## What this report is, and is not

`.reports/component-inventory.md` (the `component-identification` output,
written across four earlier commits) is a file-mapping table only: one row
per upstream file/port file pair and a yes/no "present". It carries **no CSS
column, no signal column, no action column, no text column**. Per the
`component-identification` skill's own Step 5 rule — "Never list a widget
type without its CSS classes and signals" — that document does not meet its
own skill's bar. A reader who sees 26/26 "yes" rows and stops there would
conclude the port is finished; that conclusion is not supported by anything
the inventory actually recorded. This is flagged again in the
`accountability-ensurance` report: a report that looks complete without its
required columns is a false-green risk, not a finished survey.

This report does the four-axis check the inventory skipped, spot-checked
against the units that matter most (the ones with user-visible behaviour),
not exhaustively re-scanned line-by-line for all 26 mapped files given the
scope of this audit pass.

## Findings

### 1. Settings storage is not GSettings — a real behaviour difference presented as a non-issue

`lib/settings.rb` replaces upstream's `org.gnome.SimpleScan` GSettings schema
(`data/org.gnome.SimpleScan.gschema.xml`, 12 keys, each with a translatable
`<summary>`/`<description>`) with a JSON file under `XDG_CONFIG_HOME`. The
port's own header comment calls this deliberate: "requiring an install step
... is worse than the alternative." That sentence is exactly the construction
`accountability-ensurance` exists to catch — see that report.

Behaviourally this is a real gap, not just a reporting problem:
- `gsettings get org.gnome.SimpleScan ...` / `dconf-editor` / any other
  GSettings-aware tool can read and change upstream's settings; nothing can
  read or change the port's JSON file this way.
- The 12 keys' `<summary>`/`<description>` strings (26 translatable strings —
  see `.reports/translation-parity.md`) have no home in the port at all; the
  file that carried them does not exist on `ruby`.
- Range/choice enforcement that GSettings' schema XML declares (`<range>`,
  `<choices>`) is reimplemented by hand in `lib/settings.rb` and was not
  diffed key-by-key against the schema for this report.

**Verdict: gap.** `Gtk.Settings`/`Gio.Settings` axis — behaviour — fails for
the whole settings surface, not one widget.

### 2. `install_drivers_dialog.rb` depends on `packagekit-glib` but never calls it

`simple-scan-rb.gemspec:113` declares `spec.add_dependency("packagekit-glib",
"~> 1.0")`. `lib/install_drivers_dialog.rb`'s own header says: "The
`packagekit-glib` gem this app depends on could drive that the same way
upstream's `Pk.Task.resolve_async`/`install_packages_async` pair does; wiring
that live D-Bus install flow is not done yet."

Upstream's `install_drivers` (`src/app-window.vala`, `#if HAVE_PACKAGEKIT`
branch) offers to install the missing driver package directly. The port's
dialog only *names* the package and a vendor URL — the non-PackageKit
upstream fallback path, permanently, regardless of whether PackageKit is
available. The gem is in the dependency list and in `Gemfile.lock` but
`grep -n PackageKit lib/install_drivers_dialog.rb` matches nothing: it is
required nowhere, instantiated nowhere.

**Verdict: gap.** Behaviour axis — the PackageKit install action and its
signal/response handling are entirely unbuilt, on a component the drive
script marks `ok` only for the (correct, but partial) "names the package"
path:

```
ok   install drivers dialog -> ["You appear to have an HP scanner.", "You need to install the libsane-hpaio package."]
```

A check this narrow is why the task brief calls a check that doesn't
exercise a component "unverified, not done" — the PackageKit install button,
if it exists on screen at all, is never clicked by anything.

### 3. `data/org.gnome.SimpleScan.gschema.xml` has no port counterpart at all

Not a reduced/simplified version — the file, and every one of its 26
translatable strings, simply does not exist anywhere under `ruby`. See
`.reports/translation-parity.md` for the string count.

### 4. Drive script coverage does not reach every file

29 files exist under `lib/`. `test/drive_app_window.rb`'s 49 checks were run
(`DRIVE OK`, confirmed live in this audit) and its own count-27-components
claim is in the right range, but `resources.rb`, `translations.rb` and
`scanner.rb`'s SANE-device-discovery path are exercised only indirectly
(through objects built on top of them), never directly asserted against. In
particular there is no check anywhere that drives a *second*, different SANE
device being discovered/removed at runtime (upstream's `Scanner`
`device-added`/`device-removed` signal pair) — the drive script hard-codes
one scanner's capabilities and never varies it.

## What was not checked in this pass

Given the scope of this audit, the following were not re-verified against
every one of the 26 mapped files and are not claimed clean:
- CSS class attachment for `page_menu.rb`, `scan_options_popover.rb`,
  `document_action_bar.rb` against their upstream `.ui` style classes.
- Keyboard accelerator parity (`set_accels_for_action`) key-by-key against
  upstream's action-entries table.
- Crop/rotate pixel-geometry parity beyond what the drive script's four
  crop/rotate checks assert.

These are not claimed as gaps and not claimed as parity — they are unverified,
which this audit's own instructions treat as its own category, not a pass.

## Verdict

**Not clean.** At least two concrete behaviour gaps (settings backend,
PackageKit install flow) and one missing data file (gschema) are confirmed.
The existing `component-inventory.md` is insufficient on its own to claim
component parity because it never recorded the CSS/signal/action/text axes
the `component-parity` skill requires.
