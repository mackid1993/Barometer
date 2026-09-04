# Barometer: Execution Plan

This is the step-by-step plan for building the app described in `docs/DESIGN.md`. It is written for a coding agent (Codex) working on David's Mac with the Command Line Tools only. Read `AGENTS.md` and `docs/DESIGN.md` first. Section 3.5 of the design (the identity contract) is normative and is repeated in short form in `AGENTS.md`.

## 0. How to work this plan

- Work one phase at a time, in order. Inside a phase, do the tasks in order unless a task says it can run in parallel.
- Every task has "Done when" and "Verify" lines. A task is not finished until every "Verify" command has been run and its output matches. Paste the relevant output into `docs/PROGRESS.md` under the task ID.
- Commit after every task with a message of the form `P1-T3: add CPU monitor`. Never add attribution lines or co-author trailers.
- Stop at the end of each phase and wait for David's review before starting the next one, unless he has said to continue.
- If something in this plan turns out to be wrong on the machine (an API returns nothing, a key does not exist), do not silently work around it. Record what you saw in `docs/PROGRESS.md`, pick the nearest working approach from `docs/DESIGN.md` section 6, and say so in the commit message.
- Never modify iStat Menus, Stats, or Thaw, their preferences, or their launch agents. Do not launch Thaw yourself; ask David to have it running when a verification step needs it.
- Never change the bundle identifier or any autosave name after P0 without an explicit instruction from David.

### Standard verification commands

```sh
swift build                                   # debug build of all targets
swift test                                    # unit tests
make app                                      # release build + dist/Barometer.app
make run                                      # stop any running instance, build, launch
make stop                                     # quit the running app
swift run mbs-probe <source>                  # print a data source
log stream --level debug --predicate 'subsystem == "com.barometer.app"'
defaults read com.stonerl.Thaw | grep -o 'com\.barometer\.app:[^"]*' | sort -u          # Thaw identity check (Thaw must be running)
defaults read com.barometer.app | grep 'NSStatusItem'                             # system position keys
screencapture -x -R0,0,1728,30 dist/menubar.png                                           # menu bar screenshot for visual checks
```

### Definition of done for v1.0

All of Phases 0 through 7 complete, every module from `docs/DESIGN.md` section 4 present with at least two menu bar modes and a dropdown, the Thaw identity check stable across ten relaunches and one hour of running, CPU and memory budgets from design section 11 met, `swift test` green, and `make install` producing a working `/Applications/Barometer.app`.

---

## Phase 0: Repository, build pipeline, first status item

Goal: a signed `.app` that shows one static status item with the correct identity, a Settings window, and Quit. Nothing else.

### P0-T1 Repository and package skeleton

- `git init`, `.gitignore` (`.build/`, `dist/`, `*.xcodeproj`, `.DS_Store`, `.swiftpm/`).
- `Package.swift`: `swift-tools-version: 6.2`, `platforms: [.macOS("26.0")]`, targets exactly as in design section 5.2, `swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]` or the equivalent `-strict-concurrency=complete`, `linkerSettings` linking `IOKit`, `CoreWLAN`, `SystemConfiguration`, `AppKit` on the targets that need them.
- `VERSION` file containing `0.1.0`.
- `LICENSE` (MIT, copyright David Brustein 2026), `README.md` (short, links to docs).
- Empty-but-compiling sources for every target so `swift build` succeeds.
- Done when: `swift build` and `swift test` succeed with zero warnings from our code.
- Verify: `swift build 2>&1 | tail -3`, `swift test 2>&1 | tail -3`, `git log --oneline | head`.

### P0-T2 Bundle assembly and Makefile

