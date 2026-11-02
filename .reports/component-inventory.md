# simple-scan — upstream component inventory

Survey of `origin/main` (GNOME Simple Scan, Vala + GTK3 + libhandy) against the
`ruby` branch's `lib/` (Ruby + GTK4 + Libadwaita). Produced with the
`component-identification` skill. No app code was written in this step.

## Shape of the upstream

- 13 Vala files in `src/` (~10 500 lines), 4 GtkBuilder files in `data/ui/`.
- Upstream is **GTK3 + libhandy**: `Hdy.ApplicationWindow`, `Hdy.HeaderBar`,
  `Hdy.StatusPage`, `Hdy.PreferencesWindow`, `Hdy.ActionRow`, plus GTK3-only
  widgets (`GtkMenu`/`GtkMenuItem`/`GtkRadioMenuItem`, `GtkComboBox` +
  `GtkListStore` + `GtkCellRendererText`, `GtkRadioButton`, `GtkButtonBox`,
  `GtkFileChooserNative`, `Gtk.Dialog.run ()`, `delete-event`, draw/event
  signals on `GtkDrawingArea`).
  **Every one of those has a different GTK4/Adwaita spelling.** The port is a
  translation of the component, not of the widget type:

  | Upstream (GTK3/Hdy) | Port (GTK4/Adwaita) |
  |---|---|
  | `Hdy.ApplicationWindow` + `Hdy.HeaderBar` | `Adwaita::ApplicationWindow` + `Adwaita::ToolbarView` + `Adwaita::HeaderBar` |
  | `Hdy.StatusPage` | `Adwaita::StatusPage` |
  | `Hdy.PreferencesWindow` / `Page` / `Group` / `ActionRow` | `Adwaita::PreferencesWindow` / `PreferencesPage` / `PreferencesGroup` / `ActionRow` |
  | `GtkMenu` + `GtkMenuItem` + `GtkRadioMenuItem` | `Gio::Menu` model + `Gtk::PopoverMenu` + stateful `Gio::SimpleAction` |
  | `GtkComboBox` + `GtkListStore` | `Adwaita::ComboRow` / `Gtk::DropDown` + `Gtk::StringList` |
  | `GtkRadioButton` with `draw_indicator=False`, `.linked` | `Gtk::ToggleButton` group in a `.linked` box |
  | `Gtk.MessageDialog` / `Gtk.Dialog.run ()` | `Adwaita::AlertDialog` / `Adwaita::Dialog` with response callbacks |
  | `GtkFileChooserNative` | `Gtk::FileDialog` |
  | `GtkShortcutsWindow` (help-overlay.ui) | hand-built `Adwaita::Dialog` (no `Gtk::ShortcutsWindow` in GTK4.14+ / bindings) |
  | `delete-event` returning true | `close-request` |
  | `GtkDrawingArea` `draw`/`button-press-event`/`motion-notify-event` | `set_draw_func` + `Gtk::GestureClick` / `Gtk::EventControllerMotion` / `Gtk::EventControllerKey` |
  | `Gtk.show_about_dialog` | `Adwaita::AboutDialog` (or `AboutWindow`) |
  | `Gtk.ActionBar` populated in code | `Gtk::ActionBar` as the toolbar view's bottom bar |

- Translations: `po/` has 76 locales; `po/POTFILES.in` lists 7 source files and
  4 `.ui` files plus the gschema, desktop and appdata — the user-visible string
  set lives in `app-window.vala`, `scanner.vala`, `simple-scan.vala`,
  `book.vala`, `page.vala`, `preferences-dialog.vala` and the four `.ui` files.
- GResource (`data/simple-scan.gresource.xml`): the 4 `.ui` files plus three
  bundled symbolic icons — `scan-type-adf-symbolic`, `scan-type-batch-symbolic`,
  `crop-symbolic`. These are app-provided icons, not stock; the port must ship
  them (`data/icons/scalable/actions/*.svg`) or the scan-type popover and the
  crop button render blank.
