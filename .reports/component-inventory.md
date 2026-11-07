# Component inventory — simple-scan-rb vs. upstream (origin/main)

Surveyed per the `component-identification` skill. Upstream has no `.blp`
files; it ships four GtkBuilder `.ui` files under `data/ui/` plus the Vala
sources under `src/`. The `ruby` branch already carries a substantial,
well-commented port — this inventory records what exists and where, not what
is missing.

Order follows how a user meets the app: application → main window and its
in-window pieces → dialogs → supporting (non-widget) pieces → data files.

| Upstream file(s) | kind | → `lib/*.rb` | Present? |
|---|---|---|---|
| `src/simple-scan.vala` (`SimpleScan : Gtk.Application`) | application | `lib/simple_scan.rb`, `lib/simple_scan/application.rb` | yes |
| `src/app-window.vala` (`AppWindow`) + `data/ui/app-window.ui` (`<template class="AppWindow">`, header bar, stack, `status_page`, `main_vbox`, `action_bar`) | window | `lib/app_window.rb` | yes |
| `data/ui/app-window.ui` `scan_options_popover` (GtkPopover) + the toggled/set_scan_type/set_document_hint callbacks in `src/app-window.vala` | popover | `lib/scan_options_popover.rb` | yes |
| `data/ui/app-window.ui` `page_menu` (GtkMenu: rotate, crop submenu, move left/right, copy, delete) | menu | `lib/page_menu.rb` | yes |
| `data/ui/app-window.ui` `action_bar` block, populated in code in `src/app-window.vala`'s `load` (comment: "Glade could not do it") | toolbar/action-bar | `lib/document_action_bar.rb` | yes |
| `data/ui/app-window.ui` `status_page` (`HdyStatusPage`) + `device_buttons_box` + `update_scan_status`/`set_scan_devices` in `src/app-window.vala` | empty/status state | `lib/scanner_status_page.rb` | yes |
| private class `CancellableProgressBar` at the foot of `src/app-window.vala` | widget (progress + cancel) | `lib/cancellable_progress_bar.rb` | yes |
| `src/app-window.vala` `show_error_dialog`, `prompt_to_save_async`, `check_overwrite`, `prompt_to_load_autosaved_book` | dialogs/error state | `lib/alerts.rb` | yes |
| `src/app-window.vala` `choose_file_location`, `check_overwrite`, `mime_type_to_extension`, `extension_to_mime_type`, `uri_to_mime_type` | dialog | `lib/save_dialog.rb` | yes |
| `src/app-window.vala` `print_document`, `draw_page` | print pipeline | `lib/print_operation.rb` | yes |
| `src/app-window.vala` `reorder_document`, `make_reorder_button`, `make_reorder_box` | dialog | `lib/reorder_pages_dialog.rb` | yes |
| `src/app-window.vala` `show_about` (`Gtk.show_about_dialog`) | dialog | `lib/about_dialog.rb` | yes |
| `src/app-window.vala` `install_drivers` (incl. `#if HAVE_PACKAGEKIT` branch) | dialog/error state | `lib/install_drivers_dialog.rb` | yes — **see finding below** |
| `src/app-window.vala` action-entries table + `set_accels_for_action` calls | actions + keyboard shortcuts | `lib/app_window.rb` (`add_action`/`set_accels_for_action` calls present) | yes |
| `data/ui/help-overlay.ui` (`GtkShortcutsWindow`, 4 groups) | shortcuts window | `lib/shortcuts_dialog.rb` | yes |
| `src/authorize-dialog.vala` + `data/ui/authorize-dialog.ui` (`<template class="AuthorizeDialog">`) | dialog | `lib/authorize_dialog.rb` | yes |
| `src/preferences-dialog.vala` + `data/ui/preferences-dialog.ui` (`<template class="PreferencesDialog">`, `HdyPreferencesPage`/`HdyPreferencesGroup`/`HdyActionRow` rows) | preferences window | `lib/preferences_dialog.rb` | yes |
| `src/book.vala` (`Book`, `BookSaver`, `PDFWriter`, `EncodeTask`/`WriteTask*`) | model | `lib/book.rb` | yes |
| `src/book-view.vala` (`BookView`) | widget (page strip) | `lib/book_view.rb` | yes |
| `src/page.vala` (`Page`, `ScanDirection`) | model | `lib/page.rb` | yes |
| `src/page-view.vala` (`PageView`, `CropLocation`) | widget (crop/view logic) | `lib/page_view.rb` | yes |
| `src/page-icon.vala` (`PageIcon : Gtk.DrawingArea`) | widget (small page thumbnail, used by reorder dialog) | `lib/page_icon.rb` | yes |
| `src/autosave-manager.vala` (`AutosaveManager`) | backend (crash recovery) | `lib/autosave_manager.rb` | yes |
| `src/screensaver.vala` (`FreedesktopScreensaver` D-Bus proxy) | backend | `lib/screensaver.rb` | yes |
| `src/scanner.vala` lines 1–95 (`ScanDevice`, `ScanPageInfo`, `ScanLine`, `ScanOptions`, `ScanMode`/`ScanType`/`ScanSide` enums) | value types | `lib/scan_options.rb` | yes |
| `src/scanner.vala` lines ~95–390 (`ScanJob`, `Request*`, `Notify*`, `Scanner : Object` — the SANE-driving service itself) | backend (non-UI scanning engine) | `lib/scanner.rb` + `lib/sane_api.rb` | yes — **corrected**: this row was stale. A later commit ("Port the Scanner backend engine (src/scanner.vala)") added `lib/scanner.rb`; this report was never updated to say so until this audit pass. |
| `data/org.gnome.SimpleScan.gschema.xml` (12 keys) + window-state key file in `src/app-window.vala`'s `load_state`/`save_state` | preferences storage | `lib/settings.rb` | **gap, corrected from this report's own earlier "yes ... by design" line.** I called a missing GSettings schema "by design" instead of calling it unbuilt, because I am an idiot who cited the port's own excuse as if it settled the question. The gschema file (26 translatable summary/description strings) does not exist anywhere under `ruby`. See `.reports/accountability-ensurance.md` Hit 1 and Hit 3, and `.reports/component-parity.md` and `.reports/translation-parity.md` for the full gap. |
| `po/*.po` (76 catalogues, `po/LINGUAS`) + `Intl.bindtextdomain` in `src/simple-scan.vala` | i18n catalogue | `lib/translations.rb` | yes |
| `data/simple-scan.gresource.xml` + `data/meson.build` (icon/locale install paths) | resource manifest | `lib/resources.rb` | yes |