- `Scripts/Info.plist` with the keys in design section 10, placeholders `__VERSION__` and `__BUILD__`.
- `Scripts/make-app.sh`: build the `MenuBarStatsApp` product in release, create `dist/Barometer.app`, copy the binary as `Contents/MacOS/Barometer`, substitute the plist, copy any SwiftPM resource bundles (`.build/release/*.bundle`) into `Contents/Resources`, ad-hoc sign with identifier `com.barometer.app`.
- `Makefile` targets: `build`, `test`, `app`, `run`, `stop`, `install`, `probe SRC=cpu`, `clean`. `stop` uses `osascript -e 'quit app id "com.barometer.app"'` with a `pkill -f Barometer.app/Contents/MacOS/Barometer` fallback.
- Done when: `make app` produces a bundle that `codesign -dv` reports with the right identifier and `plutil -p dist/Barometer.app/Contents/Info.plist` shows `LSUIElement => true`.
- Verify: `make app && codesign -dv --verbose=2 dist/Barometer.app 2>&1 | grep -E 'Identifier|Signature'`.

### P0-T3 Application shell

- `main.swift`: create `NSApplication.shared`, set `AppDelegate`, `NSApp.setActivationPolicy(.accessory)`, `NSApp.run()`.
- `AppDelegate`: single-instance guard (design 3.5 rule 10), logging setup, create `StatusItemRegistry`, create the Settings window controller lazily, handle `applicationShouldTerminate`.
- `StatusItemRegistry` (in `MenuBarStatsUI`): owns every `NSStatusItem`. Public API: `item(for: ModuleID) -> NSStatusItem`, `setVisible(_:for:)`. Creates all ten items at launch with the autosave names from the identity table, `button.title = ""`, `setAccessibilityIdentifier`, `setAccessibilityLabel`, no `.removalAllowed`. In P0 only the CPU item is visible and it shows a static rendered image of the text "CPU".
- `ModuleID` enum in `MenuBarStatsCore` with `autosaveName` and `displayName` computed properties. This is the single source of truth for the identity table.
- Identity self-test: in debug builds, one second after launch, log each item's `autosaveName`, `button.window?.title`, AX identifier, AX label, AX title under category `identity`, and `assert` that label and identifier match.
- Menu: the CPU item gets an `NSMenu` with "Settings…" and "Quit Barometer".
- Settings window: `NSWindow` hosting a SwiftUI `SettingsRootView` with a sidebar listing General plus every module (content can be placeholders). Opening it activates the app; closing it does not quit.
- Done when: `make run` shows a "CPU" item, its menu opens, Settings opens and closes, Quit works, and relaunching keeps the item where the user dragged it.
- Verify: `make run`; the accessibility identifier is `Barometer.CPU`; `defaults read com.barometer.app | grep 'NSStatusItem Preferred Position Barometer.CPU'` after dragging the item once; with a menu bar manager running, its identity check prints `com.barometer.app:...` ending in `Barometer.CPU` and nothing else.

### P0-T4 Probe executable and identity probe

- `mbs-probe` target with a tiny argument parser (no dependencies). Subcommands in P0: `identity` (creates a temporary status item named `MenuBarStats.Probe`, prints the same identity lines as the self-test, exits) and `version`.
- Done when: `swift run mbs-probe identity` prints `window.title=MenuBarStats.Probe`.
- Verify: `swift run mbs-probe identity`.

### P0-T5 Unit test for the identity table

- Test in `MenuBarStatsCoreTests` that hard-codes the table from design section 3.5 and asserts `ModuleID.allCases` map to exactly those strings. The point is to make any accidental rename fail loudly.
- Verify: `swift test --filter IdentityContractTests`.

End of Phase 0: stop for review.

---

## Phase 1: Sampling engine, CPU, Memory

Goal: the real architecture with two full modules, including live dropdowns and settings panes.

### P1-T1 Core engine

- `Monitor` protocol, `Scheduler` (per-monitor `Task` loops with `ContinuousClock`, pause and resume, error backoff of 1 s doubling to 60 s), `History<Value>` ring buffer with `append`, `last(_ duration:)`, `downsampled(to:)`, `ModuleStore` (`@MainActor @Observable`), `SampleClock` abstraction for tests.
- `AppSettings` and `ModuleSettings` as `Codable` with `schemaVersion = 1`, `SettingsStore` (`@MainActor @Observable`, saves to `UserDefaults` debounced by 250 ms, publishes changes).
- Power-aware scheduling: `IOPSNotificationCreateRunLoopSource` to detect battery vs AC, `NSWorkspace` sleep and wake notifications to pause and resume.
- Tests: ring buffer, downsampling, scheduler backoff with a fake clock, settings round trip and migration from a fake version 0 blob.
- Verify: `swift test --filter 'History|Scheduler|Settings'`.