- GSettings (`data/org.gnome.SimpleScan.gschema.xml`), schema
  `org.gnome.SimpleScan`, 13 keys: `selected-device`, `document-type`
  (`text`|`photo`), `paper-width`, `paper-height`, `brightness`, `contrast`,
  `text-dpi`, `photo-dpi`, `page-side` (enum `front`|`back`|`both`),
  `save-directory`, `save-format`, `jpeg-quality` (0–100), `page-delay`
  (0–15000 ms). Plus a **non-GSettings** state file at
  `$XDG_CACHE_HOME/simple-scan/state` (KeyFile: window width/height,
  is-maximized, is-fullscreen, scanner/scan-type).

## What `ruby` has today

```
lib/simple_scan.rb                 3 lines   requires application
lib/simple_scan/application.rb    54 lines   placeholder window + StatusPage
lib/simple/scan/rb/version.rb     15 lines   gem version
```

One component exists, and only as a stub: an `Adwaita::ApplicationWindow` with
a `ToolbarView`, an empty `HeaderBar` and a `StatusPage` reading "The Ruby port
has not been written yet." **No upstream component is ported.**

Note the pilot port (`gnome-contacts-rb`) keeps widget classes flat in
`lib/*.rb` with only `lib/<app>/application.rb` namespaced; the targets below
follow that.

---

## Components, in the order a user meets them

### 1. `src/simple-scan.vala` → `lib/application.rb` — the application object

Exists as `lib/simple_scan/application.rb` (stub only).

| Component | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Gtk.Application` (`org.gnome.SimpleScan`) | 1 | — | `startup`, `activate`, `command-line`, `shutdown` | `register_session = true`; `Adwaita::Application` is broken in the bindings — use `Gtk::Application` |
| command-line options | 3 | — | — | `--version`/`-v`, `--debug`/`-d`, `--fix-pdf FILENAME…` |
| session inhibit | 1 | — | — | `inhibit (app, IDLE, reason)` while scanning |

Owns: device detection via GUsb, the `Scanner` instance, the `Book`, the
`AppWindow`, log file setup. Not a widget, but a unit.

### 2. `src/app-window.vala` + `data/ui/app-window.ui` → `lib/app_window.rb` — the main window

2159 lines of Vala + 766 lines of GtkBuilder. The single largest unit; the
sub-components below (3–13) are carved out of it so no one file is unreviewable.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Hdy.ApplicationWindow` (`template AppWindow`) | 1 | — | `delete-event` → `window_delete_event_cb` | → `close-request`; restores size/maximized/fullscreen from the state file |
| `Hdy.HeaderBar` `header_bar` | 1 | `titlebar` | — | title set in code (`Document Scanner`) because Glade drops the translation |
| `Gtk.Box` `open_box` | 1 | `linked` | — | holds stop/scan/menu-button |
| `Gtk.Button` `stop_button` | 1 | `text-button`, `destructive-action` | `clicked` → `stop_scan_button_clicked_cb` | contains `Gtk.Spinner` `stop_button_spinner` + label "Stop Scan" |
| `Gtk.Button` `scan_button` | 1 | `text-button`, `suggested-action` | `clicked` → `scan_button_clicked_cb` | contains `Gtk.Image` `scan_options_image` (icon swaps per scan type) + label |
| `Gtk.MenuButton` (scan options) | 1 | — | — | popover = `scan_options_popover`; contains `Gtk.Image` `scan_hint_image` + a pan-down image |
| `Gtk.MenuButton` `menu_button` | 1 | `image-button` | — | gear menu, model built in code (see §4) |
| `Gtk.Button` `save_button` | 1 | `image-button` | `clicked` → `save_file_button_clicked_cb` | `Gtk.Image` `save_image`; `sensitive` toggled by `book_changed_cb` |
| `Gtk.Stack` `stack` | 1 | — | — | two children named `status` and `document` — the app's empty state vs. content |
| `Gtk.Box` `main_vbox` | 1 | — | — | the `document` page: `action_bar` packed end, `BookView` added with border 18, vexpand |

Repeaters: none at startup. Conditional: `stop_button` vs `scan_button`
visibility swap while scanning; `stack` page swap on first page added.

### 3. `data/ui/app-window.ui` (`GtkMenu page_menu`) → `lib/page_menu.rb` — page context menu

