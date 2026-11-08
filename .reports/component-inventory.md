# simple-scan — component inventory

Upstream read from `origin/main` (`git ls-tree -r --name-only origin/main`,
`git show origin/main:<path>`). Port state read from `lib/` on `ruby`
(current HEAD at time of writing).

Upstream is a single monolithic window: `src/app-window.vala` (≈2100 lines)
plus `data/ui/app-window.ui` build the vast majority of the UI in one class,
with dialogs, menus, a popover, an action bar and a status page all declared
or constructed inline inside it. The Ruby port already splits each of those
into its own `lib/*.rb` file, one component per file, per the house style —
so several rows below map the *same* upstream file to *several* port files.
That is the port working as intended, not duplication.

## Legend

- **kind** — window / dialog / page / popover / menu / action-bar / status-page
  / widget / model / service / backend / settings / resources / i18n / app
- **exists** — a file already present under `lib/` on `ruby`

## Application

| Upstream file | → lib path | kind | exists |
|---|---|---|---|
| `src/simple-scan.vala` (`SimpleScan : Gtk.Application`) | `lib/simple_scan/application.rb` | app | yes |
| — (gem entrypoint, no upstream file) | `lib/simple_scan.rb` | app (entrypoint) | yes |
| — (gem entrypoint, no upstream file) | `lib/simple/scan/rb/version.rb` | version constant | yes |

## Main window and the components built inside it

`src/app-window.vala` (class `AppWindow : Hdy.ApplicationWindow`) + its
template `data/ui/app-window.ui` together build everything in this section.

| Upstream file(s) | → lib path | kind | exists |
|---|---|---|---|
| `src/app-window.vala` + `data/ui/app-window.ui` | `lib/app_window.rb` | window | yes |
| `src/app-window.vala` (`Gtk.ActionBar action_bar`, "Populate ActionBar" block) + `data/ui/app-window.ui` (`class="GtkActionBar"`) | `lib/document_action_bar.rb` | action-bar | yes |
| `src/app-window.vala` (`Gtk.Menu page_menu`, `update_page_menu`, `show_page_menu_cb`) + `data/ui/app-window.ui` (`class="GtkMenu"`/`GtkRadioMenuItem` for the page context menu) | `lib/page_menu.rb` | menu | yes |
| `src/app-window.vala` (`scan_options_image`, `menu_button`, `set_scan_type`, `gear_menu`) + `data/ui/app-window.ui` (`class="GtkPopover"`) | `lib/scan_options_popover.rb` | popover | yes |
| `src/app-window.vala` (`ScanOptions` construction, `make_scan_options`) + `src/scanner.vala` (`public class ScanOptions`) | `lib/scan_options.rb` | model | yes |
| `src/app-window.vala` (`status_page`, `set_scan_devices`, scanning/no-scanner states) + `data/ui/app-window.ui` (`class="HdyStatusPage"`) | `lib/scanner_status_page.rb` | status-page | yes |
| `src/app-window.vala` (`install_drivers()`, `missing_driver`, the "install-firmware" link handler) | `lib/install_drivers_dialog.rb` | dialog | yes |
| `src/app-window.vala` (`CancellableProgressBar : Gtk.HBox`, defined at EOF of the same file) | `lib/cancellable_progress_bar.rb` | widget | yes |
| `src/app-window.vala` (`draw_page`, `Gtk.PrintOperation print`, `print.run`) | `lib/print_operation.rb` | service | yes |
| `src/app-window.vala` (`reorder_document`, `make_reorder_button`, `make_reorder_box`) | `lib/reorder_pages_dialog.rb` | dialog | yes |
| `src/app-window.vala` (`Gtk.FileChooserNative save_dialog`, save-related `Gtk.MessageDialog`s) | `lib/save_dialog.rb` | dialog | yes |
| `src/app-window.vala` (`about_cb`, inline `Gtk.AboutDialog`, "About Document Scanner" title) | `lib/about_dialog.rb` | dialog | yes |
| `src/app-window.vala` (the `Gtk.MessageDialog`s for save/lost-document/error warnings, not the about or install-drivers ones) | `lib/alerts.rb` | widget (helper) | yes |

## Dialogs with their own `.ui`/source pair

| Upstream file | → lib path | kind | exists |
|---|---|---|---|
| `src/preferences-dialog.vala` (`PreferencesDialog : Hdy.PreferencesWindow`) + `data/ui/preferences-dialog.ui` | `lib/preferences_dialog.rb` | dialog | yes |
| `src/authorize-dialog.vala` + `data/ui/authorize-dialog.ui` | `lib/authorize_dialog.rb` | dialog | yes |
| `data/ui/help-overlay.ui` (no backing source file — a standalone shortcuts window template) | `lib/shortcuts_dialog.rb` | dialog (shortcuts window) | yes |

## Document model and page widgets

| Upstream file | → lib path | kind | exists |
|---|---|---|---|
| `src/book.vala` (`Book`) | `lib/book.rb` | model | yes |
| `src/book-view.vala` (`BookView : Gtk.Box`) | `lib/book_view.rb` | widget/view | yes |
| `src/page.vala` (`Page`) | `lib/page.rb` | model | yes |
| `src/page-icon.vala` (`PageIcon`) | `lib/page_icon.rb` | widget | yes |
| `src/page-view.vala` (`PageView`) | `lib/page_view.rb` | widget | yes |
| `src/autosave-manager.vala` (`AutosaveManager`) | `lib/autosave_manager.rb` | service | yes |

