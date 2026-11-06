# Component inventory — simple-scan-rb

Survey of upstream `origin/main` (GTK3 + libhandy Vala app) against the
`ruby` branch's `lib/` (GTK4 + Libadwaita port). Produced with the
`component-identification` skill, scoped as the opening survey of a fresh
fork: this is a map of what exists and what is missing, file by file, not a
widget-by-widget inventory of each file (that is the job of
`component-parity` on one unit at a time).

Upstream has no `.blp` files; it has four `.ui` files
(`data/ui/app-window.ui`, `authorize-dialog.ui`, `preferences-dialog.ui`,
`help-overlay.ui`) plus a large amount of UI built directly in
`src/app-window.vala` (dialogs, popovers, menus, the progress bar) rather
than declared in `.ui`. The Ruby house style never uses `.ui` files, so every
row below is file → file, with the upstream `.ui` noted where one backs the
Vala class.

## Windows

| Upstream | → lib path | Kind | Exists? |
|---|---|---|---|
| `src/app-window.vala` (2159 lines) + `data/ui/app-window.ui` | `lib/app_window.rb` | window | **Yes** (905 lines) |
| `src/app-window.vala`, nested `private class CancellableProgressBar : Gtk.HBox` | `lib/cancellable_progress_bar.rb` | widget (toolbar progress) | **Yes** (72 lines) |

## Dialogs

| Upstream | → lib path | Kind | Exists? |
|---|---|---|---|
| `src/authorize-dialog.vala` + `data/ui/authorize-dialog.ui` | `lib/authorize_dialog.rb` | dialog (driver auth prompt) | **Yes** |
| `src/preferences-dialog.vala` + `data/ui/preferences-dialog.ui` | `lib/preferences_dialog.rb` | dialog | **Yes** (306 lines) |
| `data/ui/help-overlay.ui` (`GtkShortcutsWindow`, 4 groups) | `lib/shortcuts_dialog.rb` | dialog (shortcuts) | **Yes** (70 lines, `Adwaita::ShortcutsDialog`) |
| `app-window.vala#show_about` / `about_cb` (built in code, no `.ui`) | `lib/about_dialog.rb` | dialog | **Yes** (54 lines) |
| `app-window.vala#reorder_document` / `reorder_document_cb` | `lib/reorder_pages_dialog.rb` | dialog | **Yes** (174 lines) |
| `app-window.vala#install_drivers` (`Gtk.Dialog.with_buttons`) | `lib/install_drivers_dialog.rb` | dialog | **Yes** (173 lines) |
| `app-window.vala` save flow (`Gtk.FileChooserNative`, `check_overwrite`) | `lib/save_dialog.rb` | dialog | **Yes** (323 lines) |
| `app-window.vala` `Gtk.MessageDialog` call sites: driver-auth prompt (l.224), autosave-recovery prompt (l.383), overwrite confirmation (l.645), scan-replace confirmation (l.751) | `lib/alerts.rb` | dialog (message alerts) | **Yes** (94 lines) — confirm all four sites are covered when doing parity, not just existence |

## Pages / document model

| Upstream | → lib path | Kind | Exists? |
|---|---|---|---|
| `src/book.vala` (948 lines) | `lib/book.rb` | model | **Yes** |
| `src/book-view.vala` (619 lines) | `lib/book_view.rb` | view | **Yes** |
| `src/page.vala` (678 lines) | `lib/page.rb` | model | **Yes** |
| `src/page-view.vala` (1066 lines) | `lib/page_view.rb` | view | **Yes** |
| `src/page-icon.vala` (76 lines) | `lib/page_icon.rb` | widget (thumbnail) | **Yes** |

## Menus / popovers / toolbars

| Upstream | → lib path | Kind | Exists? |
|---|---|---|---|
| `app-window.vala` crop/page `Gtk.CheckMenuItem` sites (`update_page_menu`, `set_crop`, the `*_menuitem_toggled_cb` family) | `lib/page_menu.rb` | menu | **Yes** (128 lines) — note: these are `Gtk.CheckMenuItem` in GTK3; GTK4 has no menu-item widgets, so this file is necessarily a from-scratch popover/menu-model rewrite, not a line-for-line port |
| `app-window.vala` scan-type/crop popover UI (feeds `set_scan_type`, `set_crop`) | `lib/scan_options_popover.rb` | popover | **Yes** (182 lines) |
| `app-window.vala` `action_bar` construction (`action_bar.pack_start/pack_end`, rotate/move/delete buttons, `menu_button`) | `lib/document_action_bar.rb` | toolbar | **Yes** (117 lines) |
| `app-window.vala` `update_scan_status`, scanning-state label/spinner | `lib/scanner_status_page.rb` | page (status/empty state) | **Yes** (256 lines) |