A GTK3 `GtkMenu` shown on right-click from `BookView`'s `show_menu` signal. In
GTK4 this becomes a `Gio::Menu` model on a `Gtk::PopoverMenu` with stateful
actions for the crop radio group.

| Item | × | Accel | Handler |
|---|---:|---|---|
| `Rotate _Left` | 1 | `bracketleft` | `rotate_left_button_clicked_cb` |
| `Rotate _Right` | 1 | `bracketright` | `rotate_right_button_clicked_cb` |
| `_Crop` submenu → `GtkRadioMenuItem` ×9 | 9 | — | `no_crop`, `a4`, `a5`, `a6`, `letter`, `legal`, `four_by_six`, `a3`, `custom_crop` — each `*_menuitem_toggled_cb` |
| `GtkSeparatorMenuItem` + `_Rotate Crop` | 1 | — | `crop_rotate_menuitem_activate_cb` |
| `Move Left` / `Move Right` | 2 | `less` / `greater` | `page_move_left_menuitem_activate_cb`, `page_move_right_menuitem_activate_cb` |
| `Copy to Clipboard` (`GtkImageMenuItem`) | 1 | `<Ctrl>C` | `copy_to_clipboard_button_clicked_cb`; `sensitive` set by `book_changed_cb` |
| `Delete Page` (`GtkImageMenuItem`) | 1 | `Delete` | `page_delete_menuitem_activate_cb` |

The crop radio state is **two-way bound** to the `crop_button` toggle in the
action bar (`updating_page_menu` guard) — port both directions or the toggle
desyncs.

### 4. `src/app-window.vala` (gear menu, built in code) → part of `lib/app_window.rb`

`Gio::Menu` with two sections — section 1: `_Email` → `app.email`, `Pri_nt` →
`app.print`, `_Reorder Pages` → `app.reorder`; section 2: `_Preferences` →
`app.preferences`, `_Keyboard Shortcuts` → `win.show-help-overlay`, `_Help` →
`app.help`, `_About Document Scanner` → `app.about`.

### 5. `data/ui/app-window.ui` (`GtkPopover scan_options_popover`) → `lib/scan_options_popover.rb`

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.Popover` | 1 | — | — | from the scan-type `MenuButton` |
| `Gtk.RadioButton` + `Box`/`Image`/`Label` | 3 | — | `toggled` → `scan_single_radio_toggled_cb`, `scan_adf_radio_toggled_cb`, `scan_batch_radio_toggled_cb` | Single Page / All Pages From Feeder / Multiple Pages From Flatbed; icons `document-new-symbolic`, `scan-type-adf-symbolic`, `scan-type-batch-symbolic` (bundled) |
| `Gtk.RadioButton` + `Box`/`Image`/`Label` | 2 | — | `toggled` → `text_radio_toggled_cb`, `photo_radio_toggled_cb` | Text / Image document hint, bound to the `document-type` setting |
| `Gtk.Button` `preferences_button` | 1 | — | `clicked` → `preferences_button_clicked_cb` | |

### 6. `data/ui/app-window.ui` (`HdyStatusPage status_page`) → `lib/scanner_status_page.rb` — the empty / no-device state

Four distinct states set from `set_scanning`/device callbacks — the port must
reproduce all four, not just one:

| State | Title | Secondary |
|---|---|---|
| detecting | `Searching for Scanners…` | — |
| ready | `Ready to Scan` | — |
| needs driver | `Additional Software Needed` | markup link `install driver software` → `status_label_activate_link_cb` → §11 |
| none | `No Scanners Detected` | `Please check your scanner is connected and powered on.` |

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Hdy.StatusPage` | 1 | — | — | icon + title |
| `Gtk.Label` `status_secondary_label` | 1 | `body`, `description` | `activate-link` → `status_label_activate_link_cb` | markup, link `install-firmware` |
| `Gtk.Box` `device_buttons_box` | 1 | — | — | shown only when devices exist |
| `Gtk.ComboBox` `device_combo` (+ `GtkListStore device_model`, `CellRendererText` added in code) | 1 | — | `changed` → `device_combo_changed_cb` | → `Gtk::DropDown`; bound to `selected-device` |
| `Gtk.Button` `refresh_devices` | 1 | `image-button` | `clicked` → `redetect_button_clicked_cb` | `view-refresh-symbolic` |

