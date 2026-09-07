# Barometer: Execution Plan

Current implementation status: Phases 0 through 7 are implemented. The release candidate is ready for David's UI
review. The one-hour soak and notarization submission were explicitly skipped; release tooling keeps notarization
off unless a future manual dispatch enables it.

This is the step-by-step plan for building the app described in `docs/DESIGN.md`. It is written for a coding agent
working on David's Mac with the Swift 6.4 command-line toolchain from Xcode 27. Read `AGENTS.md` and `docs/DESIGN.md`
first. Section 3.5 of the design (the identity contract) is normative and is repeated in short form in `AGENTS.md`.

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

All of Phases 0 through 7 complete, every module from `docs/DESIGN.md` section 4 present with at least two menu bar
modes and a dropdown, the status-item identity set stable across ten relaunches, `swift test` green, and `make
install` producing a working `/Applications/Barometer.app`. The workflow must produce a Developer ID-signed,
hardened-runtime DMG; Gatekeeper, notarization, and stapling checks apply only when notarization is explicitly enabled.

---

## Phase 0: Repository, build pipeline, first status item

Goal: a signed `.app` that shows one static status item with the correct identity, a Settings window, and Quit. Nothing else.

### P0-T1 Repository and package skeleton

- `git init`, `.gitignore` (`.build/`, `dist/`, `*.xcodeproj`, `.DS_Store`, `.swiftpm/`).
- `Package.swift`: `swift-tools-version: 6.4`, `platforms: [.macOS("26.0")]`, targets exactly as in design section 5.2, `swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]` or the equivalent `-strict-concurrency=complete`, `linkerSettings` linking `IOKit`, `CoreWLAN`, `SystemConfiguration`, `AppKit` on the targets that need them.
- `VERSION` file containing `0.1.0`.
- `LICENSE` (MIT, copyright David Brustein 2026), `README.md` (short, links to docs).
- Empty-but-compiling sources for every target so `swift build` succeeds.
- Done when: `make build` and `make test` succeed with zero warnings from our code.
- Verify: `make build 2>&1 | tail -3`, `make test 2>&1 | tail -3`, `git log --oneline | head`.

### P0-T2 Bundle assembly and Makefile

- `Scripts/Info.plist` with the keys in design section 10, placeholders `__VERSION__` and `__BUILD__`.
- `Scripts/make-app.sh`: build the `Barometer` product in release, create `dist/Barometer.app`, copy the `Barometer`
  binary as `Contents/MacOS/Barometer`, substitute the plist, and copy any SwiftPM resource bundles
  (`.build/release/*.bundle`) into `Contents/Resources`. Sign with an explicit or locally discovered Developer ID
  Application identity when available, with an ad-hoc fallback, and preserve identifier `com.barometer.app`.
- `Makefile` targets: `build`, `test`, `app`, `run`, `stop`, `install`, `probe SRC=cpu`, `clean`. `stop` uses `osascript -e 'quit app id "com.barometer.app"'` with a `pkill -f Barometer.app/Contents/MacOS/Barometer` fallback.
- Done when: `make app` produces a bundle that `codesign -dv` reports with the right identifier and `plutil -p dist/Barometer.app/Contents/Info.plist` shows `LSUIElement => true`.
- Verify: `make app && codesign -dv --verbose=2 dist/Barometer.app 2>&1 | grep -E 'Identifier|Signature'`.

### P0-T3 Application shell

- `main.swift`: create `NSApplication.shared`, set `AppDelegate`, `NSApp.setActivationPolicy(.accessory)`, `NSApp.run()`.
- `AppDelegate`: single-instance guard (design 3.5 rule 10), logging setup, create `StatusItemRegistry`, create the Settings window controller lazily, handle `applicationShouldTerminate`.
- `StatusItemRegistry` (in `MenuBarStatsUI`): owns every live `NSStatusItem`. Creates exactly the enabled,
  non-Combined-hidden identities before any item becomes visible, with the autosave names from the identity table, `button.title = ""`,
  a unique accessibility identifier, a stable per-widget accessibility label, and no `.removalAllowed`.
