# Barometer: Design

Status: v1 design, written 2026-09-03. Companion documents: `docs/PLAN.md` (phased execution plan), `docs/CODEX_PROMPT.md` (the prompt that kicks off implementation), `AGENTS.md` (standing rules for coding agents).

## 1. Purpose

Barometer is a free, open source (MIT) macOS app that replaces iStat Menus for one specific user and, secondarily, for anyone else who wants it. It reproduces the iStat Menus feature set (CPU, GPU, memory, disks, network, sensors, battery, weather, time) as a set of menu bar items with rich dropdown panels, and it must behave correctly with third-party menu bar managers on macOS 27, where iStat Menus currently misbehaves.

Weather is a first-class module, not an add-on.

### Non-goals for v1

- Fan speed control (requires a root helper that writes to the SMC).
- SMART disk health (NVMe SMART needs private IOKit interfaces; revisit later).
- Per-process network usage (needs the private NetworkStatistics framework; revisit later).
- Mac App Store distribution (the sensor code uses private APIs).
- Supporting macOS earlier than 26.

## 2. Environment facts (verified on the target machine, 2026-09-03)

| Item | Value |
| --- | --- |
| Machine | MacBook Pro, Apple M4 Pro, 48 GB |
| OS | macOS 27.0 beta, build 26A5425a (Darwin 27.0.0) |
| Toolchain | Command Line Tools only, no Xcode. Swift 6.2.3. SDK at `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk` is version 26.2 |
| Menu bar manager | Thaw 3.0.0-alpha.1 (`com.stonerl.Thaw`, requires macOS 27), open source, fork of Ice |
| Reference apps installed | iStat Menus 7.30, Stats 3.0.14 (`eu.exelban.Stats`) |

Consequences:

- Everything must build with `swift build` from a Swift package. There is no `.xcodeproj`, no `xcodebuild`, and no Xcode-only features (no entitlements, no WeatherKit, no storyboards). The `.app` bundle is assembled by a script.
- The SDK is 26.2, so the code compiles against macOS 26 headers and runs on 27. Do not depend on any macOS 27-only API.
- Ad-hoc code signing only. TCC grants keyed to the signature (Location, Calendars) reset on every rebuild, so those permissions are optional paths, never required paths.

## 3. The macOS 27 menu bar problem and the identity contract

This section is the reason the project exists. Read it before touching any status item code.

### 3.1 What changed in macOS 27

Through macOS 26, every status item was its own window at the status bar level, and menu bar managers enumerated, captured, and moved those windows. In macOS 27 the whole menu bar is one WindowServer window named `Menubar` (plus a `MenuBarAgent` window). Managers were rebuilt around Accessibility (AX) plus the window list. Bartender and Thaw both note that an app with several items is now treated as a group: hide one, hide all.

### 3.2 How Thaw identifies an item

Verified by reading the Thaw source (`thaw-app/Thaw`, `development` branch, and the installed 3.0.0-alpha.1 binary):

- Every item gets a tag `namespace:title[:index]`.
- `namespace` is the bundle identifier of the process that owns the item.
- `title` comes from the item's window name (`kCGWindowName`) on macOS 26, and the macOS 27 engine additionally reads `AXTitle`, `AXDescription`, `AXIdentifier`, and `AXValue` from the extras menu bar via the Accessibility API.
- Thaw persists layout, section membership, and ordering under that string. If the string changes, the item is treated as brand new and lands in the "new items" section.
- Thaw hard-codes a special case for `com.bjango.istatmenus.status`: iStat Menus titles its items with the live value ("CPU 43%", "918 KB/s"), so Thaw rewrites digits to `#` for that bundle only. Thaw's own preferences on this machine contain keys such as `com.bjango.istatmenus.status:CPU #%` and `com.bjango.istatmenus.status:Currently #° and Cloudy. High of #°. Low of #°. #% chance of rain`. Note the weather title: when "Cloudy" changes to "Sunny" the identifier changes and the item is lost. That is the bug the user sees.
- No such special case will exist for this app, so every identity-bearing string must be static.

### 3.3 How iStat Menus is put together, and why it matters

iStat Menus 7.30 is three bundles plus a daemon:

| Bundle | Identifier | Role |
| --- | --- | --- |
| iStat Menus.app | `com.bjango.istatmenus` | Preferences UI, Dock icon |
| iStat Menus Helper.app | `com.bjango.istatmenus.agent` | LaunchAgent (`com.bjango.istatmenus.agent`) |
| iStat Menus Menubar.app | `com.bjango.istatmenus.status` | LaunchAgent (`com.bjango.istatmenus.status`), owns every status item |
| `com.bjango.istatmenus.daemon` | privileged helper in `/Library/PrivilegedHelperTools` | root work (fan control, some sensors) |

All items come from one process, `com.bjango.istatmenus.status`, and that is the only reason they can be managed at all. The user's observation that "every item must have the same helper name" is exactly this: one owning bundle identifier for all items. Barometer goes further and uses one process for everything, with no helper and no daemon.

### 3.4 Verified behavior of NSStatusItem on macOS 27.0

