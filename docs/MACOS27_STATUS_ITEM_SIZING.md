# Stable status-item sizing on macOS 27

This document records the sizing contract that prevents Barometer items from moving with any menu bar manager. It is
a design constraint, not an implementation suggestion. Read it before changing menu bar
font size, font weight, condensed typography, glyph scale, graph size, display mode, or status-item code.

The supported menu bar font-size range is 9–12 points. Twelve points is the largest user-selectable size that fits
the fixed-height canvases consistently. The icon and graph scale is 75–115 percent. Keep both ranges centralized in
`AppSettings`; settings, previews, and production rendering must not define separate limits.

The former Compact internal layout/high-density and Regular/Compact spacing controls were removed. Condensing text
made it unreadable, while changing transparent padding inside immutable outer frames could only redistribute the same
blank area rather than alter the real distance between items. Barometer therefore uses one legible internal layout
with zero app-added horizontal padding. Do not reintroduce either control.

Barometer also applies a deterministic density ceiling to the effective font size: up to eight enabled independent
items may use 12 points, nine through eleven use at most 11, twelve through fourteen use at most 10, and fifteen or
more use 9. The user's selection is retained, so disabling items can restore the larger effective size. Count
sensor-widget instances and respect Combined's hide-members behavior when calculating the enabled item count.

## Problem

On the tested macOS 27 beta, assigning `NSStatusItem.length` while an item is live can cause MenuBarAgent and menu bar
managers to reassess its placement. Reassigning the same numeric length is unsafe. Assigning a new length after a
user changes typography is also unsafe.

Barometer first triggered this by writing the rendered width on every sample. A later UI refactor brought the bug
back with a narrower exception: it allowed a live length write when `AppSettings` changed. Font size, font weight,
the former density controls and glyph scale therefore appeared to work immediately, but the items no longer reliably
retained the positions chosen by the user.

The user's manual reorder of two items is not evidence of this bug. The failure signature is an application-initiated
length write followed by one or more independently movable items losing their established placement.

## Decision

An individual `StatusItemController` may assign `statusItem.length` exactly once per process lifetime. A one-way
`StatusItemLengthLatch` enforces that invariant even when later renderings propose different widths. The assignment
must happen during the controller's first enabled render and before `statusItem.isVisible` becomes true.

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

1. A renderer produces its natural image for the current settings.
2. Barometer rounds the natural width up to a four-point grid.
3. On the first enabled render, Barometer prefers the previously committed width when one exists. It fits the image
   into that canvas, assigns the AppKit length once, and only then makes the item visible.
   A controller records geometry settings while hidden; when the user enables it later, its first render uses current
   geometry instead of a stale committed width.
4. If settings propose new geometry while the process remains live, Barometer records its rounded width under
   `Barometer.CommittedWidth.v5.<autosaveName>`. The rendering retains its true font and glyph sizes and clips at the
   trailing edge of the applied frame. It is never recentered or proportionally miniaturized.
5. After the user ordinarily quits and reopens Barometer, the controller applies the staged width before the item
   appears. Settings never force a relaunch.

This preserves stable outer positions while keeping controls responsive. The exact outer width takes effect on
the next launch because macOS 27 does not provide a verified way to resize a live item without risking reassessment
by at least one manager.

## Common application identity

Every status item is owned by the single `com.barometer.app` process and should group under Barometer in a manager.
Each movable child still requires a unique autosave name and matching AX identifier, such as `Barometer.CPU`; giving
all children the same key would create an identity collision rather than a common owner.

Assign the autosave name and AX identity synchronously before the first `isVisible` transition. Do not manually delete
AppKit's visibility or position defaults for inactive children. On macOS 27, either mistake can recycle a persistence
slot and produce a mismatched manager catalog, such as a Combined autosave record carrying Network's AX identifier.

## Why the width is explicit

`NSStatusItem.variableLength` adds AppKit's standard image padding. Barometer uses an explicit length equal to its
rendered canvas so zero app-added spacing is attainable while CPU, Memory, Weather, Sensors, and the other modules remain
separate items that the user can move independently.

Do not replace the separate items with one combined status item as a sizing workaround. Combined is an optional
module, not the implementation of density.

## Required regression checks

Before accepting a change to menu bar geometry or status-item lifecycle:

1. Run `swift test` and keep tests proving that an applied live width wins over wider and narrower staged widths.
2. Run the repository search above and verify exactly one production assignment remains.
3. Run `swift build -c release` and `git diff --check`.
4. Install with `make install`; repository-path launches are not valid compatibility tests.
5. Confirm each active item has its fixed autosave name, empty title, static AX label, nonzero image, and one bundle
   owner in `~/Library/Logs/Barometer/identity.json`.
6. Change font size, font weight, and glyph scale. Confirm the app stages new widths without
   changing any live status-item length.
7. Quit and reopen Barometer. Confirm the staged widths are applied before visibility.
8. When a manager compatibility check is needed, ask David to restart or operate the manager. Barometer must never
   detect, modify, automate, or special-case Bartender, Thaw, Barbie, or another menu bar manager.

If an operating-system update appears to permit safe live resizing, treat that as a new investigation. Preserve this
contract until the alternative is reproduced, documented, and explicitly approved.

The `v5` component is an intentional cache-schema version. Increment it when a future rendering constraint makes old
committed widths structurally invalid. Do not increment it merely to force arbitrary movement or bypass the staged
width lifecycle.