### 7. `src/app-window.vala` (ActionBar, built in code — Glade could not) → `lib/document_action_bar.rb`

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.ActionBar` `action_bar` | 1 | — | — | packed at the end of `main_vbox` |
| `Gtk.Button` `_New Document` | 1 | — | `clicked` → `new_document_cb` | pack_start, mnemonic |
| `Gtk.Box` (center widget, spacing 10) | 1 | — | — | |
| `Gtk.Box` rotate group | 1 | `linked` | — | |
| `Gtk.Button` rotate left / right | 2 | — | `clicked` → `rotate_left_button_clicked_cb` / `rotate_right_button_clicked_cb` | `object-rotate-left-symbolic` / `object-rotate-right-symbolic`, image margins 18, tooltips `Rotate the page to the left (counter-clockwise)` / `…right (clockwise)` |
| `Gtk.ToggleButton` `crop_button` | 1 | — | `toggled` (inline lambda → drives `custom_crop_menuitem`/`no_crop_menuitem`) | `crop-symbolic` (bundled), tooltip `Crop the selected page` |
| `Gtk.Button` `delete_button` | 1 | — | `clicked` (inline → `book.delete_page (selected_page)`) | `user-trash-symbolic`, tooltip `Delete the selected page` |

These are **built in a code block, not in the `.ui`** — a scan of the `.ui`
alone finds only the empty `GtkActionBar` and reads as 6 fewer components.

### 8. `src/app-window.vala` (`save_document`, lines ~461–660) → `lib/save_dialog.rb`

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.FileChooserNative` `Save As…` | 1 | — | — | → `Gtk::FileDialog`; default name `Scanned Document.<ext>`, start dir from `save-directory` |
| `Gtk.FileFilter` | 2 | — | — | `Image Files`, `All Files` |
| `Gtk.ComboBox` + `Gtk.ListStore` + `CellRendererText` (format) | 1 | — | `changed` | `PDF (multi-page document)`, `JPEG (compressed)`, `PNG (lossless)`, `WebP (compressed)` (WebP only `#if HAVE_WEBP`) |
| `Gtk.Label` `File format:` | 1 | — | — | |
| `Gtk.Scale` + `Gtk.Adjustment` (75, 0..100) | 1 | — | `value-changed` | `Compression:`, shown for lossy formats only; `jpeg-quality` setting |
| `Gtk.Label` `Minimum size` / `Full detail` | 2 | — | — | `<small>` markup scale end-labels |
| `Gtk.MessageDialog` replace-confirm | 1 | — | — | `A file named “%s” already exists.  Do you want to replace it?` + `_Cancel` / `_Replace` (destructive) |

Conditional: the compression scale and its two end-labels appear only for JPEG
and WebP; the WebP row only in a WebP-enabled build.

### 9. `src/app-window.vala` (`reorder_document`, lines ~1271–1400) → `lib/reorder_pages_dialog.rb`

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.Window` (title `Reorder Pages`, ctx `dialog title`) | 1 | — | — | → `Adwaita::Dialog` |
| `Gtk.Grid` | 1 | — | — | 2×2 of option buttons |
| `Gtk.Button` (from `make_reorder_button`) | 4 | — | `clicked` | `Combine sides`, `Combine sides (reverse)`, `Reverse`, `Keep unchanged` — each carries an order spec string |
| `Gtk.Box` + `Gtk.Label` + `PageIcon` (from `make_reorder_box`) | 4 | — | — | the little before/after page diagram, with a `➤` label between halves |

`make_reorder_button`/`make_reorder_box` are a **shared factory called four
times** — four components, one textual occurrence.

### 10. `src/app-window.vala` (`show_about`, line ~1565) → `lib/about_dialog.rb`

`Gtk.show_about_dialog` → `Adwaita::AboutDialog`. Fields: program-name
`Document Scanner`, title `About Document Scanner`, comments `Simple document
scanning tool`, full GPL-3 licence text, authors, `translator-credits`,
website, logo-icon-name `org.gnome.SimpleScan`.

### 11. `src/app-window.vala` (`install_drivers`, lines ~1633–1770) → `lib/install_drivers_dialog.rb`

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.Dialog.with_buttons` `Install drivers` + `_Close` | 1 | — | `response` | modal |
| `Gtk.Label` (vendor message) | 1 | — | — | 6 vendor branches: Brother, Canon, Samsung, HP, Epson, Lexmark — each a different message **and** a different instructions string with hyperlinks |
| `Gtk.Box` instructions box | 1 | — | — | |
| `Gtk.Stack` | 1 | — | — | swaps instructions ↔ progress ↔ result |
| `Gtk.Spinner` | 1 | — | — | while installing |
| `Gtk.Label` status / instructions / footer | 3 | — | `activate-link` | footer: `Once installed you will need to restart this app.`; progress `Installing drivers…`; results `Drivers installed successfully!`, `Failed to install drivers (error code %d).`, `Failed to install drivers.` |