`Tools/probes/statusitem.swift` was run on the target machine. Results:

| Step | `window.title` | AX label | AX title |
| --- | --- | --- | --- |
| Create item, set `autosaveName = "MBSProbeAutosave"` | `MBSProbeAutosave` | empty | empty |
| `button.title = "CPU 42%"` | unchanged | `CPU 42%` | `CPU 42%` |
| `button.title = "CPU 77%"` | unchanged | `CPU 77%` | `CPU 77%` |
| `setAccessibilityLabel("Probe AX Label")` | unchanged | `Probe AX Label` | `CPU 77%` |
| `button.title = ""`, image set | unchanged | `Probe AX Label` | empty |
| `autosaveName = "MBSProbeRenamed"` | `MBSProbeRenamed` | unchanged | empty |

So: the window name is the autosave name and nothing else. The button title flows straight into AX title and, unless overridden, AX label. A live value in `button.title` is a changing identity.

### 3.5 The identity contract (normative)

These rules are part of the public contract of the app. Changing any of them after the first release is a breaking change that scrambles every user's menu bar layout.

1. One process. All status items are created by the main app process. No helper app, no XPC service, no login-item bundle owns a status item.
2. One bundle identifier, forever: `com.barometer.app`. (David: change this before the first launch if you want a different one, never after.)
3. Fixed autosave names, one per module, never renamed:

   | Module | `autosaveName` |
   | --- | --- |
   | CPU | `Barometer.CPU` |
   | GPU | `Barometer.GPU` |
   | Memory | `Barometer.Memory` |
   | Disks | `Barometer.Disks` |
   | Network | `Barometer.Network` |
   | Sensors | `Barometer.Sensors` |
   | Battery | `Barometer.Battery` |
   | Weather | `Barometer.Weather` |
   | Time | `Barometer.Time` |
   | Combined | `Barometer.Combined` |

   Multiple instances of one module (two weather locations, two sensor items) use `Barometer.Weather.2`, `Barometer.Weather.3`, and so on, allocated once and stored in settings so the numbering is stable.