- `ModuleID` enum in `MenuBarStatsCore` with `autosaveName` and `displayName` computed properties. This is the single source of truth for the identity table.
- Identity self-test: in debug builds, one second after launch, log each item's `autosaveName`, `button.window?.title`, AX identifier, AX label, AX title under category `identity`, and `assert` that label and identifier match.
- Menu: the CPU item gets an `NSMenu` with "Settings…" and "Quit Barometer".
- Settings window: `NSWindow` hosting a SwiftUI `SettingsRootView` with a sidebar listing General plus every module (content can be placeholders). Opening it activates the app; closing it does not quit.
- Done when: `make run` shows a "CPU" item, its menu opens, Settings opens and closes, Quit works, and relaunching keeps the item where the user dragged it.
- Verify: `make run`; the accessibility identifier is `Barometer.CPU`; `defaults read com.barometer.app | grep 'NSStatusItem Preferred Position Barometer.CPU'` after dragging the item once; with a menu bar manager running, its identity check prints `com.barometer.app:...` ending in `Barometer.CPU` and nothing else.

### P0-T4 Probe executable and identity probe

- `mbs-probe` target with a tiny argument parser (no dependencies). Subcommands in P0: `identity` (prints the production status-item identity table without creating a status item) and `version`. Only the packaged Barometer application may create status items so menu bar managers always receive the owner bundle identity.
- Done when: `swift run mbs-probe identity` prints `statusItemCreation=disabled` and the production identity table without importing AppKit.
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

- General: launch at login (`SMAppService`), reduce sampling on battery, monochrome mode, independent font and
  icon/graph sizes, adjustable spacing for each movable status item, export and import settings.
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

- `SensorsMonitor` merging IOHID, SMC, and IOReport into a `SensorSample` with groups; renderer modes (chosen
  sensors as text, compact multi-temperature stack, mini graph, fan RPM); dropdown with grouped sparklines; settings
  (which sensors in the menu bar, units, show raw names, hide duplicates). Users can create multiple independently
  movable Sensors widgets. Each widget owns a permanent numbered identity (`Barometer.Sensors`,
  `Barometer.Sensors.2`, and so on) and an arbitrary ordered list of selected readings rather than a hard-coded
  CPU/GPU pair. Compact widgets use matched type and stable decimal fields, place readings in two-row columns, and
  expand horizontally for additional selected temperatures.
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

- `BatteryMonitor`, compact percentage-inside-battery and BAT-label percentage presentations, dropdown (details,
  health, adapter, charge history graph), settings (show when on AC, low battery threshold color). Do not expose
  duration estimates.
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

- iStat-style theme presets plus fully custom palettes. Per-module and per-section light/dark colors cover menu bar
  text and symbols, line/area/bar graphs, dropdown charts, fills, category accents, and normal/warning/critical
  thresholds. Include monochrome mode, graph style and opacity, font weight, automatic item-count-based sizing,
  reset-to-theme controls, and a live preview strip in Settings.
- Verify: exercise every preset and custom color role; screenshots in both appearances with all items visible; no
  clipping at 24 pt thickness; export/import preserves the complete theme.

### P7-T3 About, export and import, launch at login polish

- About pane (version, build, license, Open-Meteo attribution, links); JSON export and import with validation; `SMAppService` status display and a warning when running from `dist/`.
- Verify: export, delete preferences (`defaults delete com.barometer.app`), import, confirm identical layout and settings.

### P7-T4 Stability and performance pass

- Run for one hour with all modules; check `top` and memory growth (must be flat within 5 MB); run the Thaw identity check every 10 minutes and confirm the set never changes; relaunch ten times and confirm positions persist.
- Verify: paste measurements into `docs/PROGRESS.md`.

### P7-T5 Install target and README

- `make install` copies to `/Applications`, re-registers launch at login if it was on, and relaunches. README documents building, installing, permissions, and the identity contract for other developers.
- Verify: `make install && pgrep -x Barometer`.

