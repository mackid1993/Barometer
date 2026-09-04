# Stable status-item sizing on macOS 27

This document records the sizing contract that prevents Barometer items from moving with any menu bar manager. It is
a design constraint, not an implementation suggestion. Read it before changing menu bar typography, glyph scale,
graph size, display mode, or status-item code.

Menu bar sizing is automatic. Text ranges from 9–12 points and icon and graph scale ranges from 75–115 percent,
according to the enabled-item count. Keep both policies centralized in `AppSettings`; previews and production
rendering must not define separate limits or expose manual size controls.

The former Compact internal layout/high-density and Regular/Compact spacing controls were removed. Condensing text
made it unreadable, while changing transparent padding inside immutable outer frames could only redistribute the same
blank area rather than alter the real distance between items. Barometer therefore uses one legible internal layout
with zero app-added horizontal padding. This applies uniformly to plain text, label/value stacks, sensor stacks,
icon-and-text rows, symbols, and vertical icon stacks. Do not reintroduce either control.

AppKit also reads `NSStatusItemSpacing` and `NSStatusItemSelectionPadding` from the defaults search list and wraps
each explicit canvas in that spacing. Barometer sets both keys to two only in its own `com.barometer.app` defaults
domain before constructing `StatusItemRegistry`. Zero makes adjacent text collide; the host default of four is too
loose for dense monitoring. Never write or delete the by-host global values: Barometer's compact spacing must not
change spacing for the rest of the user's menu bar.

Barometer also applies deterministic density tiers. Up to eight enabled independent items may use 12-point text,
nine through eleven use at most 11, twelve through fourteen use at most 10, and fifteen or more use 9. Graphic scale
is 115 percent for one through three items, 100 for four through six, 90 for seven or eight, 85 for nine through
eleven, 80 for twelve through fourteen, and 75 for fifteen or more. Count sensor-widget instances and respect
Combined's hide-members behavior.

## Problem

On the tested macOS 27 beta, assigning `NSStatusItem.length` while an item is live can cause MenuBarAgent and menu bar
managers to reassess its placement. Reassigning the same numeric length is unsafe. Assigning a new length after a
user changes typography is also unsafe.

Barometer first triggered this by writing the rendered width on every sample. A later UI refactor brought the bug
back with a narrower exception: it allowed a live length write when `AppSettings` changed. Font size, the former
density controls, and glyph scale therefore appeared to work immediately, but the items no longer reliably retained
the positions chosen by the user.

The user's manual reorder of two items is not evidence of this bug. The failure signature is an application-initiated
length write followed by one or more independently movable items losing their established placement.

## Decision

An individual `StatusItemController` may assign `statusItem.length` exactly once per process lifetime. A one-way
`StatusItemLengthLatch` enforces that invariant even when later renderings propose different widths. A separate
launch-time geometry latch prevents settings changes from shrinking content inside that immutable frame. The length
assignment must happen during the controller's first enabled render and before `statusItem.isVisible` becomes true.

`StatusItemController` is the only production type allowed to assign `statusItem.length`. A repository search should
find exactly one assignment:

```sh
rg -n 'statusItem\.length\s*=' Sources
```

There are no live-resize exceptions. In particular, do not add an exception for:

- a settings change initiated by the user;
- a display-mode change;
- a notification or manual recompute command;
- a delayed or debounced update;
- a hidden item that has already received its initial length; or
- a comparison that concludes the new and old lengths differ or are equal.

## Width lifecycle

1. `SettingsStore` calculates font size and graphic scale once from the complete saved widget set when Barometer
   starts. Controllers created later in the same process use that same launch geometry.
2. A renderer produces its natural image using that frozen geometry and the current module display settings. Font
   weight and colors are live paint properties and redraw immediately inside the fixed canvas. The initial length
   calculation reserves the semibold rendering width, allowing every supported weight to fit without a later resize.
3. Barometer rounds the natural width up to a two-point grid, assigns the AppKit length once, and only then makes the
   item visible. No width from an earlier process is read or preferred.
