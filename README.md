<p align="center">
  <img src="Resources/AppIcon.png" width="160" alt="Barometer app icon">
</p>

<h1 align="center">Barometer</h1>

<p align="center">
  A system monitor for the macOS menu bar.
</p>

<p align="center">
  <a href="https://github.com/mackid1993/Barometer/actions/workflows/check.yml">
    <img alt="Build"
         src="https://img.shields.io/github/actions/workflow/status/mackid1993/Barometer/check.yml?style=for-the-badge">
  </a>
  <a href="LICENSE">
    <img alt="MIT License" src="https://img.shields.io/github/license/mackid1993/Barometer?style=for-the-badge">
  </a>
  <a href="https://github.com/mackid1993/Barometer/releases/latest">
    <img alt="Latest release" src="https://img.shields.io/github/v/release/mackid1993/Barometer?style=for-the-badge">
  </a>
  <a href="https://github.com/mackid1993/Barometer/releases">
    <img alt="Downloads" src="https://img.shields.io/github/downloads/mackid1993/Barometer/total?style=for-the-badge">
  </a>
</p>

<p align="center">
  <img alt="macOS 26 or later" src="https://img.shields.io/badge/macOS-26%2B-111827?style=flat-square&logo=apple">
  <img alt="Apple silicon" src="https://img.shields.io/badge/Apple%20silicon-native-111827?style=flat-square&logo=apple">
  <img alt="Free and open source" src="https://img.shields.io/badge/free-open%20source-06B6D4?style=flat-square">
</p>

Barometer is a free, open source system monitor for the macOS menu bar. It shows CPU, GPU, memory, disks, network,
temperatures, fans, power, battery, weather, and time as menu bar items. Click an item to open a panel with the
details. Barometer works with menu bar managers such as Bartender
and Thaw on macOS 27.

There is no account, no subscription, and no telemetry. Barometer is one app running as one process with no helper
programs.

## What it shows

| Item | Menu bar | Panel |
| --- | --- | --- |
| **CPU** | A percentage, a `CPU` label over the value, a history graph, per-core bars, or an icon with the value | History from 1 minute to 24 hours, user and system split, every core with performance and efficiency cores labeled, load averages, uptime, process and thread counts, and the top processes with icons and a quit button |
| **GPU** | A percentage, a history graph, or CPU and GPU rows together | Device, renderer, and tiler utilization, graphics memory in use and allocated, and frequency, power, and temperature when the hardware reports them |
| **Memory** | A `MEM` label over the value, used or pressure percentage, a history graph, or a usage bar | A breakdown of app, wired, compressed, and cached memory in the same terms Activity Monitor uses, a pressure graph with the current pressure level, swap, and the top processes by memory |
| **Disks** | A read and write activity graph, free space as a percentage or in bytes, or the read and write rates | Every mounted volume with a capacity bar and an eject button for external drives, and read and write throughput and operations per second for each physical disk |
| **Network** | Download and upload rows, arrows with rates, a `NET` label over the download rate, or an activity graph | Download and upload with a history graph, the interface in use, the apps and processes using the network, local addresses with a copy button, router and DNS, Wi-Fi signal, noise, channel, rate, and security, and an optional public address |
| **Sensors** | One or more separate widgets. Each can be a two-row stack, labels with values, a history graph, or a fan readout | Every temperature the hardware exposes sorted hottest first, fan speeds, power rails, voltages, and currents, each with a sparkline, and energy used since Barometer opened |
| **Battery** | A percentage inside the battery glyph or a `BAT` label with the value | A charge ring, health and cycle count, temperature, voltage, current, and wattage, the connected power adapter, a charge history graph, and the batteries of Bluetooth devices |
| **Weather** | A condition icon over the temperature, the temperature only, icon with temperature and conditions, high and low, or chance of rain | Current conditions, feels like, a 48 hour strip with the temperature curve and rain bars, a 10 day forecast, sunrise, sunset, and moon phase, air quality, and humidity, wind, gusts, pressure, cloud cover, and precipitation |
| **Time** | A date and time in your own format, with or without seconds | A month calendar, world clocks with offsets and day or night, sunrise and sunset for your weather location, and upcoming calendar events if you allow access |
| **Combined** | Any set of the items above inside one menu bar item, with optional separators | A tabbed summary of every included module |

Each item is its own menu bar icon. You can Command-drag them into any order, hide the ones you do not want, or put
several into the Combined item to save space.

## Menu bar options

- Two-row items such as `CPU` over `24%` share one baseline. Values use fixed-width digits so they do not shift as
  the numbers change, and an item keeps the same width while its numbers change.
