# Barometer 1.0.7

Barometer 1.0.7 redraws the weather reading, counts your whole network, and adds several ways to fit more into less
menu bar space. It also lets you choose light or dark for the app itself.

## A new weather reading

- The temperature is now the icon. The number is drawn at full size and the weather sits on it: a cloud resting on
  the number, rain, snow, or lightning underneath, a sunburst around it, a crescent over the degree sign at night.
- It takes about half the room of the old icon-and-temperature pair, and every condition is the same width, so the
  reading never shifts when the weather changes.
- It is in color: amber for a sunny day, lavender for a clear night, blue rain, icy snow, a yellow bolt. This stays on
  even if the rest of your menu bar is monochrome. Turn off **Color weather icons** in Weather settings to keep it
  plain.
- Weather settings show every condition side by side so you can see the whole set.
- Before the first forecast arrives, the reading shows a dash and a degree sign, with no weather drawn on it.
- The forecast dropdown still uses the system's weather symbols.

## Your whole network, not just the main connection

- **Automatic** now adds up every active connection instead of only the main one, so a wired port beside Wi-Fi, a
  virtual machine, a bridge, or AirDrop all count. It still shows the main connection's name and addresses.
- A VPN is not counted twice. Its traffic already passes through the physical connection.
- A new **All interfaces** choice totals everything, VPN included.
- Loopback can be picked on its own. It was missing from the list before.
- Per-app network activity now includes traffic that never leaves your Mac, such as local servers and virtual
  machines. It previously counted only traffic going out to the internet.

## Smaller menu bar readings

- A new **Item width** setting fits each reading to the value it is showing right now. Readings normally leave room
  for their largest possible value, like a three-digit temperature, and this frees up about a fifth of the space
  Barometer takes.
- Widths settle as they go. A reading only ever widens when it needs more room, so items stop moving once they have
  warmed up, and nothing is ever cut off.
- A new **Text size** slider makes menu bar text smaller, down to 9 pt. Icons and graphs shrink to match. Barometer
  already shrinks text on its own as you add more items, so the slider can only go smaller than that.
- A new **Item spacing** setting controls the gap around Barometer's items. System keeps your normal spacing. Snug,
  Tight, and Tightest close the gap, with Tightest removing it entirely. Only Barometer's items are affected, and if
  you have already tightened your menu bar another way, this may not change anything.
- Text size and Item spacing take effect when you select Apply Changes, which reopens Barometer.

## Light, dark, or system

- General now has an **Appearance** choice: Light, Dark, or System. It applies to the Settings window, every dropdown,
  and the colors of the weather reading, instead of only following macOS.
- Every module's dropdown now opens in the same translucent panel, so they all look alike and all follow that choice.

## Notes

- Item width and Item spacing are off by default, Text size starts where it always was, and Appearance starts on
  System. An existing installation looks the same as it did in 1.0.6 until you change something.
- Every reading was checked at each setting, including the clock at its longest format, and none is cut off.

Barometer 1.0.7 is a notarized, stapled DMG for Apple silicon Macs running macOS 26 or later.
