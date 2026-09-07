# Barometer 1.0.7

Barometer 1.0.7 adds two optional ways to tighten the menu bar, both off by default.

## Item width

- A new **Item width** setting shrinks each item to fit the reading it is currently showing.
- Items normally reserve room for the widest value they can ever display, such as a three-digit temperature. Sizing
  them to the live reading recovers roughly a fifth of the space Barometer occupies.
- Measured across five items, the row went from 262 to 208 points. Weather, Sensors, and Combined gain the most.
- Battery and Disks are unchanged, because their width comes from a fixed icon rather than a reserved value.
- Items shift as readings change width. Barometer normally sets each width once, which is what keeps menu bar
  managers from moving items, so this setting carries a caution: if items start moving on their own, turn it off and
  reopen Barometer.

## Menu bar spacing

- A new **Item spacing** setting controls the width Barometer reserves around its own items.
- System keeps the spacing macOS uses. Snug, Tight, and Tightest reduce it, with Tightest removing it entirely.
- Only Barometer's items are affected. A gap next to another app's item closes by Barometer's share alone, because
  that app still reserves its own.
- Tightest is the floor. If you already tighten the menu bar system-wide, this setting will not change anything.
- Spacing takes effect when you select Apply Changes, which reopens Barometer.

## Notes

- Both settings are off by default. An existing installation looks and behaves exactly as it did in 1.0.6.
- Every module was checked at both settings, including the clock at its longest format, and none clips its content.

Barometer 1.0.7 is a notarized, stapled DMG for Apple silicon Macs running macOS 26 or later.