### P7-T6 Developer ID signing and notarized release

- Add a release-only packaging path that signs the single Barometer app bundle with Developer ID Application,
  enables the hardened runtime with the minimum required entitlements, creates a distributable archive, submits it
  through `notarytool`, staples the accepted ticket, and preserves ad-hoc signing for local development builds.
- Document required Apple Developer credentials without storing secrets in the repository. Do not begin release
  submission until David selects the signing identity and provides or configures the notarization credentials.
- Verify: `codesign --verify --deep --strict --verbose=2`, `codesign -d --entitlements :-`,
  `spctl --assess --type execute --verbose=4`, `xcrun stapler validate`, and a clean-machine launch check.

End of Phase 7: v1.0 tag candidate. Stop for review.

---

## Phase 8: Battery time remaining and Stacks

Requested by David after v1.0 in response to user feedback. Stacks generalizes the Sensors widget model to every
module: each stack is one independently movable status item holding an ordered set of readings chosen from any
module, rendered in the same matched two-row columns the Sensors compact stack already uses.

David signed off on the new autosave names on 2026-09-04: stack 1 keeps `Barometer.Combined` so existing users lose
no menu bar position, and stacks 2 through 4 are `Barometer.Combined.2`, `.3`, `.4`. This is the same numbered
instance scheme Sensors and Weather already use, and `ModuleID.autosaveName(instance:)` relaxes its precondition to
allow `.combined` instances.

### P8-T1 Battery time remaining

- Read `kIOPSTimeToEmptyKey` and `kIOPSTimeToFullChargeKey`, falling back to `AppleSmartBattery`'s `AvgTimeToEmpty`
  and `AvgTimeToFull`. Reject the calculating sentinels: `-1` from IOPS and `65535` from the registry.
- Report an estimate only in the direction the battery is moving; expose `remainingMinutes` and `isEstimatingTime`
  on `BatterySample`.
- Three new menu bar presentations, all reserving a stable width: `percentageTime` (two equal live rows),
  `labeledTime` (`BAT` over the time), and `glyphTime` (battery glyph beside the time).
- Dropdown shows the estimate and distinguishes `Calculating…` from nothing to estimate.
- Verify: formatter output matches `pmset -g batt` on live hardware; the menu bar item does not change width as the
  estimate moves.

### P8-T2 Metric catalog

- A `MetricID` catalog naming every reading a stack can show, spanning all modules, with a stable label, a formatted
  value, and a reserved-width placeholder per metric.
- Verify: every metric resolves to a value or a dash from live stores.

### P8-T3 Stack settings model

- `StackSettings` following the Sensors widget discipline: never-reused ids, disabled entries kept as tombstones,
  normalization guaranteeing at least one stack. Migrate the existing `CombinedSettings` members into stack 1.
- Verify: settings written by the previous schema decode with their Combined membership intact.

### P8-T4 Stack status items

- Up to four independently movable stack items, counted by `AppSettings.enabledMenuBarItemCount` so automatic font
  size and scale stay correct.
- Verify: Thaw identity check shows each enabled stack as a separate item that keeps its position across a relaunch.

### P8-T5 Stacks settings pane

- Reorderable reading list per stack, add and delete stacks, per-stack layout, replacement, and colors.
- Verify: changes apply live and survive a relaunch.

### P8-T12 Legible weather presentation

- Icon and temperature sit side by side so both use the full bar height, instead of stacking them into half a bar
  each where neither reads. Roughly twice the width, so the compact stack stays available as its own mode.
- A glyph drawn beside text is never shrunk below its reference-scale size by the automatic item-count scale.
- Verify: the glyph and the temperature are legible at every automatic scale; both modes are selectable.

### P8-T13 One Weather presentation

- Weather shows the current condition glyph beside the current temperature, and nothing else. The mode picker and
  the high/low, precipitation, conditions, text-only, and stacked variants are gone, along with their formatting.