Conditional on `#if HAVE_PACKAGEKIT` for the actual install; the dialog and its
vendor text exist regardless. Six vendor branches = six user-visible states.

### 12. `src/app-window.vala` (`show_error_dialog` + the alert prompts) → `lib/alerts.rb`

All `Gtk.MessageDialog` in upstream; all `Adwaita::AlertDialog` in the port.

| Alert | Buttons | Trigger |
|---|---|---|
| generic error (`show_error_dialog`) | `_Close` | `Failed to save file`, `Unable to save image for preview`, `Unable to open image preview application`, `Unable to open help file` |
| autosave prompt | yes/no | `An autosaved book exists. Do you want to open it?` |
| save before new document | `_Cancel`, `_Save`, `_Discard Changes` | `Save current document?` + `If you don’t save, changes will be permanently lost.` |
| save before quit | `_Cancel`, `_Save`, `_Quit without Saving` | `Save document before quitting?` |
| contacting scanner | — | `Contacting Scanner…` progress text |

### 13. `src/app-window.vala` (`CancellableProgressBar`, lines ~2114–2159) → `lib/cancellable_progress_bar.rb`

A private class in the same file. `Gtk.HBox` (→ `Gtk::Box`) with a
`Gtk.ProgressBar` (show_text) and an optional `Gtk.Button` `Cancel` that
cancels and hides; `destroy_with_delay` desensitises then destroys on a
timeout. Used for `Saving` and for the driver install progress.

### 14. `src/app-window.vala` (`print_document`/`draw_page`, ~1457–1540) → `lib/print_operation.rb`

`Gtk.PrintOperation` run with `PRINT_DIALOG` (the platform print dialog is the
component), `draw-page` rendering each page via Cairo at printer resolution.