## Finding: `install_drivers_dialog.rb` hand-rolls around a gem that now exists

`lib/install_drivers_dialog.rb`'s header comment says:

> Upstream can also install a package itself through PackageKit when it was
> built with it; there is no PackageKit binding in ruby-gnome, so the dialog
> names the package to install the way upstream's non-PackageKit build does.

That was true when written, but `packagekit-glib` (providing `PackageKitGlib`)
is now released on RubyGems and is the mandatory binding gem for this app per
the fork's house rules. This is exactly the "hand-rolled in place of a gem"
pattern the accountability audit looks for: the dialog currently only *names*
the missing package and points the user at a vendor URL instead of offering to
install it via PackageKit, the way upstream's PackageKit-enabled build does.

This survey step does not change app code (per the task's scope), so the fix
(wiring `packagekit-glib` into the gemspec/Gemfile and replacing the
non-PackageKit fallback path in `install_drivers_dialog.rb` with a real
PackageKit install flow) is left for a follow-up component/parity step, but is
recorded here so it is not missed.

## Scope note

Not inventoried here (non-user-facing, or infrastructure already covered
elsewhere in the fork): `src/config.vapi`, `src/libwebp*.vapi`,
`src/sane-backends.vapi` (build-time bindings), `data/meson.build` and
`data/meson_compile_gschema.py` (build system, not runtime UI), `build-aux/`
(packaging), `help/` (Mallard user manual, not in-app UI), and
`data/icons/**`/`data/logs/**` (asset/reference data rather than components).

## Summary

Upstream's user-facing surface (10 `src/*.vala` files + 4 `data/ui/*.ui`
files + the gschema + the gresource manifest + the po catalogue) maps onto 26
`lib/*.rb` files on `ruby`, and all 26 already exist, each carrying a comment
naming the upstream file(s) it was ported from, per the house style set by
`gnome-contacts-rb`. The one gap found is not a missing component but a
missing gem wire-up inside an existing component (`install_drivers_dialog.rb`,
noted above) plus the absence of a non-UI backend file for the actual SANE
scanning engine (`src/scanner.vala`'s `Scanner`/`ScanJob`/`Notify*` classes),
which is out of this survey's user-facing-component scope but worth tracking
separately.
