# Test parity — simple-scan-rb

| | |
|---|---|
| Upstream | `origin/main` |
| Port | `ruby` |
| Upstream tests | 0 |
| Ported | 0 |
| Gaps | 0 |
| Test command | none — `spec/` has no spec files; `test/drive_app_window.rb` is a manual drive script |

## Upstream has no test suite

Verified directly against `origin/main` (246 tracked files):

```
git ls-tree -r --name-only origin/main | grep -i test   # zero matches
```

No `test/`, `tests/` directory, no `g_test_add_func`/`GLib.Test`, no meson
`test()` target. Upstream simple-scan ships no automated tests at all.

Per the `test-parity` skill's own rule for this exact case: **parity is 0/0
and is met trivially, and the port therefore inherits no safety net.** That
line has to be said explicitly, not left implied, so it is said here: nothing
in this port's test posture is backed by a test upstream ever wrote. Every
check that exists was written by the port, for the port, and pins only what
the port's own authors thought to pin.

## What the port actually has

- `spec/` contains only `README.md` (describing the `kettle-test` harness)
  and `spec_helper.rb`. **There are zero `*_spec.rb` files.** The spec
  infrastructure is wired up and unused — `bundle exec rspec` or the dev
  shell's own documented spec command runs an empty suite.
- `test/drive_app_window.rb` is a single 388-line script, not a test
  framework file: no `test_*` methods, no assertions library, just a `check`
  helper that prints `ok`/`FAIL` lines and a final tally. It is a manual
  smoke-drive, structurally the same shape as the `## Extra` category the
  skill describes for apps with no upstream suite to port against.

Run live in this audit, in the fork's own dev shell and virtual display, per
the project's own instructions:

```
nix develop --command xvfb-run -a ruby test/drive_app_window.rb
```

Result: `49 of 49 checks passed`, `DRIVE OK`. This is real — it was executed,
not assumed — and it is reported as `## Extra`, not as test parity, because
that is what it is: a script written for the port, pinning behaviour the
port's own authors chose to check, not a port of anything upstream wrote.

**Re-run again in this audit pass** (`nix develop --command xvfb-run -a ruby
test/drive_app_window.rb`), independently of the above: same result, `49 of
49 checks passed`, `DRIVE OK`. The script now also attempts two widget
screenshots (`shot 06-document`, `shot 07-empty-again`) added since the
prior pass; both raised `RuntimeError: widget produced no render node (not
realised yet?)` and were caught and printed, not counted as failures — the
script's own comment says plainly "a screenshot is not an assertion, so a
failure here never fails a check." That is disclosed, not a hidden
false-green, and is noted here only for completeness.

One line of this run's output is more significant: the install-drivers
check printed `Failed to install drivers:
GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown: The name is not
activatable` and was still marked `ok`, because the check only ever asserted
the dialog's two display strings, not the PackageKit resolve/install call
itself. See `.reports/component-parity.md` finding 2 for the detail: the
PackageKit install code was wired up since the prior test-parity pass (a
real fix), but this drive script does not and cannot (no PackageKit D-Bus
service is activatable in the xvfb sandbox) verify that the install call
itself succeeds. That specific mechanism remains unverified by anything
that runs, which per the task brief counts as "unverified, not done."

## The runtime gate is a drive script, not a test suite

The task brief's "49 checks passed, 0 failed, 27 components" gate is this
same `drive_app_window.rb` run. Treating a single manual drive script's
"OK" as evidence of test parity would be exactly the false-green this audit
is required to flag: it proves 27 components start up and respond to one
scripted interaction each. It proves nothing about:
- any of the 76 locale catalogues actually loading and substituting text
  (the drive script runs in the default/English locale only — confirmed: no
  `LANG=`/`LANGUAGE=` variation anywhere in `test/drive_app_window.rb`);
- the PackageKit install path in `install_drivers_dialog.rb` (see
  `.reports/component-parity.md` — there is nothing to drive, because it was
  never built);
- device hot-plug (`device-added`/`device-removed`) — the script drives one
  fixed `ScanDevice`, never a second one appearing or the first disappearing;
- error recovery paths beyond the single "error alert builds, presents and
  closes" check, which does not assert the alert shows the *right* message
  for more than one failure mode.

## Extra

- `test/drive_app_window.rb` — 49 checks, driving the application window,
  its dialogs, scan options, document model, save/print pipeline, autosave
  and window-state persistence. Confirmed to run and pass in this audit.

## Verdict

**Not clean**, but not for the reason a shallower read would give it: the
0/0 upstream-test bijection genuinely holds (there is nothing to port). The
gap is that the port has built no automated regression suite of its own
beyond one hand-run drive script, and that script is never invoked by CI:
there is no `.github/workflows/` directory at all, and `.gitlab-ci.yml` never
mentions `drive`, `xvfb` or `Xvfb` (confirmed by direct grep in this audit — not re-verified in this pass), and `spec/` is scaffolding with no
tests in it. That is a real gap in safety net, worth stating plainly per the
skill's own instruction, even though it is not a bijection failure.