### P1-T2 CPU source and monitor

- `SystemSources/CPUSource.swift`: `host_processor_info` wrapper returning per-core tick counts; `CoreTopology` from `hw.perflevel*`; `getloadavg`; boot time.
- `SystemSources/ProcessSource.swift`: `proc_listpids`, `proc_pid_rusage`, names and paths, with a cache keyed by pid and start time.
- `MenuBarStatsCore/Modules/CPU/CPUMonitor.swift` producing `CPUSample` (total, user, system, idle, nice, perCore, loadAverages, uptime, processCount, threadCount, topProcesses).
- `mbs-probe cpu` prints a sample and `mbs-probe cpu --watch` prints one per second.
- Verify: `swift run mbs-probe cpu` shows per-core values that sum sensibly; run `yes > /dev/null &` and confirm one core goes to about 100%, then `kill %1`.

### P1-T3 Memory source and monitor

- `SystemSources/MemorySource.swift`: `host_statistics64`, page size, `hw.memsize`, `kern.memorystatus_level`, `vm.swapusage`, memory pressure `DispatchSource`.
- `MemoryMonitor` producing `MemorySample` (total, used, app, wired, compressed, cached, free, pressurePercent, pressureLevel, swapUsed, swapTotal, topProcesses).
- `mbs-probe memory`.
- Verify: `swift run mbs-probe memory`; compare used and pressure against Activity Monitor within a few percent.

### P1-T4 Menu bar rendering framework

- `MenuBarRenderer` protocol, `RenderContext` (thickness, appearance, palette, font size), `TextRenderer`, `GraphRenderer` (line, area, bars), `StackedLabelRenderer`, `IconTextRenderer`, `CombinedRenderer` scaffold.
- `StatusItemController` per module: observes `ModuleStore` and `SettingsStore`, renders, sets `button.image` and `accessibilityValue`, respects `isVisible`.
- CPU modes: percentage, graph, per-core bars, stacked. Memory modes: used percentage, pressure percentage, graph, bar, stacked.
- Fixed-width text option and monospaced digits.
- Verify: `make run`; `screencapture` the menu bar and confirm the items render in both light and dark appearance (toggle with `osascript -e 'tell app "System Events" to tell appearance preferences to set dark mode to not dark mode'` twice).

### P1-T5 Dropdown framework

- `DropdownController`: builds the `NSMenu`, hosts a SwiftUI root in the first item at 320 pt width, adds standard items, and installs a `.common`-mode timer that ticks the store while the menu is open.
- CPU dropdown: history graph with range picker (1 min, 5 min, 30 min, 3 h, 24 h), per-core bars, load averages, uptime, top processes with icon, name, percentage, and a kill button (confirm with an alert for non-user processes).
- Memory dropdown: breakdown bar, pressure graph, swap, top processes.
- Live update check: open the CPU menu, keep it open for 10 s, confirm the graph advances. If it does not, implement the `NSPanel` fallback described in design section 8 before continuing and record the finding in `docs/PROGRESS.md`.
- Verify: manual, plus `log stream` showing render ticks while the menu is open.

### P1-T6 Settings panes for General, CPU, Memory

- General: launch at login (`SMAppService`), reduce sampling on battery, monochrome mode, font size, export and import settings.
- CPU and Memory: enabled toggle (drives `isVisible`), mode picker with live preview image, interval, graph options, color pickers, dropdown options (show processes, count).
- Verify: toggle CPU off and on, confirm the item hides and returns without the Thaw identity changing (run the Thaw identity check before and after).

### P1-T7 Performance pass