## Scanning backend

| Upstream | → lib path | Kind | Exists? |
|---|---|---|---|
| `src/scanner.vala` (1802 lines): `Scanner` (SANE device worker thread), `ScanDevice`, `ScanPageInfo`, `ScanLine`, `ScanJob`, `Credentials`, `ScanState`, the `Notify*`/`Request*` message classes | `lib/scanner.rb` | **model/service** | **No — missing.** `app_window.rb` and `scan_options.rb` only mention `Scanner` in comments; nothing in `lib/` instantiates or wraps it. This is the single largest gap: the device-redetect flow, authorization flow, and the actual scan/notify pipeline that every other widget reacts to have no Ruby counterpart yet. |
| `src/scanner.vala` `public enum ScanType`, `ScanSide`; `public class ScanOptions` | `lib/scan_options.rb` | enum/value object | **Yes** (127 lines) — ported ahead of its owning class |
| `app-window.vala#draw_page` / `print_document` (`Gtk.PrintOperation`) | `lib/print_operation.rb` | service | **Yes** (65 lines) |

## Application / lifecycle

| Upstream | → lib path | Kind | Exists? |
|---|---|---|---|
| `src/simple-scan.vala` (`public class SimpleScan : Gtk.Application`, `main()`) | `lib/simple_scan/application.rb` + `lib/simple_scan.rb` | application | **Yes** |
| `src/autosave-manager.vala` (367 lines) | `lib/autosave_manager.rb` | service | **Yes** |
| `src/screensaver.vala` (25 lines) | `lib/screensaver.rb` | service | **Yes** |
| `app-window.vala#load_state/save_state/state_get_boolean` + `data/org.gnome.SimpleScan.gschema.xml` (13 keys: `selected-device`, `document-type`, `paper-width`, `paper-height`, `brightness`, `contrast`, `text-dpi`, `photo-dpi`, `page-side`, `save-directory`, `save-format`, `jpeg-quality`, `page-delay`) | `lib/settings.rb` | settings | **Yes** (268 lines) — confirm all 13 keys are wired during parity, not just the file's existence |
| `data/simple-scan.gresource.xml` (icon bundle: `org.gnome.SimpleScan.svg`, symbolic icon, `crop-symbolic`, `scan-type-adf-symbolic`, `scan-type-batch-symbolic`) | `lib/resources.rb` | resources | **Yes** (87 lines) |
| `po/*.po` (76 locale catalogues) + upstream's own i18n helper usage (`_()`, `p_()`) | `lib/translations.rb` | i18n | **Yes** (36 lines) — this is Ruby's own `_`/`p_` shim, not a port of any single `.po` file. The `po/` catalogues themselves are translation *content*; see the `translation-parity` skill for whether/how they get carried over rather than this inventory. |

## Not components (no lib mapping)

- `src/config.vapi`, `src/libwebp.vapi`, `src/libwebpmux.vapi`, `src/sane-backends.vapi`, `src/meson.build` — build glue / FFI bindings, not UI.
- `data/meson.build`, `data/meson_compile_gschema.py`, `data/simple-scan.desktop.in`, `data/simple-scan.appdata.xml.in`, `data/simple-scan.1` — packaging/metadata, not widgets.
- `help/**` — Mallard user documentation, not app UI.
- `build-aux/**` — Flatpak/Snap packaging.

## Summary

- 20 of 21 upstream component files/sites already have a `lib/*.rb` counterpart on `ruby`.
- **The one missing component is `lib/scanner.rb`** (from `src/scanner.vala`), the SANE-backed scanning engine itself — the thing every dialog, popover, and status page in the rest of the app ultimately drives. Until it exists, `app_window.rb`'s scan/redetect/authorize call sites have nothing real to call.
- Existence here is file-level only (per the `component-identification` skill's per-file scan unit). None of the existing files have been checked widget-by-widget against upstream in this pass — that per-unit CSS/signal/action comparison is the next step, via `component-parity`, one unit at a time, starting with `app_window.rb` (the largest and most central file) or `scanner.rb` (the only wholly absent one).