## Scanning backend

| Upstream file | → lib path | kind | exists |
|---|---|---|---|
| `src/scanner.vala` (`Scanner`, `ScanDevice`, `ScanJob`, `ScanLine`, `ScanPageInfo`, the `Notify*`/`Request*` state machine) | `lib/scanner.rb` | backend | yes |
| `src/sane-backends.vapi` (the raw libsane C binding Vala links against directly — SANE has no GObject-introspection, hence the direct binding on both sides) | `lib/sane_api.rb` | backend (FFI) | yes |
| `src/screensaver.vala` (`Screensaver`, inhibit while scanning) | `lib/screensaver.rb` | service | yes |

## Settings, resources, i18n

| Upstream file | → lib path | kind | exists |
|---|---|---|---|
| `data/org.gnome.SimpleScan.gschema.xml` (the `org.gnome.SimpleScan` GSettings schema: `selected-device`, `document-type`, `paper-width`/`paper-height`, scan-type, etc.) | `lib/settings.rb` | settings | yes |
| `data/simple-scan.gresource.xml` (bundles `ui/app-window.ui`, `ui/preferences-dialog.ui`, `ui/authorize-dialog.ui`, `ui/help-overlay.ui`, 3 symbolic icons) | `lib/resources.rb` | resources | yes |
| `po/*.po` + `po/LINGUAS` (76 languages) | `lib/translations.rb` | i18n | yes |

## Not yet mapped to any `lib/*.rb` file

| Upstream file(s) | kind | notes |
|---|---|---|
| `data/icons/hicolor/scalable/org.gnome.SimpleScan.svg`, `data/icons/hicolor/symbolic/org.gnome.SimpleScan-symbolic.svg`, `data/icons/scalable/actions/{crop,scan-type-adf,scan-type-batch}-symbolic.svg` | app/action icons | no icon asset pipeline found under the port's `data/`; needs a home before the port can show its own icon or the scan-type icons `scan_options_popover`/`scanner_status_page` reference |
| `data/simple-scan.desktop.in` | desktop launcher | present verbatim under `data/`, but **never installed anywhere** — `flake.nix` installs the man page and `help/**` (`$out/share/man/man1`, `$out/share/help/<lang>/simple-scan`) but has no `$out/share/applications/` step and the gemspec does not package it either; grep for `desktop`/`applications/` across `flake.nix`, `simple-scan-rb.gemspec`, `exe/*` returns nothing. The file sitting in the repo is not the same as a launcher the desktop ever sees. |
| `data/simple-scan.appdata.xml.in` | AppStream metadata | same as above: present under `data/`, never installed, never referenced by anything that would register it with a software centre |
| `data/simple-scan.1` | man page | **resolved since the prior pass** — ported verbatim (`diff` against `origin/main:data/simple-scan.1` is empty) and installed to `$out/share/man/man1/` by `flake.nix` |
| `help/**` (the Mallard user-help pages, 30+ languages) | user documentation | **resolved since the prior pass, partially** — the English `help/C/*` pages are ported verbatim (`diff` against `origin/main:help/C/index.page` is empty) and `flake.nix` installs `help/*/` into `$out/share/help/<lang>/simple-scan/`. Only the `C` (English) tree exists under `ruby`'s `help/`; upstream's `help/LINGUAS` lists 40 translated help trees, none of which were ported — confirmed by `find help -type f` returning only `help/C/*`, 19 files total, no other language directories. |

## Totals

- Upstream Vala/UI component-bearing files: 12 `src/*.vala` + 4 `data/ui/*.ui`
  + 1 gschema + 1 gresource manifest = 18.
- Upstream translation catalogue: 76 languages in `po/LINGUAS`.
- `lib/*.rb` files on `ruby`: 29 (including the two gem-boilerplate
  entrypoints `lib/simple_scan.rb` and `lib/simple/scan/rb/version.rb`).
- Every upstream component file above already has a corresponding `lib/*.rb`
  file. The gaps that remain are off to the side of this file-level survey —
  desktop/appdata installation, 40 of 41 help-page language trees — plus
  whatever this inventory's sibling checks (`component-parity`,
  `translation-parity`, `test-parity`) find once they compare *inside* each
  mapped file: a file existing is not proof its widgets, CSS classes, signals
  and actions are all there.

## Update (this audit pass, 2026-11-07)

Re-verified against the current `ruby` HEAD and `origin/main`. Since the
table above was written, two items moved from "not yet mapped" to resolved:
the man page and the English help pages are now ported verbatim and
installed by `flake.nix`. Two items in the same row did not move: the
`.desktop` and AppStream files are present in `data/` but installed nowhere,
and only 1 of upstream's 41 help-page language trees (`C`) was ported. See
`.reports/component-parity.md` for the full current-state findings.

## Update (re-audit pass, 2026-11-08)

Re-counted: `find lib -name '*.rb' | wc -l` still returns 31 (29 mapped
upstream/widget components plus the 2 gem-boilerplate entrypoints counted
above — consistent with this round's runtime gate describing "29
components" covered by the drive script). The two commits since the last
`Parity reports` commit (`aa2cf654`, `447e9f6c`) touched only `flake.nix`,
`simple-scan-rb.gemspec` and `test/drive_app_window.rb` — no `lib/*.rb` file
was added, removed or renamed, so the file-mapping table itself is
unchanged. Confirmed live: `nix develop --command xvfb-run -a ruby
test/drive_app_window.rb` → 53 of 53 checks, DRIVE OK, in this pass.