- Measure with `top -l 5 -stats pid,cpu,mem -pid $(pgrep -x MenuBarStats)`; must be under 0.7% CPU average with both modules at 1 s and 2 s intervals.
- Verify: paste the `top` output into `docs/PROGRESS.md`.

End of Phase 1: stop for review.

---

## Phase 2: Weather

Goal: a complete weather module on Open-Meteo, because it matters most to David after the basics.

### P2-T1 Open-Meteo client

- `MenuBarStatsCore/Weather/OpenMeteoClient.swift`: `forecast(for: Location, units: WeatherUnits) async throws -> Forecast`, `geocode(_ query: String) async throws -> [GeocodingResult]`, `airQuality(for:) async throws -> AirQuality`. `URLSession` with 15 s timeout, `User-Agent: MenuBarStats/<version> (https://github.com/...)`.
- Models: `Location` (id, name, admin, country, latitude, longitude, timeZone), `CurrentConditions`, `HourlyPoint`, `DailyPoint`, `Forecast`, `AirQuality`, `WeatherUnits`, `WMOCode` with `symbolName(isDay:)` and `description`.
- Fixture JSON files under `Tests/MenuBarStatsCoreTests/Fixtures/` captured from real responses (fetch once with `curl` and commit).
- Tests: decoding of forecast, geocoding, air quality; WMO mapping table; moon phase for 2000-01-06 (new) and 2000-01-21 (full).
- `mbs-probe weather --lat 42.3601 --lon -71.0589` and `mbs-probe geocode "Boston"`.
- Verify: `swift test --filter Weather`; `swift run mbs-probe weather --lat 42.3601 --lon -71.0589` prints current temperature and a 10-day list.

### P2-T2 Weather monitor and cache

- `WeatherMonitor` per location, 15 min interval, refresh on wake and on network change, exponential backoff, on-disk cache in `~/Library/Application Support/MenuBarStats/weather/`, stale flag.
- Verify: launch, then turn Wi-Fi off and on; the log shows a refresh on reconnect; kill network and confirm the cached forecast still renders with a stale marker after two intervals (shorten intervals with a debug setting).

### P2-T3 Weather settings pane

- Location list with add (search field backed by geocoding, results list, add button), remove, reorder, primary location; "Use current location" toggle that requests Location authorization through `CLLocationManager` and falls back gracefully; units; refresh interval; menu bar template editor with token list and live preview.
- Verify: add two locations, switch the primary, confirm the menu bar item updates.

### P2-T4 Weather menu bar renderer

- Modes from design 4.8. Condition icon uses `NSImage(systemSymbolName:)` tinted for color mode, template for monochrome. Template string renderer.
- Verify: screenshots in both appearances; confirm the AX label stays "Weather" while the value changes (`swift run mbs-probe identity` pattern applied to the running app through the debug identity log).

### P2-T5 Weather dropdown

- Sections from design 4.8: header, hourly strip (48 h) with temperature curve and precipitation bars, daily rows (10 d) with range bars, sun and moon, air quality, details grid, location switcher, Refresh, Open in Weather app (`open -b com.apple.weather`), attribution footer.
- Verify: manual review; dropdown opens in under 100 ms (measure with `log` timestamps).

End of Phase 2: stop for review.

---

## Phase 3: Network and Disks

### P3-T1 Network source

- `NET_RT_IFLIST2` counters, `getifaddrs` addresses, `SCDynamicStore` primary interface, router, DNS, change notifications; CoreWLAN details with the Location-permission fallback; optional public IP.
- `mbs-probe net` and `mbs-probe wifi`.
- Verify: `swift run mbs-probe net --watch` while running `curl -o /dev/null https://speed.cloudflare.com/__down?bytes=100000000` shows download rate climbing.

### P3-T2 Network module

- `NetworkMonitor`, `NetworkSample`, renderer modes (two-line text, graph, arrows, stacked), dropdown (graph, interface picker, addresses with copy, Wi-Fi block, totals), settings (interface selection, units bits vs bytes, public IP opt-in, graph scale auto vs fixed).
- Verify: Thaw identity check still shows a fixed set; totals match `netstat -ib` for the interface.

