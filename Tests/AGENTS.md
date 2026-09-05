# Test Guidance

These rules apply to every file under `Tests/`.

## Regression coverage

- Every production bug fix must include a test that fails for the reported behavior before the fix.
- Exercise the real production type or the narrowest production helper that controls the behavior. Do not duplicate
  production logic inside a test and then test the duplicate.
- Keep tests deterministic. Use isolated `UserDefaults` suites, checked-in fixtures, injected clocks, and injected
  pointer locations. Unit tests must not depend on the live network, the current pointer position, or another app.
- Do not weaken an assertion or update an expected result solely to make a regression pass.

## Required verification order

1. Run `python3 Scripts/check-source-invariants.py`. This must pass before compiling.
2. Run `make test`. Every test must execute and pass before packaging or installation.
3. For dropdown, panel, scrolling, graph, or layout changes, run:
   `POPOVER_SNAPSHOT_DIRECTORY="$PWD/dist/panel-screens" make test`.
   Inspect representative top, middle, and bottom captures in both appearances. Check alignment, clipping, scrolling,
   panel placement, card shapes, gradients, and glows.
4. Run `python3 Scripts/benchmark-popover-memory.py` for any SwiftUI surface or graph change.
5. Run `python3 Scripts/benchmark-memory.py dist/memory-baseline` for any sampling or retained-history change.
6. Run `git diff --check`.

Record the commands and results in `docs/PROGRESS.md`. A failing check blocks packaging and installation until the
failure is fixed and the complete applicable sequence passes again.

## Screen and memory regressions

- The screen-placement suite must keep every custom Barometer panel inside the visible display at every corner in
  light and dark appearances. Any scrollable panel must prove it can reach its true bottom.
- Populate graph histories in screen tests. A blank graph does not verify path alignment, fill, markers, or glow.
- The panel benchmark must exercise the rich Weather surfaces and every shared graph primitive. Its peak must remain
  below the checked threshold, and repeated cycles must not show continuing growth.
- Do not add SwiftUI `Canvas` to `MenuBarStatsUI`. Measured graph backings retained more than 160 MiB after closing;
  the pre-build source invariant enforces the shape-path implementation.