- The unit letter is dropped from the menu bar; the reader chose the unit and the space is scarce.
- Every condition glyph is reserved, so changing weather cannot change the item's width.
- Verify: saved settings in any old mode resolve to the single presentation.

### P8-T6 Battery power adapter correctness

- `AppleSmartBattery` keeps publishing an `AdapterDetails` stub after the adapter is unplugged, which made the
  dropdown report a wired adapter that was not attached. Report an adapter only when the power source says one is
  connected and the dictionary carries a real field.
- Verify: on battery, the dropdown shows no adapter section.

### P8-T7 User-named, unlimited stacks and a stable Battery width

- No cap, deletion allowed, nothing prefilled, and the person creating a stack names it.
- Every Battery presentation shares one canvas, because a status item keeps one length for the life of the process.
- Verify: a deleted instance number is never handed out again; all Battery presentations measure one width.

### P8-T8 Center stacked readings that have no leading marker

- Verify: the two rows share a horizontal center; Network's arrows still share one leading edge.

### P8-T9 Gate the weather glyph at a legible size

- Verify: the glyph fills its row at every automatic icon scale without changing the item's width.

### P8-T10 Put stacked rows on the shared two-row grid

- An empty marker string reports the default system font's line height, which pushed rows below every other item.
- Verify: two-row items share row origins at 22, 24, and 26 pt thickness. 22 is the real thickness on this Mac, and
  testing only at 24 hid the fault.

### P8-T11 Stack dropdown detail and Settings preview

- A stack's dropdown hosts each source module's own full dropdown behind a tab, rather than a summary of it.
- The Stacks pane shows a live preview of every stack, including staged edits, so the result is visible before the
  Apply bar is used. Reserved widths come from one catalog shared with the renderer.
- Verify: opening a stack shows the same detail the module's own item shows; the preview matches the rendered item.

### P8-T23 Bound graph-history memory

- Keep full details only in the latest sample and retain compact numeric graph history.
- Allocate history incrementally, preserve CPU and Memory day-long windows, and cap other buffers at the
  largest window actually displayed. Downsample long dropdown graphs without copying the full history.
- Bound process-icon caching and retain only row-sized thumbnails.
- Verify: execute the history and thumbnail tests, run the full suite, build the app, and compare identical
  synthetic sample workloads against P8-T22 with `Scripts/benchmark-memory.py`. Record both measurements
  and any baseline failures in the progress log.

### P8-T24 Rich daily weather with configurable detail

- Open a day-specific forecast fly-out from each daily row, using the location's date and time zone.
- Put conditions, precipitation, temperature, wind, hourly forecasts, and comfort ahead of optional astronomy
  and technical detail. Use chevrons for secondary information; lunar details start collapsed.
- Extend the existing forecast request with supported optional surface-weather and daily summary fields,
  including provider moon phase/rise/set. Preserve old caches, missing values, and independent units.
- Offer All details or Custom in Weather settings, remembering custom section choices across mode changes.
- Verify: weather model, decoding, visibility, and presentation tests; captured real metric/imperial fixtures;
  light/dark rendering; full suite; signed local build and installed-app review. Wait for David's approval before
  pushing these changes or starting another GitHub build.

### P8-T80 Open Notification Center from the clock (reverted)

Requested and reverted on 2026-09-07. Pressing the system clock's Accessibility item does open Notification Center
on a bare macOS 27, but the same press does nothing while Thaw is running, and David's goal is a hidden system clock
with the notifications inside Barometer rather than Apple's panel. See P8-T82.

### P8-T81 Clock text size

Requested by David on 2026-09-07: the clock is the one item people size on its own.

- Add `TimeSettings.menuBarFontSize` (optional, nil follows the global size, clamped to 9 to 14 pt) and carry it
  through `TimeMenuBarConfiguration` so it is staged with the other clock edits until Apply Changes.
- `TimeMenuBarPresenter` renders with the clock size through `RenderContext.withFontSize`.
- Time settings: a "Use a separate text size for the clock" toggle and a slider under the format controls.
- Verify: settings migration and staging tests, a render test proving 14 pt fits the 22 pt menu bar, full suite.