### P3-T3 Disk source

- Volumes via `FileManager` resource values, mount notifications, `IOBlockStorageDriver` statistics with BSD name mapping.
- `mbs-probe disks`.
- Verify: `swift run mbs-probe disks --watch` while running `dd if=/dev/zero of=/tmp/mbs-test bs=1m count=2000` shows write throughput; delete the file.

### P3-T4 Disk module

- `DiskMonitor`, renderer modes (activity graph, free percentage, free bytes), dropdown (volume bars, activity graph, per-disk rates, eject), settings (volumes to show, hide system volumes, units).
- Verify: plug in or mount a disk image (`hdiutil create -size 100m -fs APFS -volname MBSTest /tmp/mbs.dmg && hdiutil attach /tmp/mbs.dmg`), confirm it appears and can be ejected from the dropdown, then detach and delete the image.

End of Phase 3: stop for review.

---

## Phase 4: Sensors and GPU

### P4-T1 C shim target

- `CSystemSources/include/CSystemSources.h` declaring the private IOKit HID event system client functions, `IOHIDEventGetFloatValue`, the IOReport functions (`IOReportCopyChannelsInGroup`, `IOReportMergeChannels`, `IOReportCreateSubscription`, `IOReportCreateSamples`, `IOReportCreateSamplesDelta`, `IOReportChannelGetGroup`, `IOReportChannelGetSubGroup`, `IOReportChannelGetChannelName`, `IOReportChannelGetUnitLabel`, `IOReportSimpleGetIntegerValue`, `IOReportStateGetCount`, `IOReportStateGetNameForIndex`, `IOReportStateGetResidency`), and the SMC key data structs. Link `IOKit`; IOReport symbols resolve from the shared cache without an explicit library.
- Verify: `swift build` links; `nm .build/debug/mbs-probe | grep -c IOReport` is greater than zero after P4-T3.

### P4-T2 IOHID temperature source

- Port `Tools/probes/temps.swift` into `SystemSources/HIDTemperatureSource.swift` with the C shim, filtering invalid readings, deduplicating names by averaging, and a friendly-name table (`PMU tdie*` -> "SoC die N", `gas gauge battery` -> "Battery", `NAND CH0 temp` -> "SSD", `PMU tcal` -> "PMU").
- `mbs-probe temps`.
- Verify: `swift run mbs-probe temps` lists die temperatures between 25 and 100 °C and no negative values.

### P4-T3 IOReport source

- Subscription to `Energy Model` and `CPU Stats` and `GPU Stats`; sample deltas over the interval; watts computed from energy deltas; frequencies from `pmgr` voltage states; residency-weighted average frequency.
- `mbs-probe power` and `mbs-probe freq`.
- Verify: `swift run mbs-probe power --watch` while running `yes > /dev/null` on a few cores shows CPU power rising; kill the load.

### P4-T4 SMC source

- `SMCClient` with key enumeration, key info cache, typed decoding, fans, and a curated list of power and temperature keys tried at startup and kept only if they answer. Read-only by design: no write selector is exposed.
- `mbs-probe smc --list` and `mbs-probe fans`.
- Verify: `swift run mbs-probe fans` shows RPM for both fans; `swift run mbs-probe smc --list | wc -l` is greater than 100.

### P4-T5 Sensors module

- `SensorsMonitor` merging IOHID, SMC, and IOReport into a `SensorSample` with groups; renderer modes (chosen sensors as text, mini graph, fan RPM); dropdown with grouped sparklines; settings (which sensors in the menu bar, units, show raw names, hide duplicates).
- Verify: Thaw identity check unchanged; the menu bar shows the hottest die and the fan RPM.

### P4-T6 GPU source and module

- `IOAccelerator` `PerformanceStatistics` reader; GPU temperature and power from IOReport where present; `GPUMonitor`, `GPUSample`; renderer modes (percentage, graph, combined with CPU); dropdown; settings.
- `mbs-probe gpu`.
- Verify: `swift run mbs-probe gpu --watch` while a WebGL demo or a 4K video plays shows utilization above 20%.