4. Later settings and samples may redraw colors and readings, but cannot change launch geometry or the live AppKit
   length. The renderer does not add edge insets. Single-line numeric fields are trailing-aligned within their
   reserved width, while stacked label/value modes keep both rows on one leading edge. The outer canvas is never
   recentered or miniaturized.
5. Module and Sensors-widget visibility controls remain staged until the user selects **Apply Changes**. Apply saves
   the complete visibility set and performs a controlled application reopen; it never mutates a live item length.
   All geometry and widths are then freshly calculated from the saved configuration before any item appears.

This preserves stable outer positions without retaining stale transparent space from an earlier layout. The exact
outer width takes effect on the next launch because macOS 27 does not provide a verified way to resize a live item
without risking reassessment by at least one manager.

## Common application identity

Every status item is owned by the single `com.barometer.app` process, so every child groups under the same source app
in a manager. Each movable child still requires a unique autosave name, matching AX identifier, and static label, such
as `Barometer.CPU` and `CPU`; giving all children the same child identity would create a collision rather than a
common owner.

Prepare exactly the enabled, non-Combined-hidden identities before allowing any item to become visible. Assign each
autosave name and AX identity synchronously before its first `isVisible` transition. Render every launch item and
attach every controller and menu while the complete set remains hidden, then reveal the set synchronously in the
same canonical `ModuleID` order used to construct the registry. Revealing controllers while the coordinator is only
partly assembled exposes a different child order and lets an external manager save a valid autosave identity against
the wrong ordinal.

Do not create disabled hidden items: their persistence slots have no visible AX counterparts, so macOS 27 managers
can pair the slots and children by conflicting ordinals. Create a newly enabled identity once, assign its full
identity, attach its controller and menu, render it while hidden, and only then activate visibility. Do not manually
delete AppKit's position defaults. An incomplete first snapshot can also pair one child's autosave slot with another
child's AX identity.

## Why the width is explicit

`NSStatusItem.variableLength` adds AppKit's standard image padding. Barometer uses an explicit length equal to its
rendered canvas so zero app-added spacing is attainable while CPU, Memory, Weather, Sensors, and the other modules
remain separate items that the user can move independently.

Reserved fields are stability space, not decoration. Do not add generic `+ 4` width allowances, half-point edge
insets, or renderer-specific side padding. Center a symbol only inside a symbol field whose width must remain stable.
Trailing-align a standalone changing value inside its stable numeric field, but never offset one row of a stacked
label/value pair from the other. This preserves the one-time outer length without breaking row alignment.

Do not replace the separate items with one combined status item as a sizing workaround. Combined is an optional
module, not the implementation of density.

## Required regression checks

Before accepting a change to menu bar geometry or status-item lifecycle:

1. Run `swift test` and keep tests proving that applied launch geometry and live width reject later proposals.
2. Run the repository search above and verify exactly one production assignment remains.
3. Run `swift build -c release` and `git diff --check`.
4. Install with `make install`; repository-path launches are not valid compatibility tests.
5. With a different by-host global spacing, confirm each active Barometer window is exactly two points wider than its
   button, image, and fixed item length, which must match one another. Confirm each item also has its fixed autosave
   name, empty title, static AX label, nonzero image, and one bundle owner in
   `~/Library/Logs/Barometer/identity.json`.
6. Change enabled widgets and confirm the live set does not change before selecting **Apply Changes**.
7. Apply the pending changes. Confirm Barometer reopens and calculates fresh widths from the complete saved set before
   visibility. Change font weight separately and confirm it redraws live without changing item length.
8. When a manager compatibility check is needed, ask David to restart or operate the manager. Barometer must never
   detect, modify, automate, or special-case Bartender, Thaw, Barbie, or another menu bar manager.

If an operating-system update appears to permit safe live resizing, treat that as a new investigation. Preserve this
contract until the alternative is reproduced, documented, and explicitly approved.