### 15. `src/preferences-dialog.vala` + `data/ui/preferences-dialog.ui` → `lib/preferences_dialog.rb`

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Hdy.PreferencesWindow` (`template PreferencesDialog`) | 1 | — | `delete-event` → hide, not destroy | `search_enabled=False`; modal, transient for the window |
| `Hdy.PreferencesPage` | 1 | — | — | |
| `Hdy.PreferencesGroup` | 2 | — | — | `Scanning`, `Quality` |
| `Hdy.ActionRow` | 7 | — | — | `Scan _Sides`, `_Page Size`, `_Delay in Seconds` (+ subtitle `Interval to scan multiple pages`), `_Text Resolution`, `_Image Resolution`, `_Brightness`, `_Contrast` — each with `activatable_widget` |
| `Gtk.Box` `scan_side_box` | 1 | `linked` | — | homogeneous |
| `Gtk.RadioButton` (`draw_indicator=False`) sides | 3 | — | `toggled` | `Front`, `Back`, `Both` → `page-side` enum |
| `Gtk.Box` page-delay | 1 | `linked` | — | homogeneous |
| `Gtk.RadioButton` (`draw_indicator=False`) delay | 5 | — | `toggled` | `0`, `3`, `6`, `10`, `15` → `page-delay` ms |
| `Gtk.ComboBox` `paper_size_combo` (+ `GtkListStore paper_size_model`) | 1 | — | `changed` | → `Adwaita::ComboRow`; `paper-width`/`paper-height` |
| `Gtk.ComboBox` `text_dpi_combo` / `photo_dpi_combo` (+ 2 `GtkListStore`) | 2 | — | `changed` | `text-dpi`, `photo-dpi` |
| `Gtk.Scale` `brightness_scale` / `contrast_scale` (+ 2 `GtkAdjustment` −100..100) | 2 | — | `value-changed` | `draw_value=False`; `brightness`, `contrast` |
| `Gtk.SizeGroup` `scale_size_group` | 1 | — | — | horizontal, over the two scales |

The `GtkAdjustment`s, `GtkListStore`s and `GtkSizeGroup` are `type`, not
`widget` — they are behaviour the port still has to reproduce (as
`Gtk::Adjustment`, `Gtk::StringList`, `Gtk::SizeGroup`).

### 16. `src/authorize-dialog.vala` + `data/ui/authorize-dialog.ui` → `lib/authorize_dialog.rb`

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.Dialog` (`template AuthorizeDialog`) | 1 | — | `response` (action-widget 0) | modal, non-resizable, urgency hint; run synchronously by `AppWindow.authorize` |
| `Gtk.Button` `authorize_button` | 1 | — | — | `_Authorize` |
| `Gtk.Label` `authorize_label` | 1 | — | — | set dynamically: `Username and password required to access “%s”` |
| `Gtk.Grid` | 1 | — | — | 2×2 |
| `Gtk.Entry` `username_entry` | 1 | — | — | |
| `Gtk.Entry` `password_entry` | 1 | — | — | `visibility=False`, invisible char `●` |
| `Gtk.Label` `_Username for resource:` / `_Password:` | 2 | — | — | mnemonic_widget bound to the entries |

Upstream calls `dialog.run ()` — blocking. GTK4 has no `run`; the port needs an
async/callback form of the same interaction.

### 17. `data/ui/help-overlay.ui` → `lib/shortcuts_dialog.rb` — keyboard shortcuts window

A standalone `.ui` with **no backing source file** — a unit of its own, reached
by `win.show-help-overlay` (`<Ctrl>?`). `GtkShortcutsWindow` with 1
`GtkShortcutsSection`, 4 `GtkShortcutsGroup`s, 18 `GtkShortcutsShortcut`s:

| Group | Shortcuts |
|---|---|
| Scanning | `<ctrl>1` Scan a single page · `<ctrl>f` Scan all pages from document feeder · `<ctrl>m` Scan continuously from a flatbed scanner · `Escape` Stop scan in progress |
| Document Modification | `less` Move page left · `greater` Move page right · `bracketleft` Rotate page to the left (anti-clockwise) · `bracketright` Rotate page to the right (clockwise) · `Delete` Delete page |
| Document Management | `<ctrl>n` Start new document · `<ctrl>s` Save scanned document · `<ctrl>e` Email scanned document · `<ctrl>p` Print scanned document · `<ctrl>c` Copy current page to clipboard |
| General | `F1` Show help · `F10` Open menu · `<ctrl>question` Keyboard shortcuts · `<ctrl>q` Quit |

All strings carry the `shortcut window` msgctxt.

### 18. `src/book-view.vala` → `lib/book_view.rb` — the page strip / canvas

`BookView : Gtk.Box` (vertical), 619 lines. Custom-drawn, so nothing is in a
`.ui` and a type scan finds almost nothing.

