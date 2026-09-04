# Stable status-item sizing on macOS 27

This document records the sizing contract that prevents Barometer items from moving with any menu bar manager. It is
a design constraint, not an implementation suggestion. Read it before changing menu bar
font weight, typography, glyph scale, graph size, display mode, or status-item code.

Menu bar sizing is automatic. Text ranges from 9–12 points and icon and graph scale ranges from 75–115 percent,
according to the enabled-item count. Keep both policies centralized in `AppSettings`; previews and production
rendering must not define separate limits or expose manual size controls.

The former Compact internal layout/high-density and Regular/Compact spacing controls were removed. Condensing text
made it unreadable, while changing transparent padding inside immutable outer frames could only redistribute the same
blank area rather than alter the real distance between items. Barometer therefore uses one legible internal layout
with zero app-added horizontal padding. Do not reintroduce either control.

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
back with a narrower exception: it allowed a live length write when `AppSettings` changed. Font size, font weight,
the former density controls and glyph scale therefore appeared to work immediately, but the items no longer reliably
retained the positions chosen by the user.

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
   starts and captures font weight with them. Controllers created later in the same process use that same launch
   geometry.
2. A renderer produces its natural image using that frozen geometry and the current module display settings.
3. Barometer rounds the natural width up to a two-point grid, assigns the AppKit length once, and only then makes the
   item visible. No width from an earlier process is read or preferred.
4. Later settings and samples may redraw colors and readings, but cannot change launch geometry or the live AppKit
   length. The rendering remains anchored to the leading edge and is never recentered or miniaturized.
5. After the user ordinarily quits and reopens Barometer, all geometry and widths are freshly calculated from the
   saved configuration before the items appear. Settings never force a relaunch.

This preserves stable outer positions without retaining stale transparent space from an earlier layout. The exact
outer width takes effect on the next launch because macOS 27 does not provide a verified way to resize a live item
without risking reassessment by at least one manager.

## Common application identity

Every status item is owned by the single `com.barometer.app` process and uses the static AX label `Barometer`, so every
child groups under the same source app in a manager. Each movable child still requires a unique autosave name and
matching AX identifier, such as `Barometer.CPU`; giving all children the same key would create an identity collision
rather than a common owner.

Prepare every standard identity and every saved extra Sensors identity before allowing any item to become visible.
Assign each autosave name and AX identity synchronously before its first `isVisible` transition. Do not create another
identity beside the live set; newly added Sensors widgets join on the next normal launch. Do not manually delete
AppKit's visibility or position defaults for inactive children. On macOS 27, any of these mistakes can produce a
mismatched manager catalog, such as a CPU autosave record carrying Sensors' AX identifier.

## Why the width is explicit

`NSStatusItem.variableLength` adds AppKit's standard image padding. Barometer uses an explicit length equal to its
rendered canvas so zero app-added spacing is attainable while CPU, Memory, Weather, Sensors, and the other modules
remain separate items that the user can move independently.

Do not replace the separate items with one combined status item as a sizing workaround. Combined is an optional
module, not the implementation of density.

## Required regression checks

Before accepting a change to menu bar geometry or status-item lifecycle:

1. Run `swift test` and keep tests proving that applied launch geometry and live width reject later proposals.
2. Run the repository search above and verify exactly one production assignment remains.
3. Run `swift build -c release` and `git diff --check`.
4. Install with `make install`; repository-path launches are not valid compatibility tests.
5. Confirm each active item has its fixed autosave name, empty title, static AX label, nonzero image, and one bundle
   owner in `~/Library/Logs/Barometer/identity.json`.
6. Change enabled widgets and font weight. Confirm no live status-item length or launch geometry changes.
7. Quit and reopen Barometer. Confirm fresh widths are calculated from the saved settings before visibility.
8. When a manager compatibility check is needed, ask David to restart or operate the manager. Barometer must never
   detect, modify, automate, or special-case Bartender, Thaw, Barbie, or another menu bar manager.

If an operating-system update appears to permit safe live resizing, treat that as a new investigation. Preserve this
contract until the alternative is reproduced, documented, and explicitly approved.
