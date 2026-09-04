<p align="center">
  <img src="Resources/AppIcon.png" width="160" alt="Barometer app icon">
</p>

<h1 align="center">Barometer</h1>

<p align="center">
  A detailed, beautiful macOS menu bar system monitor built for modern macOS.
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
  <img alt="Swift 6.2" src="https://img.shields.io/badge/Swift-6.2-F05138?style=flat-square&logo=swift&logoColor=white">
  <img alt="DMG releases"
       src="https://img.shields.io/badge/releases-DMG-06B6D4?style=flat-square">
</p>

Barometer is a free, open source alternative to iStat Menus. It combines CPU, GPU, memory, network, disk, sensor,
battery, weather, and time data with dense, configurable menu bar presentations and detailed dropdowns. A Combined
item can consolidate selected monitors when menu bar space is tight.

Every status item is owned by the main application bundle so Bartender and Thaw can identify and manage it correctly
on macOS 27.

## Highlights

- Live CPU and memory monitors with history, per-core detail, pressure, and real application icons
- Detailed automatic-location Weather powered by Open-Meteo, with Fahrenheit and Celsius support
- Stable, individually manageable menu bar identities for Bartender and Thaw
- Independent type and icon/graph sizing, plus precise spacing between movable items
- One app bundle and one process: no anonymous helper owns menu bar items
- Developer ID signed DMG release workflow, with optional notarization only when explicitly selected
- No third-party runtime dependencies

## Install

When releases begin, download `Barometer-VERSION.dmg` from the
[latest release](https://github.com/mackid1993/Barometer/releases/latest), open it, and drag Barometer into
Applications. Releases are distributed as DMGs, not zip archives.

macOS 26 and later may also require Barometer to be enabled under **System Settings → Menu Bar**.

For a local source build, install and relaunch the bundle with:

```bash
make install
```

This replaces `/Applications/Barometer.app`; it does not install a helper or background command-line process.

## Permissions

- **Location** is optional and requested only when automatic Weather location is enabled. Barometer follows location
  changes while a laptop moves and keeps the last forecast available when the network is offline.
- **Calendar** is optional and requested only after selecting **Allow Calendar Access** in Time settings.
- CPU, memory, GPU, network, disks, sensors, and battery monitoring do not request additional privacy permissions.

Denied or unavailable sources remain labeled as unavailable rather than displaying invented values.

## Build from source

Barometer uses Swift Package Manager and does not require an Xcode project:

```bash
swift test
make app
make dmg
```

The app bundle and disk image are written to `dist/`. Local packages are ad hoc signed. GitHub release builds use
Developer ID signing and the hardened runtime. Notarization and stapling are opt-in workflow choices.

## Menu bar manager identity

Every `NSStatusItem` is created and retained by the executable inside `Barometer.app`. Items use permanent
`Barometer.*` autosave names, empty button titles, image-only content, and stable accessibility identifiers. Disabling
an item changes `isVisible`; it is never removed and recreated. Contributors must not move status-item creation into
a helper, XPC service, command-line tool, or second app bundle. This is the contract that lets Bartender and Thaw
associate each item with `com.barometer.app` on macOS 27.

Barometer is available under the [MIT License](LICENSE).