| Widget / controller | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.Box` (BookView root) | 1 | — | emits `page_selected (Page?)`, `show_page (Page)`, `show_menu (Gdk.Event)` | upstream sets `border_width = 18` from the caller |
| `Gtk.DrawingArea` | 1 | — | `draw` → `draw_cb`, `configure-event` → `configure_cb`, `button-press/release-event` → `button_cb`, `motion-notify-event` → `motion_cb`, `key-press-event` → `key_cb`, `focus-in/out-event` → `focus_cb` | GTK4: `set_draw_func` + `GestureClick` + `EventControllerMotion` + `EventControllerKey` + `EventControllerFocus` |
| `Gtk.Scrollbar` + `Gtk.Adjustment` | 1 | — | `value-changed` → `scroll_cb` | horizontal |

Repeater: one `PageView` per page in the book, laid out by hand; page rulers
drawn with the theme's `theme_fg_color` looked up from the style context, and
focus drawn with `render_focus`.

### 19. `src/page-view.vala` → `lib/page_view.rb` — one page inside the strip

`PageView : Object` (not a widget — it draws into `BookView`'s canvas), 1066
lines. Signals `size_changed`, `changed`. Owns the crop handles and the
hit-testing for the 8 crop grips plus the move region, the scan-progress
overlay and the page border. It is a component even though it is not a
`Gtk.Widget`; dropping it loses all direct manipulation.

### 20. `src/page-icon.vala` → `lib/page_icon.rb`

`PageIcon : Gtk.DrawingArea` — a tiny page glyph with a text label and an r/g/b
tint, minimum width 20, custom `get_preferred_width`/`height` and `draw`. Used
only by the reorder dialog (§9), 4 instances per dialog.

### 21. `src/book.vala` → `lib/book.rb` — the document model

948 lines. `Book` with `page_added`, `page_removed`, `reordered`, `changed`
signals (the four that drive `update_page_menu`), page list, `delete_page`,
`move_page`, `clear`, and the save pipeline for PDF / JPEG / PNG / WebP. Not a
widget, but it is in `POTFILES.in` — it carries user-visible strings.

### 22. `src/page.vala` → `lib/page.rb` — one scanned page

678 lines. Pixel data, dpi, scan direction, crop rectangle, rotation,
`pixels_changed`/`size_changed`/`scan_line_changed`/`crop_changed` signals. In
`POTFILES.in`.

### 23. `src/scanner.vala` → `lib/scanner.rb` — SANE driver thread

1802 lines. Device enumeration, `ScanDevice`, `ScanOptions`, `ScanType`
(`single`/`adf`/`batch` with `type_from_string`/`type_to_string` used by the
state file), authorisation callback (→ §16), progress and error signals that
drive the status page and the error alerts. In `POTFILES.in`. There is **no SANE
binding in ruby-gnome** — this unit needs a decision (FFI to libsane, or
shelling out to `scanimage`); record it as a blocker, not as a widget gap.

### 24. `src/autosave-manager.vala` → `lib/autosave_manager.rb`

367 lines. Writes the in-progress book to the cache dir and restores it on
start; drives the autosave prompt in §12.

### 25. `src/screensaver.vala` → `lib/screensaver.rb`

25 lines. `org.freedesktop.ScreenSaver` D-Bus proxy, `Inhibit`/`UnInhibit`.
Straightforward with `Gio::DBusProxy`.

### 26. `data/org.gnome.SimpleScan.gschema.xml` → `lib/settings.rb`

The 13 keys above, plus the KeyFile state file (window geometry + scan type)
which is *not* GSettings and needs its own reader/writer. The gschema also has
to be compiled and installed for `Gio::Settings` to find it at runtime — in a
gem-shaped port that means either shipping and compiling the schema or backing
`Settings` with a plain config file.

### 27. `po/` (76 locales), `data/simple-scan.desktop.in`, `data/simple-scan.appdata.xml.in`

Not a widget. The port needs a gettext setup and the `.po` catalogue carried
over for translation parity, and the desktop/appdata files for the app to show
up in a shell. `po/POTFILES.in` is the authoritative list of string-bearing
files; the `help/C/*.page` user manual (17 pages, 30 translations) is a separate
parity question.

---

## Summary table

| # | Upstream | Port target | Kind | Exists |
|---|---|---|---|---|
| 1 | `src/simple-scan.vala` | `lib/application.rb` (today `lib/simple_scan/application.rb`) | application | partial — stub only |
| 2 | `src/app-window.vala` + `data/ui/app-window.ui` | `lib/app_window.rb` | window | no |
| 3 | `data/ui/app-window.ui` (`page_menu`) | `lib/page_menu.rb` | menu | no |
| 4 | `src/app-window.vala` (gear menu) | part of `lib/app_window.rb` | menu | no |
| 5 | `data/ui/app-window.ui` (`scan_options_popover`) | `lib/scan_options_popover.rb` | popover | no |
| 6 | `data/ui/app-window.ui` (`status_page`) | `lib/scanner_status_page.rb` | empty/error state | no |
| 7 | `src/app-window.vala` (ActionBar block) | `lib/document_action_bar.rb` | toolbar | no |
| 8 | `src/app-window.vala` (`save_document`) | `lib/save_dialog.rb` | dialog | no |
| 9 | `src/app-window.vala` (`reorder_document`) | `lib/reorder_pages_dialog.rb` | dialog | no |
| 10 | `src/app-window.vala` (`show_about`) | `lib/about_dialog.rb` | dialog | no |
| 11 | `src/app-window.vala` (`install_drivers`) | `lib/install_drivers_dialog.rb` | dialog | no |
| 12 | `src/app-window.vala` (message dialogs) | `lib/alerts.rb` | error/confirm states | no |
| 13 | `src/app-window.vala` (`CancellableProgressBar`) | `lib/cancellable_progress_bar.rb` | widget | no |
| 14 | `src/app-window.vala` (`print_document`) | `lib/print_operation.rb` | dialog/print | no |
| 15 | `src/preferences-dialog.vala` + `data/ui/preferences-dialog.ui` | `lib/preferences_dialog.rb` | preferences | no |
| 16 | `src/authorize-dialog.vala` + `data/ui/authorize-dialog.ui` | `lib/authorize_dialog.rb` | dialog | no |
| 17 | `data/ui/help-overlay.ui` | `lib/shortcuts_dialog.rb` | shortcuts | no |
| 18 | `src/book-view.vala` | `lib/book_view.rb` | view | no |
| 19 | `src/page-view.vala` | `lib/page_view.rb` | view | no |
| 20 | `src/page-icon.vala` | `lib/page_icon.rb` | widget | no |
| 21 | `src/book.vala` | `lib/book.rb` | model | no |
| 22 | `src/page.vala` | `lib/page.rb` | model | no |
| 23 | `src/scanner.vala` | `lib/scanner.rb` | service | no |
| 24 | `src/autosave-manager.vala` | `lib/autosave_manager.rb` | service | no |
| 25 | `src/screensaver.vala` | `lib/screensaver.rb` | service | no |
| 26 | `data/org.gnome.SimpleScan.gschema.xml` | `lib/settings.rb` | settings | no |
| 27 | `po/`, `desktop.in`, `appdata.xml.in` | packaging + gettext | i18n/packaging | no |

27 components. One exists, as a stub.

## Blockers to resolve before the port can reach parity

1. **No SANE binding in ruby-gnome.** `src/scanner.vala` (1802 lines) is the
   whole scanning engine. Options: FFI to `libsane`, or drive the `scanimage`
   CLI. Every scan-related component downstream (status page states, progress,
   authorise dialog, driver install) depends on this choice.
2. **Upstream is GTK3 + libhandy; the port is GTK4 + Libadwaita.** None of the
   `.ui` files can be reused, and every GTK3-ism in the table at the top needs a
   deliberate translation. The `.ui` files are the component spec, not source.
3. **`Gtk.Dialog.run ()` has no GTK4 equivalent.** `AppWindow.authorize` and
   the replace-file / save-before-quit prompts are written as blocking calls
   inside non-async code paths; the port has to restructure them as callbacks.
4. **`Gtk.PrintOperation` and `Gtk.FileChooserNative`** — confirm both are
   bound in the fork's ruby-gnome before planning §8 and §14.
5. **GUsb** (device hotplug in `simple-scan.vala`) and **colord** / **PackageKit**
   / **libwebp** (optional upstream deps behind `#if`) have no ruby-gnome
   bindings. Decide per feature whether the port carries it, and record the
   omission in the class comment as the pilot port does.
6. **No `Gtk::ShortcutsWindow`** in current GTK4/bindings — §17 must be
   hand-built as an `Adwaita::Dialog`.
7. **Three bundled icons** (`scan-type-adf-symbolic`, `scan-type-batch-symbolic`,
   `crop-symbolic`) must be carried into the port and registered with the icon
   theme; without them §5 and §7 render blank.
8. **GSettings schema installation** in a gem-shaped project — the schema must
   be compiled somewhere `Gio::Settings` can find it, or `lib/settings.rb` must
   be backed by a plain file.