### P8-T82 Notifications in the Time dropdown

Requested by David on 2026-09-07 so the system clock can stay hidden by a menu bar manager: keep the native
banners, drop Apple's notification panel, and list the waiting notifications in Barometer's clock dropdown.

- `NotificationCenterSource` in `SystemSources` reads Notification Center's SQLite database read-only, joins the
  per-app `delivered` UUID lists with `record` rows, and decodes each request's title, subtitle, body, and date.
  Missing Full Disk Access reports `fullDiskAccessRequired`; no database reports `unavailable`.
- `NotificationFeed` in `MenuBarStatsCore` reads when the Time dropdown opens, follows the database and its WAL
  through a file watcher with a 250 ms debounce, and stops when the dropdown closes.
- `TimeSettings.showsNotifications`, default off. Time settings explain the grant and open the Full Disk Access
  pane. The dropdown card shows the complete read-only list grouped by application, without a hidden row cap. An
  **Open Notification Center** button posts the shortcut the user assigned under Keyboard Shortcuts > Mission
  Control; when none is assigned, it opens that settings pane. Barometer never changes the shortcut itself.
- Verify: fixture-database source tests, age formatter test, settings migration, the panel screens with a preset
  feed, the popover memory benchmark, full suite, signed local build.

### P8-T83 Time dropdown order, height, and notification polish

Requested by David on 2026-09-07 after using P8-T82.

- Hide notifications from applications whose "Allow notifications" is off: the per-app `auth` mask in
  `group.com.apple.usernoted.plist` is zero for them, and Notification Center no longer shows their records.
- `TimeSettings.dropdownSectionOrder`: the dropdown's cards in the user's order, always a full permutation, with
  move up and down controls in Time settings.
- `TimeSettings.dropdownHeight` (400 to 1000 pt, default 560): `DropdownController.setPreferredPanelHeight`
  applies it the next time the panel opens; the panel still never exceeds the screen.
- Credit the Thaw developers in README and the About pane.
- Verify: source, settings, and panel-height tests, the panel screens, the popover benchmark, full suite, signed
  local build.

### P8-T84 Relicense to GPL-3.0

David's decision on 2026-09-07, made so Thaw's and Ice's GPL code can be adapted with attribution instead of
reimplemented. David Brustein is the sole copyright holder, so the change needs no other consent.

- Replace `LICENSE` with the GPL-3.0 text; update README, AGENTS, DESIGN, and the About pane.
- Any adapted Thaw or Ice code must keep its copyright notice and name its origin in a comment.

### P8-T85 Hide the system clock

