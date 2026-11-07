# Translation parity — simple-scan-rb

| | |
|---|---|
| Upstream | `origin/main` |
| Port | `ruby` |
| Upstream `.po` catalogues | 76 (per `po/LINGUAS`) |
| Port `.po` catalogues | 76 |
| Catalogue files copied verbatim | yes, spot-checked |

## What survived (confirmed, not assumed)

- `po/LINGUAS` lists 76 languages on both sides; `po/` holds exactly 76 `.po`
  files on `ruby`, matching.
- `de.po` diffed byte-for-byte on its `msgid` lines between
  `origin/main:po/de.po` and the port's `po/de.po`: **202 msgids on each
  side, zero differences.** The port did not reword, retype or re-wrap any
  of upstream's existing message catalogue — it is copied, not rebuilt from
  scratch. This is the right move and is confirmed, not inferred.
- `lib/translations.rb` binds the same `simple-scan` gettext domain upstream
  uses and documents, correctly, that the port's msgids have to stay
  character-for-character identical to upstream's for those 76 catalogues to
  keep working — and the `de.po` check above shows that constraint is being
  honoured for the strings that are extracted at all.

## Gaps — strings that exist upstream and have no path into the port's catalogue

### 1. `data/org.gnome.SimpleScan.gschema.xml` does not exist in the port at all

Upstream's schema carries a `<summary>` and `<description>` for each of its
keys:

```
git show origin/main:data/org.gnome.SimpleScan.gschema.xml | grep -c "<summary>\|<description>"
=> 26
```

26 translatable strings. There is no gschema file anywhere under `ruby`
(`lib/settings.rb` replaces the mechanism with a JSON file — see
`.reports/component-parity.md`), so these 26 strings have no Ruby source
location to be marked in and are not in `po/simple-scan.pot`. They are not
moved, not reworded — they are gone. This is 26 of the catalogue's rows that
76 translator teams wrote and the port cannot show in any language, because
nothing in the port ever displays them (there is no settings UI panel that
shows a key's description the way `dconf-editor` would) — which is itself a
symptom of the backend substitution, not a separate bug, but it means the
string loss is real either way.

### 2. `data/simple-scan.desktop.in` and `data/simple-scan.appdata.xml.in` exist in the port, but are not extracted

Both files are present under `ruby`'s `data/` (confirmed: `find data -type f`
lists both), and both still carry their translatable content byte-for-byte
from upstream:

```
Name=Document Scanner
Comment=Make a digital copy of your photos and documents
Keywords=scan;scanner;flatbed;adf;
```

and the appdata file's `<name>`, `<summary>`, and release-note `<p>` entries.
Upstream's `po/POTFILES.in` lists both files as translatable sources. The
port's `po/POTFILES.in` does **not**:

```
upstream po/POTFILES.in:
data/org.gnome.SimpleScan.gschema.xml
data/simple-scan.appdata.xml.in
data/simple-scan.desktop.in
data/ui/app-window.ui
data/ui/authorize-dialog.ui
data/ui/help-overlay.ui
data/ui/preferences-dialog.ui
src/app-window.vala  src/book.vala  src/page.vala
src/preferences-dialog.vala  src/scanner.vala  src/simple-scan.vala

port po/POTFILES.in: only lib/*.rb files (29 entries), none of
data/simple-scan.desktop.in or data/simple-scan.appdata.xml.in
```

Consequence: the app's **name, one-line summary, search keywords, and the
GNOME Software description/release notes** are never pulled into
`po/simple-scan.pot`, so no translator ever sees them and no `.po` file ever
carries a translation for them. In a software centre or app grid running in
any of the 76 languages this ships catalogues for, the app's own title and
description fall back to English while every other string in the app is
localized. The four `.ui` files have a legitimate correspondence (their
strings are built in Ruby and already appear via the `lib/*.rb` entries that
replace them — confirmed for at least `preferences_dialog.rb`,
`authorize_dialog.rb`); the desktop and appdata files have no such
correspondence. Nothing in `lib/` builds or re-marks their strings.

### 3. `po/simple-scan.pot` msgid count is lower than upstream's marked-string count, consistent with the above

```
port po/simple-scan.pot msgids:                 153
upstream _()/N_()/ngettext() call sites in
  src/*.vala + data/*.ui combined (regex count): 108 occurrences / 96 distinct
```

The port's count being higher than upstream's raw occurrence count is
expected and not itself a problem (one upstream string can be referenced
from several call sites, and the port's own strings — error messages built
fresh in Ruby, e.g. in `alerts.rb` — add rows too). It is reported here only
to show the counts were actually pulled and compared, not asserted. The
concrete gap is items 1 and 2 above, which are omissions the count alone
does not surface.

### 4. Help pages: only the English (`C`) tree is ported; upstream's 40 translated help trees are not

Separate from `po/*.po` (which covers UI strings), upstream also ships
per-language Mallard help trees under `help/<lang>/`, listed in
`help/LINGUAS` — 40 languages. This audit's re-pass of the repository (since
`.reports/component-inventory.md` was last updated) found the man page and
`help/C/*` were ported verbatim in commit `5d7e894e` — a real fix, credited
in `.reports/component-parity.md`. But `find help -type f` on `ruby` shows
only `help/C/*`; none of the 40 translated trees exist. A non-English user
opening in-app help gets English, where upstream would show their own
language.

**Verdict: gap**, newly discovered against a part of the tree that did not
exist in the port at the time of the prior translation-parity pass.

### 5. Confirmed again this pass: the desktop/appdata gap is also an installation gap, not only an extraction gap

Item 2 above (POTFILES.in omission) still holds unchanged. This pass also
checked whether the two files are even installed anywhere runnable — they
are not (`.reports/component-parity.md` finding 4) — so the translation gap
compounds with a packaging gap: not only do the app's name/summary/keywords
never reach a `.po` file, the files carrying them are never installed to
where a desktop environment or software centre would read them in *any*
language, English included.

## What this report does not claim

This pass spot-checked one catalogue (`de.po`) byte-for-byte and did not diff
all 76 `.po` files individually, and did not re-render each of the 153
extracted msgids against its upstream counterpart string-by-string (the
`component-parity` report's "text axis" per-component). Those are not
claimed clean; they are unverified in this pass.

## Verdict

**Not clean.** Confirmed again in this pass: the entire 26-string gschema
catalogue is still missing, the desktop/appdata files' strings still never
reach `po/POTFILES.in`, and (newly found this pass) 40 of upstream's 41
help-page language trees were never ported. The man page and English help
pages did get ported since the prior pass — credited, not a gap. None of
the remaining gaps are excused anywhere in the port's own files (no
`PORTING.md` or similar exists on this branch) — the omissions have not
been laundered into a "decision" yet. They still need to be built.