- Text, icons, and graphs size themselves automatically from the number of enabled widgets. Text uses 12 points with
  up to 8 widgets, 11 points with 9–11, 10 points with 12–14, and 9 points with 15 or more. Graphics use matching
  density steps. Each enabled Sensors widget counts separately; Combined counts as one when it hides its members.
- Barometer adds no extra spacing around menu bar items, leaving as much room as possible around the notch.
- Themes: System (monochrome), Ocean, Sunset, Forest, Neon, or your own colors. Colors can be set once for
  everything or per module, with separate light and dark values and separate colors for graph lines, fills,
  warnings, and critical readings.
- Every panel uses the same glass cards, module colors, animated readouts, and hover rows. Long panels scroll.

## Menu bar managers

macOS 27 changed how the menu bar is drawn and most menu bar managers were rebuilt for it. Barometer is set up for
that:

- Every item belongs to Barometer itself and has a fixed name that never contains a live value, so a manager can
  tell `Barometer.CPU` from `Barometer.Weather` and remember where each one goes.
- Barometer calculates the complete layout when it opens, then keeps every item’s size fixed while it runs. Show or
  hide as many widgets as you like in Settings, then select **Apply Changes**. Barometer reopens once with the complete
  selection and sizes everything together.
- Hiding an item in Barometer keeps its identity, so it comes back where it was.

## Weather

Weather data comes from [Open-Meteo](https://open-meteo.com/). It is free and needs no account or key. Add places
by searching for a city, or turn on **Use current location**. Units: Fahrenheit or Celsius, miles per hour,
kilometers per hour, meters per second, or knots, inches of mercury, hectopascals, or millimeters of mercury, and
inches or millimeters of rain. Forecasts refresh every 15 minutes by default and right after the Mac wakes or
changes networks. The last forecast is saved on disk, so the panel still works offline and is marked as stale.

## Sensors on Apple silicon

Barometer reads temperatures, fans, and power from the hardware without root access or a helper process. Duplicate
sensors are combined by default and firmware identifiers are hidden until you turn on **Show advanced firmware
sensors**. The CPU temperature in the menu bar is the hottest processor die sensor, which is what other monitors
report. The panel also shows the hottest sensor anywhere in the machine.

## Install

1. Download `Barometer-VERSION.dmg` from the [latest release](https://github.com/mackid1993/Barometer/releases/latest).
2. Open it and drag Barometer into Applications.
3. Launch Barometer. If macOS asks, allow it under **System Settings → Menu Bar**.
4. Turn on **Launch Barometer at login** in General settings if you want it to start with your Mac.

Barometer needs macOS 26 or later. Sensor, frequency, and power readings come from Apple silicon.

## Privacy and permissions

Barometer does not collect anything. It uses the network for weather (Open-Meteo) and, only if you turn the option
on, for your public IP address (ipify.org).

- **Location** is optional. It is requested only when you enable current-location weather. It also lets Barometer show
  the name of the Wi-Fi network you are on.
- **Calendar** is optional. It is requested only when you press **Allow Calendar Access** in Time settings.
- Nothing else asks for a permission. Readings that a Mac does not provide are shown as unavailable.

Settings can be exported to a JSON file and imported on another Mac.

## Questions

**Why does Barometer reopen when I apply visibility changes?** Menu bar managers can lose an item's position if its
width changes while it is visible. Barometer keeps every live width fixed, then reopens once to build and size the
complete selection safely.

**Why is a reading missing?** Some values depend on the hardware and on macOS. A Mac without fans shows no fan
readout. Readings that the system stops reporting show as unavailable instead of old numbers.

**Can Barometer control fans?** No. Reading sensors needs no special access. Changing fan speeds would need a
privileged helper and Barometer does not have one.

**Does it work on Intel Macs?** It runs, but temperature, frequency, and power readings come from Apple silicon
interfaces, so those sections will be mostly empty.

## Building it yourself

Barometer is a Swift package with no third-party dependencies and no Xcode project. With Xcode 27's Swift 6.4
command-line toolchain installed, run:

```bash
make install
```

This builds the app, installs it in Applications, and launches it. Read [docs/DESIGN.md](docs/DESIGN.md) and the
macOS 27 field guide in [docs/AGENTS.md](docs/AGENTS.md) before changing anything that creates or sizes a menu bar
item.

## Credits

Barometer is available under the [MIT License](LICENSE). Weather data by [Open-Meteo.com](https://open-meteo.com/)
(CC BY 4.0).