4. `button.title` is always the empty string. All menu bar content is rendered into an `NSImage` and assigned to `button.image`. Text in the menu bar is drawn text, not a title.
5. `button.setAccessibilityIdentifier(autosaveName)` and `button.setAccessibilityLabel(staticHumanName)` where the human name is the module name ("CPU", "Weather"). Both are set once and never changed.
6. The live reading goes into `button.setAccessibilityValue(...)` only. This is what Control Center does for its Battery module, which Thaw identifies as `com.apple.controlcenter:Battery` regardless of the percentage.
7. Never set the status item window's title. Never call `NSWindow.title` on `button.window`.
8. Status items are created once at launch and live for the whole process lifetime. Disabling a module sets `isVisible = false`. It does not remove the item. Enabling sets it back to `true`.
9. `NSStatusItem.behavior` does not include `.removalAllowed`. Visibility is managed from Settings.
10. Only one instance of the app runs. On launch, if another process with the same bundle identifier is running, the new one activates the old one's settings window and exits.
11. Position is left to the system (`NSStatusItem Preferred Position <autosaveName>` in the app's own defaults) and to the menu bar manager. The app never tries to reorder its own items.

### 3.6 Verifying the contract

- `Tools/probes/statusitem.swift` is the reference probe. Re-run it on every new macOS beta.
- Debug builds log each item's `autosaveName`, `window.title`, AX identifier, AX label, and AX title at launch, and assert that the label and identifier match the table above.
- With Thaw running, after the app has been up for a minute:

  ```sh
  defaults read com.stonerl.Thaw | grep -o 'net\.brustein\.MenuBarStats:[^"]*' | sort -u
  ```

  must print exactly one line per visible item, each ending in an autosave name from the table, and the set must not change across app relaunches or value changes.
- `Tools/probes/windows.swift` lists status bar layer windows and is useful for seeing what the window server exposes.

## 4. Product scope: module by module

Parity target is iStat Menus 7. Each module has a menu bar representation (several selectable modes), a dropdown panel, and a settings pane.

### 4.1 CPU

- Metrics: total usage split into user, system, idle (and nice); per-core usage with performance and efficiency cores labeled; 1, 5, 15 minute load averages; uptime; process count and thread count; CPU frequency per cluster (IOReport); CPU package power (IOReport); top 5 processes by CPU with icons.
- Menu bar modes: percentage text, history graph (line or bars), per-core bar graph, stacked label plus value, icon plus text.
- Dropdown: large history graph (selectable window: 1 min to 24 h), per-core bars, load averages, uptime, top processes with kill button (SIGTERM via `kill`), frequency and power when available.

### 4.2 GPU

- Metrics: device utilization, renderer utilization, tiler utilization, GPU memory in use and allocated, GPU frequency and power and temperature when IOReport provides them.
- Menu bar modes: percentage, history graph, combined with CPU.
- Dropdown: history graph, memory, frequency, temperature, power.

### 4.3 Memory

- Metrics: physical size; used, app, wired, compressed, cached files, free; memory pressure percentage and level (normal, warning, critical); swap used and total; top 5 processes by memory footprint.
- Menu bar modes: used percentage or pressure percentage, history graph, bar (used vs total), stacked label.
- Dropdown: breakdown bar in Activity Monitor style, pressure graph, swap, top processes.

### 4.4 Disks

- Metrics per volume: name, mount point, total, used, free, percentage, internal or external or network, ejectable. Per physical disk: read and write throughput, operations per second, cumulative bytes since boot.
- Menu bar modes: activity graph (read up, write down), free space percentage or bytes, text with arrows.
- Dropdown: volume list with usage bars, activity graph, per-disk rates, eject buttons for removable volumes.

### 4.5 Network

- Metrics: upload and download rate on the primary interface and per interface; totals since boot and session; local IPv4 and IPv6; router; DNS servers; public IP (optional, off by default); Wi-Fi SSID, BSSID, RSSI, noise, channel, band, transmit rate, security; VPN interfaces (`utun*`) flagged.
- Menu bar modes: two-line up/down text, activity graph, arrows with rates, stacked label.
- Dropdown: throughput graph, interface picker, addresses, Wi-Fi details, copy-to-clipboard for addresses.

### 4.6 Sensors

- Metrics: every temperature sensor exposed by IOHID (die temperatures, battery, NAND, PMU calibration), SMC temperatures, fans (RPM, min, max, target), power rails (CPU, GPU, ANE, system total, adapter), voltages and currents where the SMC exposes them. Raw sensor names are mapped to friendly labels through a table; unknown names are shown raw.
- Menu bar modes: one or more chosen sensors as text, a mini graph, a fan RPM readout.
- Dropdown: grouped list (temperatures, fans, power, voltage, current) with sparkline per sensor, hottest sensor summary.
- Read-only. No fan control.

### 4.7 Battery and power

- Metrics: charge percentage, state (charging, discharging, full, on AC), time remaining or time to full, health (full charge capacity over design capacity), cycle count, temperature, voltage, amperage, wattage in or out, adapter name and wattage, battery condition, low power mode; Bluetooth device batteries (AirPods, keyboard, mouse, trackpad) when available.
- Menu bar modes: percentage, icon with fill, time remaining, wattage.
- Dropdown: details, health, adapter, Bluetooth devices, charge history graph.

### 4.8 Weather

- Provider: Open-Meteo, no API key, free for non-commercial use, CC BY 4.0 data license. Attribution "Weather data by Open-Meteo.com" appears in the dropdown footer and in About.
- Locations: one or more saved locations, each entered by search (Open-Meteo geocoding API) or by coordinates. Optional "current location" via CoreLocation; because ad-hoc signing resets the Location grant, the default is a saved location.
- Metrics: current temperature, apparent temperature, condition code and description, day or night, humidity, dew point, wind speed, gusts, direction, pressure, cloud cover, visibility, UV index, precipitation and probability; hourly forecast for 48 hours; daily forecast for 10 days with high, low, condition, precipitation probability and sum, sunrise, sunset, UV max; air quality (US AQI, PM2.5) from the Open-Meteo air quality API; moon phase computed locally.
- Units: temperature (°F or °C), wind (mph, km/h, m/s, kn), pressure (inHg, hPa, mmHg), precipitation (in, mm), independent of locale with locale-based defaults.
- Menu bar modes: temperature only, icon plus temperature, icon plus temperature plus condition text, high/low, precipitation probability, custom template string built from tokens (`{temp}`, `{cond}`, `{hi}`, `{lo}`, `{pop}`, `{wind}`, `{aqi}`).
- Dropdown: current conditions header, hourly strip with temperature curve and precipitation bars, daily rows with temperature ranges, sun and moon, air quality, details grid, location switcher, "Open in Weather app" and "Refresh" actions, attribution.
- Refresh: every 15 minutes by default (configurable 5 to 60), immediately on wake and on network change, exponential backoff on failure, last successful response cached on disk and shown with a "stale" marker when older than two refresh intervals.

### 4.9 Time

- Menu bar modes: custom date and time formats built from tokens, seconds toggle, week number, day of year, multiple world clocks as text.
- Dropdown: month calendar with today highlighted, world clocks list with UTC offsets and day/night, sunrise and sunset for the primary weather location, upcoming calendar events (EventKit, optional permission).

### 4.10 Combined item

- One status item that shows any subset of modules side by side with separators. Uses the `Barometer.Combined` autosave name. The dropdown shows tabs or stacked sections for the included modules.

### 4.11 Global

- Launch at login (`SMAppService.mainApp`).
- Per-module update intervals; global "pause while on battery" multiplier; automatic pause during display sleep.
- Colors: a palette per module with light and dark variants; graph style (line, area, bars); graph width; text font size; monochrome (template) mode.
- Settings export and import as JSON.
- Alerts (later phase): threshold rules such as "CPU above 90% for 60 s" delivered through UserNotifications.
- About window with version, attribution, license, and links.

## 5. Architecture

### 5.1 Process model

One `LSUIElement` application, `Barometer.app`, with no Dock icon. It owns all status items, all dropdown menus, the Settings window, and all sampling. Opening Settings calls `NSApp.activate()` so the window comes to the front; closing it returns to accessory behavior. No helper, no daemon, no XPC, no privileged operations.

### 5.2 Swift package layout

```
MenuBarStats/
  Package.swift                      swift-tools-version 6.2, platforms macOS "26.0", zero third-party dependencies
  AGENTS.md                          rules for coding agents
  README.md
  LICENSE                            MIT
  docs/DESIGN.md  docs/PLAN.md  docs/CODEX_PROMPT.md
  Makefile                           build, app, run, test, clean, probe targets
  Scripts/make-app.sh                assembles Barometer.app from the built binary
  Scripts/Info.plist                 bundle metadata (LSUIElement, bundle ID, usage descriptions)
  Resources/                         asset catalogs are not available without Xcode; use PNG/PDF files and SF Symbols
  Sources/
    CSystemSources/                  C target: headers for private symbols (IOHIDEventSystemClient, IOReport, SMC structs)
      include/CSystemSources.h
      shim.c
    SystemSources/                   Swift wrappers over Mach, sysctl, IOKit, libproc, CoreWLAN, IOPS, IOHID, IOReport, SMC
    MenuBarStatsCore/                Monitors, samples, history buffers, formatting, settings model, weather client. No AppKit.
    MenuBarStatsUI/                  AppKit + SwiftUI: status item controllers, renderers, dropdown views, settings window
    MenuBarStatsApp/                 main.swift, AppDelegate, wiring
    mbs-probe/                       CLI executable that prints any data source, used for verification and debugging
  Tests/
    MenuBarStatsCoreTests/           pure logic tests (swift test)
    SystemSourcesTests/              smoke tests that run on the dev Mac (skipped when a source is unavailable)
  Tools/probes/                      standalone swiftc scripts kept for OS-upgrade checks
```

Targets and dependencies: `MenuBarStatsApp` depends on `MenuBarStatsUI`, which depends on `MenuBarStatsCore`, which depends on `SystemSources`, which depends on `CSystemSources`. `mbs-probe` depends on `MenuBarStatsCore` only. Nothing below `MenuBarStatsUI` imports AppKit or SwiftUI.

### 5.3 Data flow

```
SystemSources (sync, blocking C calls)
    -> Monitor actors (one per module, sample on their own schedule)
    -> Sample structs (Sendable, value types, timestamped)
    -> ModuleStore (@MainActor @Observable: latest sample + History ring buffers)
    -> StatusItemController (renders NSImage, updates accessibilityValue)
    -> DropdownController (SwiftUI views hosted in NSMenu items, observe the store)
    -> Settings (SwiftUI, writes AppSettings; stores react to changes)
```

- `Monitor` protocol: `associatedtype Sample: Sendable`, `func sample() async throws -> Sample`, `var interval: Duration`, `var isAvailable: Bool`. Each monitor is an actor. A `Scheduler` runs each monitor on a `Task` loop with `ContinuousClock`, catches errors, and applies backoff.
- `History<T>`: fixed-capacity ring buffer of `(Date, T)` with downsampling helpers, used for graphs. Capacities are set by the longest graph window (24 h at the module's interval, capped at 8,640 points).
- All UI mutation is on the main actor. Samples are delivered with `AsyncStream` per monitor and consumed by a main-actor `ModuleStore`.
- Strict concurrency is on (`-strict-concurrency=complete`, Swift 6 language mode).

### 5.4 Timing defaults

| Module | Interval | Notes |
| --- | --- | --- |
| CPU | 1 s | Process list every 3 s |
| GPU | 1 s | |
| Memory | 2 s | Process list every 5 s |
| Disks | 2 s | Volume list every 30 s and on mount/unmount notification |
| Network | 1 s | Addresses every 10 s and on `SCDynamicStore` change |
| Sensors | 3 s | IOHID and SMC reads are cheap but plentiful |
| Battery | 10 s | Also on `IOPSNotificationCreateRunLoopSource` events |
| Weather | 15 min | Plus wake and network change |
| Time | 1 s or 60 s | 1 s only when seconds are displayed |

All intervals double while on battery if "reduce sampling on battery" is on (default on). Sampling pauses on `NSWorkspace.screensDidSleepNotification` and resumes on wake.

## 6. Data sources

Every source below has been checked on the target machine unless marked "expected". Each lives in `SystemSources` behind a small Swift type with an `isAvailable` check so the app degrades gracefully.

### 6.1 CPU

- Usage: `host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, ...)` returns per-core tick counts for user, system, idle, nice. Keep the previous sample and compute deltas. Free the buffer with `vm_deallocate`.
- Core layout: `sysctlbyname("hw.perflevel0.logicalcpu")` (performance) and `"hw.perflevel1.logicalcpu"` (efficiency); `hw.perflevel0.name` gives the label. On Apple Silicon the efficiency cores are the lowest-numbered logical CPUs.
- Load average: `getloadavg`. Uptime: `sysctl kern.boottime`.
- Frequency and power (expected, from macmon and asitop): IOReport. Subscribe to group `CPU Stats`, subgroup `CPU Core Performance States` (channels `ECPU`, `PCPU`, per-core variants) for state residency, and group `Energy Model` (channels `CPU Energy`, `GPU Energy`, `ANE Energy`, in nJ or mJ per sample delta). Frequency values for each performance state come from the IORegistry `pmgr` node (`voltage-states1-sram` for efficiency cores, `voltage-states5-sram` for performance cores, `voltage-states9` for GPU). Treat as optional.
- Processes: `proc_listpids(PROC_ALL_PIDS)`, `proc_pid_rusage(pid, RUSAGE_INFO_V4)` for `ri_user_time`, `ri_system_time`, `ri_phys_footprint`; `proc_name` and `proc_pidpath` for names; `NSRunningApplication(processIdentifier:)` for icons where the pid is an app. CPU percent is the delta of (user + system) nanoseconds over wall time, divided by core count when showing "of all cores".

### 6.2 GPU

- Utilization and memory: IORegistry, class `IOAccelerator` (`AGXAccelerator` on Apple Silicon), property `PerformanceStatistics`. Verified keys on this machine: `Device Utilization %`, `Renderer Utilization %`, `Tiler Utilization %`, `In use system memory`, `Alloc system memory`, `In use system memory (driver)`.
- Temperature and power (expected): IOReport groups exposed in the accelerator's `IOReportLegend`: `GPU Stats` with channels such as `Tg1a Latest`, and `Energy Model` with `GPU Energy`. Scaling needs to be established with `mbs-probe`.
- Frequency (expected): IOReport `GPU Stats` / `GPU Performance States` residency with frequencies from `pmgr` `voltage-states9`.

### 6.3 Memory

- `host_statistics64(HOST_VM_INFO64)` -> `vm_statistics64`. Page size from `vm_kernel_page_size` (16 KB on Apple Silicon). Total from `sysctl hw.memsize`.
- Definitions matching Activity Monitor: app memory = `internal_page_count - purgeable_count`; wired = `wire_count`; compressed = `compressor_page_count`; cached files = `external_page_count + purgeable_count`; used = app + wired + compressed; free = total - used.
- Pressure percentage: `sysctlbyname("kern.memorystatus_level")` gives the free level; pressure = 100 - level. Pressure state: `DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical])`.
- Swap: `sysctlbyname("vm.swapusage")` -> `xsw_usage` (`xsu_total`, `xsu_used`).
- Processes: as in CPU, sorted by `ri_phys_footprint`.

### 6.4 Disks

- Volumes: `FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys:options: [.skipHiddenVolumes])` with keys `volumeName`, `volumeTotalCapacity`, `volumeAvailableCapacityForImportantUsage`, `volumeIsInternal`, `volumeIsRemovable`, `volumeIsEjectable`, `volumeIsLocal`, `volumeUUIDString`. Mount changes via `NSWorkspace` `didMountNotification` and `didUnmountNotification`.
- Activity: IORegistry, iterate services of class `IOBlockStorageDriver`, read the `Statistics` dictionary (verified keys `Bytes (Read)`, `Bytes (Write)`, `Operations (Read)`, `Operations (Write)`, `Total Time (Read)`, `Total Time (Write)`, `Latency Time (Read)`, `Latency Time (Write)`). Find the BSD name by walking to the child `IOMedia` and reading `BSD Name`. Rates are deltas per interval. Verified: the internal drive reports 693 GB read since boot.
- Eject: `NSWorkspace.shared.unmountAndEjectDevice(at:)`.

### 6.5 Network

- Byte counters: `sysctl` with `CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0` and walk `if_msghdr2` records. Use this rather than `getifaddrs`, whose `if_data` counters are 32-bit and wrap. Per interface: `ifi_ibytes`, `ifi_obytes`, `ifi_ipackets`, `ifi_opackets`.
- Interface names and addresses: `getifaddrs` (AF_INET, AF_INET6). Primary interface: `SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4")` key `PrimaryInterface`, with a fallback to `route -n get default` parsing in the probe tool only. Verified primary interface: `en0`.
- Router and DNS: `State:/Network/Global/IPv4` `Router`, `State:/Network/Global/DNS` `ServerAddresses`.
- Change notifications: `SCDynamicStoreSetNotificationKeys` on `State:/Network/Global/IPv4` and `State:/Network/Interface/.*/Link`.
- Wi-Fi: CoreWLAN `CWWiFiClient.shared().interface()`: `ssid()` and `bssid()` require Location authorization on macOS 14 and later, otherwise nil; `rssiValue()`, `noiseMeasurement()`, `transmitRate()`, `wlanChannel()` (`channelNumber`, `channelBand`, `channelWidth`), `security()`, `interfaceMode()`, `activePHYMode()`. When SSID is unavailable, show "Wi-Fi (name requires Location access)" with a button to request it.
- Public IP: opt-in only. `https://api.ipify.org?format=json` and `https://api64.ipify.org?format=json`, refreshed every 15 minutes and on network change.

### 6.6 Sensors

- Temperatures (verified, no root): IOHIDEventSystemClient from IOKit. Create with `IOHIDEventSystemClientCreate`, set matching `{"PrimaryUsagePage": 0xff00, "PrimaryUsage": 5}`, copy services, read `Product` for the name, `IOHIDServiceClientCopyEvent(service, kIOHIDEventTypeTemperature = 15, 0, 0)` and `IOHIDEventGetFloatValue(event, 15 << 16)`. On this machine that yields 77 services. Names seen: `PMU tdie1` through `PMU tdie14` (SoC die sensors, several duplicated), `PMU tcal`, `gas gauge battery`, `NAND CH0 temp`, and `PMU tdev1` through `PMU tdev8` which return about -9201 and must be discarded (drop anything below -40 or above 150). Duplicate names are averaged, or kept separately with a suffix in the raw view. The reference implementation is `Tools/probes/temps.swift`.
- SMC (expected, proven by Stats 3.0.14 on this machine): `IOServiceMatching("AppleSMC")` matches the `AppleSMCKeysEndpoint` service; `IOServiceOpen`, then `IOConnectCallStructMethod` with selector 2 (`kSMCHandleYPCEvent`), using an 80-byte `SMCKeyData_t` with `data8 = 9` (`kSMCGetKeyInfo`) followed by `data8 = 5` (`kSMCReadKey`). Data types to decode: `flt ` (Float32 little-endian, used for almost everything on Apple Silicon), `ui8 `, `ui16`, `ui32`, `sp78`, `fpe2`, `ioft`. Keys: fans `FNum`, `F0Ac` (actual RPM), `F0Mn`, `F0Mx`, `F0Tg`, `F0Md`; system power `PSTR`; adapter power `PDTR`; battery charge power `PPBR`; temperatures on Apple Silicon use the `Tp..`, `Tg..`, `Ts..`, `TB..` families whose exact set varies per chip. Enumerate all keys through `#KEY` (count) and `SMCGetKeyInfo` by index to build the table at runtime instead of hard-coding. Stats (MIT) `Modules/Sensors/values.swift` is a reference for friendly names.
- Power (expected): IOReport `Energy Model` group as in 6.1, converted to watts by dividing the delta by the elapsed seconds.

### 6.7 Battery

- Summary: `IOPSCopyPowerSourcesInfo`, `IOPSCopyPowerSourcesList`, `IOPSGetPowerSourceDescription` for `kIOPSCurrentCapacityKey`, `kIOPSMaxCapacityKey`, `kIOPSIsChargingKey`, `kIOPSPowerSourceStateKey`, `kIOPSTimeToEmptyKey`, `kIOPSTimeToFullChargeKey`, `kIOPSBatteryHealthKey`. Change events from `IOPSNotificationCreateRunLoopSource`.
- Detail (verified): IORegistry class `AppleSmartBattery`. Keys present on this machine: `CycleCount` (45), `Voltage` (mV), `Amperage` (mA, stored as an unsigned 64-bit value that must be reinterpreted as signed; -558 while discharging), `IsCharging`, `ChargerData` (`NotChargingReason`, `IsCharging`), `BatteryData` (`FullChargeCapacity`, `NominalChargeCapacity`, `AvgTimeToEmpty`, `RemainingCapacity`, `AbsoluteCapacity`), `DesignCapacity`, `Temperature`, `AdapterDetails` (`Watts`, `Name`, `Description`), `ExternalConnected`, `AppleRawCurrentCapacity`, `AppleRawMaxCapacity`. Health = `FullChargeCapacity / DesignCapacity`. Wattage = `Voltage * Amperage / 1e6`.
- Low power mode: `ProcessInfo.processInfo.isLowPowerModeEnabled` and its notification.
- Bluetooth devices (expected, later phase): IORegistry entries with `BatteryPercent`, `BatteryPercentLeft`, `BatteryPercentRight`, `BatteryPercentCase`, and `Product` under `IOBluetoothDevice` and `AppleDeviceManagementHIDEventService`; also `IOBluetooth` framework paired devices for names.

### 6.8 Weather (network)

- Forecast: `GET https://api.open-meteo.com/v1/forecast` with `latitude`, `longitude`, `timezone=auto`, `forecast_days=10`, `temperature_unit`, `wind_speed_unit`, `precipitation_unit`, and:
  - `current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,rain,showers,snowfall,weather_code,cloud_cover,pressure_msl,surface_pressure,wind_speed_10m,wind_direction_10m,wind_gusts_10m`
  - `hourly=temperature_2m,apparent_temperature,precipitation_probability,precipitation,weather_code,wind_speed_10m,wind_direction_10m,uv_index,is_day,relative_humidity_2m,dew_point_2m,visibility,cloud_cover`
  - `daily=weather_code,temperature_2m_max,temperature_2m_min,apparent_temperature_max,apparent_temperature_min,sunrise,sunset,uv_index_max,precipitation_sum,precipitation_probability_max,wind_speed_10m_max,wind_gusts_10m_max`
  Confirm the exact variable names against the Open-Meteo docs at implementation time; the API rejects unknown names with a 400 and a message, which the client surfaces in the log.
- Geocoding: `GET https://geocoding-api.open-meteo.com/v1/search?name=<query>&count=10&language=en&format=json` returns `results[]` with `name`, `latitude`, `longitude`, `country`, `admin1`, `timezone`, `population`.
- Air quality: `GET https://air-quality-api.open-meteo.com/v1/air-quality?latitude=..&longitude=..&current=us_aqi,pm2_5,pm10,ozone`.
- Weather codes are WMO codes. Mapping to SF Symbols: 0 `sun.max` / `moon.stars`; 1 and 2 `cloud.sun` / `cloud.moon`; 3 `cloud`; 45 and 48 `cloud.fog`; 51 to 57 `cloud.drizzle`; 61 to 65 `cloud.rain` (65 `cloud.heavyrain`); 66 and 67 `cloud.sleet`; 71 to 77 `cloud.snow`; 80 to 82 `cloud.heavyrain`; 85 and 86 `cloud.snow`; 95 `cloud.bolt`; 96 and 99 `cloud.bolt.rain`.
- Moon phase: local computation from the synodic month (29.530588853 days) relative to a known new moon epoch (2000-01-06 18:14 UTC), mapped to eight phase names and symbols.
- Networking: `URLSession` with a 15 s timeout, `If-None-Match` not needed, gzip is automatic. Rate budget is far below the 10,000 calls per day limit even with several locations.
- Cache: last successful forecast per location stored as JSON in `~/Library/Application Support/MenuBarStats/weather/<locationID>.json`.

### 6.9 Time

- `Calendar`, `TimeZone`, `DateFormatter` with cached formatters; sunrise and sunset from the weather daily data; EventKit `EKEventStore` (optional, with `NSCalendarsFullAccessUsageDescription`) for events.

## 7. Menu bar rendering

- Every module has a `MenuBarRenderer` that produces an `NSImage` for the current `Sample`, `History`, and `MenuBarStyle`. Rendering uses `NSImage(size:flipped:drawingHandler:)` so it is resolution independent.
- Height is `NSStatusBar.system.thickness` (24 on notch Macs, 22 elsewhere). Content is vertically centered with 1 pt padding.
- Text uses `NSFont.monospacedDigitSystemFont(ofSize:weight:)` so values do not jitter. Fixed-width modes reserve the width of the widest plausible value ("100%", "999 KB/s") so the menu bar does not reflow every second.
- Monochrome mode produces template images (`isTemplate = true`) that adapt to the menu bar appearance, including the transparent macOS 26 and 27 menu bar. Color mode draws explicit colors from the module palette and is not a template image.
- Graph modes: line, filled area, and bars. History window for the menu bar graph is configurable (30 s to 10 min). Graph width is configurable (24 to 96 pt).
- Stacked label mode draws two lines (label above value) at a smaller font, mirroring iStat Menus 7.
- Combined mode concatenates renderers with a 6 pt gap and a 1 pt separator line.
- After each render: `button.image = image`, `button.setAccessibilityValue(text)`. Never touch `button.title`.
- Rendering runs on the main actor and must stay under 1 ms per item. Cache fonts, attributed string attributes, and paths.

## 8. Dropdown menus

- Each status item has an `NSMenu`. The first item is a custom view (`NSMenuItem.view = NSHostingView(rootView:)`) with a fixed width of 320 pt, matching iStat Menus. Below it come standard items: "Settings…", per-module actions, and "Quit Barometer".
- The hosted SwiftUI view observes the module store. Live updates while the menu is open are driven by a `Timer` scheduled on `RunLoop.main` in `.common` modes, because menu tracking runs in `NSEventTrackingRunLoopMode`. Phase 1 includes a check that samples continue to flow while the menu is open; if they do not, the fallback is an `NSPanel` shown under the item.
- Menu bar managers open menus by sending an AX press to the item, so `NSMenu` attached to the status item is the most compatible choice. `NSPopover` is not used for the primary dropdown.
- Graphs in dropdowns are SwiftUI `Canvas` views drawing from `History`, with a time-range picker.
- Hover highlighting for process rows and click actions (kill, copy, eject) are handled in SwiftUI. Menus close on a click outside as usual.

## 9. Settings and persistence

- `AppSettings` is a versioned `Codable` struct (`schemaVersion`) stored as JSON data in `UserDefaults.standard` under one key, with a migration chain. The bundle identifier `com.barometer.app` fixes the preferences domain, and `NSStatusItem` position keys live in the same domain.
- Each module has a `ModuleSettings` struct: enabled, menu bar mode, interval, colors, graph options, dropdown options, and module-specific fields (weather locations and units, sensor selection, time formats).
- Changes are applied live. The settings window is SwiftUI (`NSWindow` hosting a `TabView` or sidebar with one pane per module plus General, Appearance, and About).
- Export and import: JSON file via `NSSavePanel` and `NSOpenPanel`.

## 10. Build, packaging, signing, permissions

- `swift build -c release` produces `.build/release/MenuBarStatsApp`. `Scripts/make-app.sh` creates `dist/Barometer.app/Contents/{MacOS,Resources}`, copies the binary as `Barometer`, writes `Info.plist` with version substitution, copies resources, and runs `codesign --force --sign - --identifier com.barometer.app dist/Barometer.app`.
- `Info.plist` keys: `CFBundleIdentifier`, `CFBundleName`, `CFBundleDisplayName`, `CFBundleExecutable`, `CFBundlePackageType=APPL`, `CFBundleShortVersionString`, `CFBundleVersion`, `LSMinimumSystemVersion=26.0`, `LSUIElement=true`, `NSHumanReadableCopyright`, `NSLocationUsageDescription`, `NSCalendarsFullAccessUsageDescription`, `NSSupportsAutomaticTermination=false`, `NSSupportsSuddenTermination=false`.
- `make run` kills any running instance, rebuilds, and opens the app with `open dist/Barometer.app`. `make install` copies to `/Applications`.
- Launch at login uses `SMAppService.mainApp.register()`; it requires the app to be in a stable location, so Settings warns when running from `dist/`.
- Permissions that may be requested, all optional: Location (Wi-Fi SSID, current-location weather), Calendars (Time module events). Accessibility and Screen Recording are never needed.
- Later: Developer ID signing and notarization, Sparkle updates, and a Homebrew cask. Not part of v1.

## 11. Logging, diagnostics, performance

- `os.Logger` with subsystem `com.barometer.app` and one category per module plus `identity`, `scheduler`, `render`, `weather`. Stream with `log stream --level debug --predicate 'subsystem == "com.barometer.app"'`.
- `mbs-probe` prints any source as text or JSON: `mbs-probe cpu`, `mbs-probe temps`, `mbs-probe smc --list`, `mbs-probe gpu`, `mbs-probe battery`, `mbs-probe disks`, `mbs-probe net`, `mbs-probe weather --lat 42.36 --lon -71.06`, `mbs-probe identity` (launches a temporary status item and prints its identity strings).
- Budgets on the M4 Pro with all modules enabled at default intervals: under 0.7% average CPU measured over five minutes with `top -pid`, under 80 MB resident, zero energy impact rating of "High" in Activity Monitor. Sampling threads must not spin; the scheduler sleeps between samples.

## 12. Testing

- Unit tests (`swift test`) for: ring buffer, rate computation from counters including wraparound, byte and rate formatting, weather JSON decoding against fixture files, WMO code mapping, moon phase for known dates, settings migration, menu bar template string parsing, and the identity constants (a test asserts the autosave table in this document matches the code).
- Source smoke tests run only on macOS and skip when a source reports unavailable: IOHID returns at least one temperature between 0 and 120, GPU statistics dictionary contains `Device Utilization %`, block storage statistics present, battery present on laptops.
- Manual checklist per phase in `docs/PLAN.md`, including the Thaw identity check from section 3.6.

## 13. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Private APIs (IOHID event client, IOReport, SMC user client) change in a macOS update | Each source has `isAvailable`, a unit-independent decoder, and the UI shows "unavailable" rather than crashing. `mbs-probe` makes regressions visible in one command. |
| macOS 27 is a beta and the SDK is 26.2 | No 27-only API. Probes in `Tools/probes` are re-run on each beta. |
| Thaw or Bartender change how identity is derived | The contract keeps every AX and window string static, which is the safest possible position regardless of which string a manager picks. |
| SwiftUI inside `NSMenu` misbehaves (no live updates, hover glitches) | Phase 1 validates it early; `NSPanel` fallback is designed in. |
| Ad-hoc signing resets TCC grants on rebuild | Location and Calendars are optional; weather defaults to saved locations. |
| Menu bar width jitter | Fixed-width text modes and monospaced digits. |
| Open-Meteo outage | Cached last response, stale marker, backoff. |

## 14. Decisions log

| Decision | Choice | Alternatives rejected |
| --- | --- | --- |
| Language and UI | Swift 6.2, AppKit for status items and menus, SwiftUI for panel and settings content | Pure SwiftUI `MenuBarExtra` (cannot set autosave names or accessibility per item reliably, and its window style is not an `NSMenu`) |
| Build system | SwiftPM plus a bundle script | Xcode project (not installed) |
| Dependencies | None | Sparkle, charts libraries (add later if wanted) |
| Minimum macOS | 26.0 | 15 (would need feature flags for glass and menu bar changes) |
| Process model | Single process | iStat-style helper and daemon (source of the identity problem, and root is unnecessary for reading) |
| Weather provider | Open-Meteo | WeatherKit (paid developer account, entitlement, Xcode), OpenWeatherMap (API key) |
| Weather location default | Saved location via geocoding search | CoreLocation (TCC resets with ad-hoc signing) |
| Temperature source | IOHID first, SMC second | SMC only (fewer sensors on Apple Silicon) |
| Dropdown container | `NSMenu` with hosted views | `NSPopover`, custom panel |
| License | MIT | GPL (Thaw and Ice are GPL; do not copy their code) |

## 15. Open questions for David

1. Bundle identifier: `com.barometer.app` is the default. Confirm or change before the first launch.
2. Default temperature unit: °F is assumed.
3. Should the Weather module also offer WeatherKit as an optional provider once Xcode and a developer account are available? The provider protocol allows it; it is not planned for v1.
4. Alerts and notifications are scheduled for a late phase. Say so if they should move earlier.
