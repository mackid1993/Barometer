# Barometer 1.0.7

Barometer 1.0.7 redraws the weather reading, shows internal network activity, and adds three ways to fit more into
less menu bar space.

## Internal network activity

- Network can now show **All interfaces**, which adds up every active connection instead of just the main one.
- Activity that never leaves your Mac is now included: local connections, virtual machines, bridges, and AirDrop.
- Per-app network activity now counts that traffic too. It previously showed only traffic going out to the internet.
- Loopback can also be picked on its own. It was missing from the list before.
- Automatic still follows your main connection, so the default reading is unchanged.

## A new weather mark

- The weather reading is now the icon. The temperature is drawn at full size and the condition sits on it: a cloud
  resting on the number, rain, snow, or lightning underneath, a sunburst around it, a crescent over the degree sign.
- It takes about half the room of the old icon-and-temperature pair.
- It is in color, even if the rest of your menu bar is monochrome: amber sun, lavender night, blue rain, icy snow, a
  yellow bolt. Turn **Color weather icons** off in Weather settings to keep it plain.
- Choose **System** under Menu bar icons in Weather settings to go back to the standard symbols.
- Weather settings now show every condition side by side so you can see the whole set.

## Smaller menu bar readings

- A new **Item width** setting fits each reading to the value it is showing right now.
- Readings normally leave room for their largest possible value, like a three-digit temperature. Fitting them to the
  current value frees up about a fifth of the space Barometer takes up.
- Widths settle as they go: a reading only ever widens when it needs more room, so items stop moving once warmed up.
- A new **Text size** slider makes Barometer's menu bar text smaller, down to 9 pt. Icons and graphs shrink to match.
- Barometer still shrinks text on its own as you add more items, so the slider can only go smaller than that.

## Menu bar spacing

- A new **Item spacing** setting controls the gap around Barometer's items in the menu bar.
- System keeps your normal spacing. Snug, Tight, and Tightest close the gap, with Tightest removing it entirely.
- Only Barometer's items are affected. A gap next to another app's item closes halfway, because the other app keeps
  its own spacing.
- If you have already tightened your menu bar spacing another way, this may not change anything.
- Spacing takes effect when you select Apply Changes, which reopens Barometer.

## Notes

- Item width and Item spacing are off by default, and Text size starts where it always was. An existing installation
  looks the same as it did in 1.0.6 until you change something.
- Every reading was checked at each setting, including the clock at its longest format, and none is cut off.

Barometer 1.0.7 is a notarized, stapled DMG for Apple silicon Macs running macOS 26 or later.