Requested by David on 2026-09-07. Thaw's maintainers shared `SystemClockCover.swift` and `SystemClockHider.swift`
and permitted their use; Barometer is GPL-3.0 since P8-T84. The hider's mechanism is the menu bar's
assessment-mode assertion (Apple's private `MenuBarClientCore`): a configuration names the numbered system items
and the third-party bundle identifiers that stay, and the bar removes the rest while the assertion is live. The
clock has slot 2, so leaving it out removes the clock alone and reclaims its width. Where the assertion is
unavailable, the clock is covered on its Accessibility bounds instead.

- `MenuBarAssessmentAssertion` in `SystemSources`: the one wrapper for the private framework, `isAvailable`,
  `activate(allowedSystemItems:allowedBundleIdentifiers:)`, `invalidate()`.
- `SystemClockHider` in `MenuBarStatsUI`: holds the assertion while the Time setting is on, allows every running
  app and re-applies on launch and quit, falls back to `SystemClockCover`, and publishes its state to Time settings.
- `TimeSettings.hidesSystemClock` and `systemClockCoverColor`.
- Verify: allowlist and index tests, cover band and flip math, settings migration, full suite, signed local build,
  David's installed check.

---

### P8-T86 Notification mirroring and system control replacements

Requested by David on 2026-09-07; implemented with GPT 5.6 Sol agents while Claude owns P8-T85 clock hiding.

- Investigate Apple's actual notification activation and dismissal interfaces, including their access requirements.
- Prefer the system's default notification action over inferred URLs or activating the sending application.
- Keep the mirrored notification list read-only and treat macOS as authoritative. Never write Notification Center's
  database, restart its processes, or treat a failed read as an empty list.
- Keep native action availability and any remaining limitations explicit. Do not request additional permissions.
- Show the complete delivered list without the previous 100-record and 30-row limits. Group by application with
  collapsed previews and expansion. Opening the native panel is the only clearing path.
- Add optional Focus and Now Playing menu bar pills with independent Enable Focus and Enable Now Playing toggles
  under Time. Preserve every existing identity and add permanent `Barometer.Focus` and `Barometer.NowPlaying` names.
  Use the standard registry, fixed image sizing, staged visibility, and visible-only source updates.
- Wrap the Thaw credit so the full contributor names remain visible in About.
- Verify: source invariants, routing/source/feed regression tests and the full suite, panel snapshots in both
  appearances, the popover memory benchmark, `git diff --check`, and a signed repository-local app build.
- Installed notification activation and removal require an end-to-end check against disposable notifications.
  Focus access and playback controls also require David's installed-app test; shell probes cannot prove they work
  under the installed application's grants. David chose to test the build himself instead of granting Codex access.

### P8-T92 Direct notification clearing experiment (reverted)

The direct SQLite write and notification-process restart approach was restored briefly for a disposable live test.
On the first clear, the replacement usernoted process treated its database as failed, renamed it to `db.corrupt`,
and then logged that a locked database prevented initialization. Its recreated database contained no notification
records. The renamed database passed SQLite integrity and foreign-key checks, so structural corruption was not
established. Another notification utility held long-lived SQLite read connections during the incident, which makes
process-restart recovery unsafe even when Barometer closes all of its own statements.

The writer, daemon restarter, recovery journal, and all clear controls are removed from the product. The supported
design is the read-only grouped list plus **Open Notification Center**, driven by a shortcut the user configures in
macOS. Never restore the P8-T92 approach without a new design that avoids direct database writes and process restarts.

### P8-T93 Open Notification Center through a hot corner

David's decision on 2026-09-07 after every other trigger was tried with the clock hidden by Thaw: the clock
press, the Show Notification Center shortcut (physical and synthesized), System Events, the private menu-tracking
call, a click on the clock's former spot, and the panel's own menus (no item shows the panel). The Dock's triggers
still work with the clock gone: the trackpad edge swipe and a hot corner assigned to Notification Center. A
synthesized pointer entry into such a corner opens the panel (verified by David from Terminal).

- The user assigns any corner to Notification Center in System Settings, which applies it live; Barometer reads
  the Dock's preferences to find it, never writes them, never relaunches the Dock, and never borrows a corner
  (a live CoreDock assignment was tried and did not fire).
- A press hides the cursor, jumps it into the corner, waits for the panel's expanded state, and puts the cursor
  back before showing it, so the pointer is never seen to move. No sweep across corners, ever.
- Time and Notifications settings carries the note and an "Open Hot Corner Settings…" button; the flyout carries
  only the glass "Open Notification Center" button. The list stays read-only.

### P8-T94 Temperature-keyed forecast bars

David on 2026-09-07: the 10-day forecast bar gradient was the same cyan-to-orange sweep stretched across every
bar, so a cold day and a hot day looked alike. `TemperatureScale` in WeatherDropdownView keys color to the
temperature itself (violet at -20 °C through blue, cyan, green, yellow, and orange to red at 42 °C) and each bar
samples it at its own low and high plus every stop between, in either unit. Shipped in 1.0.8.

---

## Phase 9: After v1

Only after David asks:

- Alerts with threshold rules and UserNotifications.
- Per-process network usage (private NetworkStatistics framework) and SMART data.
- Sparkle updates and a Homebrew cask.
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
