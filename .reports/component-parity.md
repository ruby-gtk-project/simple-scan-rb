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

### 2. `install_drivers_dialog.rb`'s PackageKit flow — code gap resolved, verification gap remains

**Update (this audit pass):** this is no longer the gap the prior report
described. Commit `5d7e894e` ("Port the man page and Mallard help pages;
wire PackageKit driver install") wired this up: `lib/install_drivers_dialog.rb`
now `require`s `packagekit_glib`, builds a `PackageKitGlib::Task`, and calls
`resolve_sync`/`install_packages_sync` on a background `Thread`, marshalling
the result back to the GTK main loop via `GLib::Idle.add` — confirmed by
reading the file directly, and matching upstream's `#if HAVE_PACKAGEKIT`
`Pk.Task.resolve_async`/`install_packages_async` shape in
`src/app-window.vala`. The header comment's "not done yet" hedge is gone.

It is real code, but it is still not proven to *work end to end*, and the
drive script's own output from this audit pass shows why:

```
Failed to install drivers: GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown: The name is not activatable
ok   install drivers dialog -> ["You appear to have an HP scanner.", "You need to install the libsane-hpaio package."]
```

The check still only asserts the same two display strings it asserted
before PackageKit was wired; it would pass identically whether the
PackageKit call succeeds, fails, or — as it does in the xvfb-run sandbox
used for this very audit, where no PackageKit D-Bus service is activatable
— errors out before reaching `install_packages_sync` at all. Nothing in
`test/drive_app_window.rb` asserts on the resolve/install call itself, its
success path, or the dialog's handling of a failed install. Per the task
brief — "a component no check exercises is unverified, not done" — the
*install mechanism* (as opposed to the dialog's static text, which the
check does cover) is unverified by anything that runs.

**Verdict: code gap resolved; narrow-check gap remains on the install path
specifically.**

### 3. `data/org.gnome.SimpleScan.gschema.xml` has no port counterpart at all

Not a reduced/simplified version — the file, and every one of its 26
translatable strings, simply does not exist anywhere under `ruby`. See
`.reports/translation-parity.md` for the string count.

### 4. `data/simple-scan.desktop.in` and `data/simple-scan.appdata.xml.in` exist in the repo but are installed nowhere

Both files are present verbatim under `ruby`'s `data/` (confirmed earlier in
`translation-parity.md`). This audit pass checked whether anything actually
installs them: `grep -rn "simple-scan.desktop\|applications/" flake.nix
simple-scan-rb.gemspec exe/*` returns nothing. `flake.nix` installs the man
page to `$out/share/man/man1/` and help pages to `$out/share/help/`, but has
no equivalent step for `$out/share/applications/simple-scan.desktop` or an
AppStream metainfo directory. Upstream's `data/meson.build` installs both.
The practical effect: even a from-source install of this port never gives
the app a desktop-grid/app-switcher launcher entry or appears in a software
centre — the files sitting in the repo are inert.

**Verdict: gap**, separate from (but related to) the translation gap
`translation-parity.md` already flags for the same two files.

### 5. Upstream help pages are ported in English only — 40 of 41 language trees missing

`flake.nix` installs whatever directories exist under `help/*/` into
`$out/share/help/<lang>/simple-scan/`, which is the right mechanism, but
`ruby`'s `help/` tree only contains `help/C/*` (19 files, confirmed by
`find help -type f`). Upstream's `help/LINGUAS` lists 40 translated help
trees (`ar`, `bg`, `ca`, `cs`, `da`, …). None were ported. A non-English
user who opens in-app help (`app.help` → `help:simple-scan`) gets the
English pages regardless of their locale, where upstream would show their
own language's help if present.

**Verdict: gap.**

### 6. Drive script coverage does not reach every file

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

**Not clean.** Since the prior pass, two real fixes landed (PackageKit
install code is now wired; the man page and English help pages are ported
and installed) — credited above, not re-litigated as gaps. But confirmed
gaps remain: the settings backend (JSON, not GSettings), the entirely
missing gschema data file and its 26 strings, the desktop/appdata files
being present but installed nowhere, 40 of 41 help-page language trees
missing, and the PackageKit install path being code-complete but exercised
by nothing that asserts success or failure. The existing
`component-inventory.md` is insufficient on its own to claim component
parity because it never recorded the CSS/signal/action/text axes the
`component-parity` skill requires.