End of Phase 4: stop for review.

---

## Phase 5: Battery and power

### P5-T1 Battery source

- IOPS summary plus `AppleSmartBattery` details, signed `Amperage` handling, adapter details, low power mode, change notifications.
- `mbs-probe battery`.
- Verify: `swift run mbs-probe battery` shows cycle count 45 or later, health near `FullChargeCapacity / DesignCapacity`, and negative wattage on battery, positive on the charger.

### P5-T2 Battery module

- `BatteryMonitor`, renderer modes (percentage, icon with fill, time remaining, wattage), dropdown (details, health, adapter, charge history graph), settings (show when on AC, low battery threshold color).
- Verify: unplug and replug the charger; the item updates within 2 s.

### P5-T3 Bluetooth device batteries (optional in v1)

- IORegistry scan for `BatteryPercent*` keys and device names; list in the dropdown.
- Verify: with AirPods connected, both bud levels appear.

End of Phase 5: stop for review.

---

## Phase 6: Time

### P6-T1 Time module

- `TimeMonitor` (1 s when seconds are shown, otherwise aligned to the minute), format token engine with live preview, world clocks with `TimeZone` picker and search, week number, day of year, dropdown with month calendar, world clocks list, sunrise and sunset from the primary weather location, settings.
- Verify: change the system time zone; the item follows within a second.

### P6-T2 Calendar events (optional in v1)

- EventKit with `NSCalendarsFullAccessUsageDescription`; next 5 events in the dropdown; graceful state when denied.
- Verify: grant access, see events; deny, see the explanation row.

End of Phase 6: stop for review.

---

## Phase 7: Combined item, appearance, polish

### P7-T1 Combined item

- `Barometer.Combined` item that hosts any subset of modules with separators; tabbed dropdown; settings to choose members and order; members can be shown in Combined and hidden individually.
- Verify: Thaw identity check shows `Barometer.Combined` and the members that are still individually visible; hide members and confirm only Combined remains.

### P7-T2 Appearance system

- Palette per module with light and dark values; monochrome mode; graph style; font size; item spacing; global "compact" toggle; live preview strip in Settings.
- Verify: screenshots in both appearances with all items visible; no clipping at 24 pt thickness.

### P7-T3 About, export and import, launch at login polish

- About pane (version, build, license, Open-Meteo attribution, links); JSON export and import with validation; `SMAppService` status display and a warning when running from `dist/`.
- Verify: export, delete preferences (`defaults delete com.barometer.app`), import, confirm identical layout and settings.

### P7-T4 Stability and performance pass

- Run for one hour with all modules; check `top` and memory growth (must be flat within 5 MB); run the Thaw identity check every 10 minutes and confirm the set never changes; relaunch ten times and confirm positions persist.
- Verify: paste measurements into `docs/PROGRESS.md`.

### P7-T5 Install target and README

- `make install` copies to `/Applications`, re-registers launch at login if it was on, and relaunches. README documents building, installing, permissions, and the identity contract for other developers.
- Verify: `make install && pgrep -x MenuBarStats`.

End of Phase 7: v1.0 tag candidate. Stop for review.

---

## Phase 8: After v1

Only after David asks:

- Alerts with threshold rules and UserNotifications.
- Per-process network usage (private NetworkStatistics framework) and SMART data.
- Sparkle updates, Developer ID signing, notarization, Homebrew cask.
- WeatherKit as an alternative provider once Xcode and a developer account are available.
- Fan control through a privileged helper (separate design review required).

---

## Manual QA checklist (run at the end of every phase)

1. `make run` from a clean `make clean`.
2. All enabled items render in light and dark appearance.
3. Each dropdown opens, updates live for 10 s, and closes.
4. Settings changes apply live and survive a relaunch.
5. `swift test` green.
6. Thaw identity check: same set before and after a relaunch, and after 5 minutes of value changes.
7. `top` CPU for the app under 0.7% average over 5 minutes.
8. `log stream` shows no errors at the `error` level during 5 minutes of normal use.
