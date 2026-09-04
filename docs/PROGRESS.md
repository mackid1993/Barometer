# MenuBarStats Progress

Verification results and implementation notes are recorded here by task.

## P0-T1 Repository and package skeleton

Implemented the Git repository metadata, SwiftPM package graph, license, version, README, and compiling skeletons for
all production and test targets.

`swift build 2>&1 | tail -3` (exit 0):

```text
Building for debugging...
[0/5] Write swift-version--1AB21518FC5DEDBE.txt
Build complete! (0.16s)
```

`swift test 2>&1 | tail -3` (exit 0):

```text
Building for debugging...
[0/6] Write swift-version--1AB21518FC5DEDBE.txt
Build complete! (0.17s)
```

Environment note: this Command Line Tools installation ships `Testing.framework` under
`/Library/Developer/CommandLineTools/Library/Developer/Frameworks`, but SwiftPM does not add that framework search
path to test targets automatically. `Package.swift` adds the Command Line Tools framework path to test compilation
and linking. Plain `swift test` builds the test bundle and exits successfully, but currently prints no test-run
summary; this behavior must be revisited as part of P0-T5 identity-test verification.

`git log --oneline | head` after the task commit:

```text
287861d P0-T1: repository and package skeleton
```

## P0-T2 Bundle assembly and Makefile

Implemented the app-bundle plist, release assembly and ad-hoc signing script, and Makefile targets for the standard
build, test, app, run, stop, install, probe, and clean workflows.

`make app && codesign -dv --verbose=2 dist/MenuBarStats.app 2>&1 | grep -E 'Identifier|Signature'` (exit 0):

```text
./Scripts/make-app.sh
[0/1] Planning build
Building for production...
[0/2] Write swift-version--1AB21518FC5DEDBE.txt
Build of product 'MenuBarStatsApp' complete! (0.16s)
/Users/david/MenuBarStats/dist/MenuBarStats.app: replacing existing signature
Identifier=net.brustein.MenuBarStats
Signature=adhoc
TeamIdentifier=not set
```

`plutil -p dist/MenuBarStats.app/Contents/Info.plist` confirmed:

```text
"CFBundleIdentifier" => "net.brustein.MenuBarStats"
"CFBundleShortVersionString" => "0.1.0"
"CFBundleVersion" => "1"
"LSUIElement" => true
```

Additional validation: `sh -n Scripts/make-app.sh` succeeded and `plutil -lint Scripts/Info.plist` reported `OK`.

## P0-T3 Application shell

Implemented the accessory application lifecycle, single-instance guard, permanent registry of all ten status items,
static image-rendered CPU item, Settings and Quit menu, placeholder SwiftUI settings sidebar, and identity self-test.

`make run` built, signed, and launched the app successfully. `pgrep` confirmed one running process:

```text
14217 /Users/david/MenuBarStats/dist/MenuBarStats.app/Contents/MacOS/MenuBarStats
```

Launching a second copy with `open -n` left that same single process running. The second process notified the first to
show Settings and exited.

The debug-level unified log contained one identity line for every permanent status item. Representative lines:

```text
autosaveName=MenuBarStats.CPU window.title=MenuBarStats.CPU AXIdentifier=MenuBarStats.CPU AXLabel=CPU AXTitle=
autosaveName=MenuBarStats.Weather window.title=MenuBarStats.Weather AXIdentifier=MenuBarStats.Weather AXLabel=Weather AXTitle=
autosaveName=MenuBarStats.Combined window.title=MenuBarStats.Combined AXIdentifier=MenuBarStats.Combined AXLabel=Combined AXTitle=
```

All ten lines had a window title and AX identifier equal to the fixed autosave name, the expected static AX label,
and an empty AX title. The app defaults also recorded hidden visibility for all nine non-CPU items.

Pending manual verification:

- Confirm the CPU image and menu are visually correct, Settings opens and closes, and the menu's Quit item works.
- Command-drag the CPU item once, then check for `NSStatusItem Preferred Position MenuBarStats.CPU` in the app defaults.
- With Thaw running, perform the read-only identity check from the plan and confirm exactly one fixed CPU identity.

The attempted automated menu-bar screenshot failed with `could not create image from rect`, so visual verification
requires direct UI review.

## P0-T4 Probe executable and identity probe

Added dependency-free argument parsing plus the `identity` and `version` subcommands. The identity probe uses a
temporary AppKit status item and removes it before exiting.

`swift run mbs-probe identity` (exit 0):

```text
Build of product 'mbs-probe' complete! (0.99s)
autosaveName=MenuBarStats.Probe
window.title=MenuBarStats.Probe
AXIdentifier=MenuBarStats.Probe
AXLabel=Probe
AXTitle=
button.title=
```

Additional check, `swift run mbs-probe version` (exit 0):

```text
Build of product 'mbs-probe' complete! (0.15s)
0.1.0
```

## P0-T5 Unit test for the identity table

Added `IdentityContractTests`, which hard-codes all ten permanent autosave names and compares them in order with
`ModuleID.allCases`.

`swift test --filter IdentityContractTests` (exit 0):

```text
[0/1] Planning build
Building for debugging...
[0/8] Write sources
[1/8] Write swift-version--1AB21518FC5DEDBE.txt
[3/6] Compiling MenuBarStatsCoreTests IdentityContractTests.swift
[4/6] Emitting module MenuBarStatsCoreTests
[4/6] Write Objects.LinkFileList
[5/6] Linking MenuBarStatsPackageTests
Build complete! (0.64s)
```

Toolchain deviation: the command exits successfully after compiling and linking but does not print a test-execution
summary, including when passed `--enable-swift-testing --disable-xctest`. The Command Line Tools include
`Testing.framework` but no `XCTest` module, and SwiftPM does not visibly invoke the Swift Testing bundle after it is
built. To verify the contract logic actually executes, the same hard-coded comparison was compiled with `swiftc`
against `ModuleID.swift` and run as an ignored temporary executable:

```text
Identity contract check passed for 10 modules
```

The test source remains in the normal SwiftPM test target. Recheck the runner behavior after the next Command Line
Tools update.

## P1-T1 Core engine

Implemented the monitor protocol, continuous and injectable sample clocks, per-monitor scheduler with pause/resume
and 1-to-60-second exponential error backoff, fixed-capacity history ring buffer, downsampling, and main-actor
observable module stores. Added versioned settings, version 0 migration, debounced `UserDefaults` persistence, JSON
import/export primitives, IOKit power-source notifications, and workspace display sleep/wake notifications.

Added focused tests for history wraparound, time filtering, downsampling, scheduler backoff with a fake clock, settings
round-trip, version 0 migration, and immediate settings-store persistence.

`swift test --filter 'History|Scheduler|Settings'` (exit 0):

```text
[0/1] Planning build
Building for debugging...
[0/7] Write swift-version--1AB21518FC5DEDBE.txt
[2/11] Compiling SystemSourcesTests SystemSourcesTests.swift
[3/11] Emitting module SystemSourcesTests
[4/11] Compiling MenuBarStatsCoreTests SettingsTests.swift
[5/11] Compiling MenuBarStatsCoreTests SchedulerTests.swift
[6/11] Compiling MenuBarStatsCoreTests HistoryTests.swift
[7/11] Emitting module MenuBarStatsCoreTests
[8/11] Compiling MenuBarStatsCoreTests IdentityContractTests.swift
[9/11] Compiling MenuBarStatsCoreTests MenuBarStatsCoreTests.swift
[9/11] Write Objects.LinkFileList
[10/11] Linking MenuBarStatsPackageTests
Build complete! (1.15s)
```

Command Line Tools deviation: importing both Foundation and Testing activates a `Testing` cross-import overlay for
`_Testing_Foundation`, but that framework has no module interface in this installation. Test compilation uses the
compiler's `-disable-cross-import-overlays` option. The previously documented silent Swift Testing runner behavior
remains: the required command compiles and links successfully but prints no execution summary.

## P1-T2 CPU source and monitor

Implemented Mach per-core tick collection with correct buffer deallocation, Apple Silicon performance/efficiency
topology, load averages, uptime, libproc process enumeration, PID/start-time metadata caching, physical footprints,
thread counts, and timebase-corrected process CPU deltas. Added `CPUMonitor`, complete CPU samples, top-process
selection, and the `mbs-probe cpu [--watch]` command.

`swift run mbs-probe cpu` under normal interactive load (exit 0, selected output):

```text
CPU 15.4% (user 9.7%, system 5.7%, nice 0.0%, idle 84.6%)
load averages: 7.41, 5.85, 4.15; uptime: 179742 s
processes: 805; threads: 4765
cores: E0 48.1%, E1 44.4%, E2 33.3%, E3 33.3%, P4 0.0%, P5 0.0%, P6 0.0%, P7 0.0%, P8 0.0%, P9 17.9%, P10 11.1%, P11 14.8%, P12 6.9%, P13 7.1%
```

`swift run mbs-probe cpu --watch` printed fresh CPU, core, load, uptime, process, and thread values once per second.

Controlled-load verification used one `yes` process. `ps` reported:

```text
PID    %CPU      TIME COMM
17403  99.9   0:13.45 yes
```

The probe reported the process at 7.10% of total machine capacity, which is the expected normalized value for one
fully occupied logical CPU on this 14-core machine. Total CPU rose, but the scheduler migrated the process across
performance cores during the sampling interval, so no single per-core counter remained near 100%. This is a
verification-assumption deviation rather than a data-source failure; per-core values remained internally consistent
with the total.

`swift build 2>&1 | tail -3` (exit 0):

```text
[2/4] Linking MenuBarStatsApp
[3/4] Applying MenuBarStatsApp
Build complete! (0.66s)
```

## P1-T3 Memory source and monitor

Implemented Mach `HOST_VM_INFO64` statistics, host page-size and physical-memory queries, Activity Monitor-style
memory categories, memorystatus pressure, swap usage, kernel pressure notifications, top processes by physical
footprint, `MemoryMonitor`, and `mbs-probe memory`.

`swift run mbs-probe memory` (exit 0):

```text
Memory 36.50 GiB used of 48.00 GiB
app 16.65 GiB; wired 5.15 GiB; compressed 14.70 GiB; cached 9.20 GiB; free 11.50 GiB
pressure 43.0% (normal); swap 0.0 MiB of 0.0 MiB
top processes:
    1102  8.64 GiB  prl_vm_app
   93467  6.25 GiB  com.apple.Virtualization.Virtua
    2968  1.50 GiB  iTerm2
```

The independent `memory_pressure` tool reported `System-wide memory free percentage: 57%`, exactly matching the
probe's derived 43% pressure. `sysctl vm.swapusage` independently reported total and used swap of 0.00 MiB, matching
the probe. Direct Activity Monitor visual comparison remains part of manual review.

## P1-T4 Menu bar rendering framework

Implemented the `MenuBarRenderer` protocol, render context and light/dark palette, fixed-width monospaced text,
line/area/bar graphs, stacked labels, SF Symbol plus text, and combined-renderer scaffold. Added generic observable
status-item controllers that only update `button.image` and AXValue, plus a coordinator connecting CPU and Memory
stores, schedulers, power-aware interval multipliers, and display sleep/wake pause and resume.

CPU supports percentage, history graph, per-core bars, stacked label/value, and icon/text modes. Memory supports used
percentage, pressure percentage, history graph, used bar, and stacked label/value modes.

User feedback changed the defaults from ambiguous bare percentages to labeled, two-line iStat-style presentations:
`CPU` and `MEM` above their values. A one-time presentation-default migration updated the settings created by the
earlier Phase 1 launch without touching status-item position preferences. The persisted settings now contain:

```text
"cpu" ... "mode":"stacked"
"memory" ... "mode":"stacked"
```

`make run` built, signed, and launched the live app successfully. Render logs confirmed changing values:

```text
module=Memory value=Memory 79.4 percent used, pressure 56.0 percent
module=CPU value=CPU 37.1 percent
module=CPU value=CPU 28.3 percent
module=Memory value=Memory 80.3 percent used, pressure 53.0 percent
```

Screenshots were captured in `dist/phase1-light.png` and `dist/phase1-dark.png`. Both appearances rendered without
clipping. The required temporary switch to light appearance was visible to the user before the scripted restoration
completed; dark appearance was immediately restored and verified through both global defaults and a new screenshot.
Do not change the user's system appearance again without an explicit warning immediately before the change.

## P1-T5 Dropdown framework

Implemented a reusable `DropdownController` that owns each module menu, hosts a 320-point SwiftUI detail view,
provides Settings and Quit commands, and runs a half-second `.common`-mode timer while menu tracking is active. The
timer advances the observable store revision and logs `tracking tick` records in the `dropdown` category.

The CPU dropdown includes a live history graph with 1-minute, 5-minute, 30-minute, 3-hour, and 24-hour ranges,
per-core activity bars, load averages, uptime, process/thread counts, app icons, top-process CPU values, and process
termination. Processes owned by another user or macOS require an explicit warning confirmation. The Memory dropdown
includes a composition bar and legend, pressure history and severity coloring, swap use, app icons, and top process
footprints. History capacities now retain a full 24 hours at the normal CPU and Memory intervals.

`swift build` (exit 0):

```text
Building for debugging...
[3/7] Compiling MenuBarStatsUI MonitoringCoordinator.swift
[4/7] Emitting module MenuBarStatsUI
[8/10] Linking MenuBarStatsApp
Build complete! (1.42s)
```

`make app` and `make run` both exited 0. The packaged process remained running from
`dist/MenuBarStats.app/Contents/MacOS/MenuBarStats`, confirming startup and menu installation did not crash.

The required interactive 10-second open-menu check and corresponding live `log stream` capture remain for David's
review because they require holding the actual CPU menu open. If the graph does not advance during that check, P1-T5
must be reopened to add the `NSPanel` fallback before Phase 1 is accepted.

## P1-T6 Settings panes for General, CPU, and Memory

Replaced the placeholder settings window with working General, CPU, and Memory panes. General settings now control
launch at login through `SMAppService`, reduced sampling on battery, monochrome rendering, font size, and JSON import
and export. CPU and Memory settings now provide enabled toggles, labeled display-mode choices, a renderer-backed live
preview image, fixed-width digits, graph style, separate light/dark colors, live sampling intervals, process-list
visibility, and a configurable 1-to-10 row count.

Sampling interval changes now flow from the persisted module settings into each scheduler. Dropdown process controls
are live, and both monitors retain enough candidates to honor the 10-row maximum.

`swift build` (exit 0):

```text
[3/7] Compiling MenuBarStatsUI SettingsWindowController.swift
[4/7] Emitting module MenuBarStatsUI
[12/14] Linking MenuBarStatsApp
Build complete! (2.31s)
```

The first build exposed a Swift 6.2.3 compiler crash while emitting a `Binding<Bool>` whose setter directly
referenced the main-actor login-service method. Replacing that one control with an equivalent state-labeled
Enable/Disable button avoided the compiler defect without relaxing concurrency checks.

`make app`, `make run`, and a second `open -n dist/MenuBarStats.app` all exited 0. The second launch opened the
settings handoff and terminated, leaving exactly one owner process:

```text
20031 /Users/david/MenuBarStats/dist/MenuBarStats.app/Contents/MacOS/MenuBarStats
```

`swift test --filter Settings` exited 0 after compiling and linking the test bundle; the previously documented silent
Swift Testing runner behavior remains. The interactive CPU hide/show check against Thaw remains for David's review;
Thaw was not launched or modified, as required by the repository rules.

Follow-up visual review found that font size alone was not enough control for the compact stacked labels. Added a
separate 75%-to-135% menu-bar scale that grows text, icons, and graph widths together, plus 0-to-12-point horizontal
item spacing. Both controls update live in General settings. The production default is now 115% scale with 3 points
of padding on each side, and a one-time presentation migration applies those more readable values to settings from
the earlier Phase 1 build.

`swift test --filter Settings` compiled and linked successfully after adding focused migration assertions for the new
values (exit 0; the installed test runner remains silent). `make run` then rebuilt, signed, and launched the packaged
app with the larger migrated presentation.

## Product identity update

David explicitly renamed the product to Barometer and authorized replacing the original personal-name bundle
identifier. Updated the visible application name, settings window, login control, menu commands, export filename,
bundle assembly paths, executable name, package name, logging subsystem, single-instance notification, tests, and
identity documentation. The permanent per-module autosave names remain unchanged so the internal item identifiers
continue to come from the single `ModuleID` table.

`make app` produced `dist/Barometer.app`. Bundle inspection confirmed:

```text
Identifier=com.barometer.app
Signature=adhoc
TeamIdentifier=not set
"CFBundleDisplayName" => "Barometer"
"CFBundleExecutable" => "Barometer"
"CFBundleIdentifier" => "com.barometer.app"
"CFBundleName" => "Barometer"
```

`make run` exited 0, and the renamed bundle launched as exactly one process:

```text
21906 /Users/david/MenuBarStats/dist/Barometer.app/Contents/MacOS/Barometer
```

This requested identifier change creates a new macOS status-item namespace, so positions saved under the pre-release
identifier do not transfer. The obsolete generated app bundle and temporary benchmark helpers were moved to `/tmp`
rather than left beside the new product.

## P1-T7 Performance pass

The first measurement showed that enumerating every process on every module sample caused periodic CPU spikes.
Process lists are now refreshed independently of the lightweight system counters (CPU every 3 seconds, Memory every
5 seconds), while stable process ownership and thread metadata are cached for 15 seconds. This preserves fresh top
processes and counts while avoiding thousands of redundant libproc calls. The command-line CPU probe uses a short
refresh interval so its one-shot output still contains meaningful deltas.

For the required test, reduced battery sampling was disabled only in Barometer's settings domain, the app was
relaunched with CPU at 1 second and Memory at 2 seconds, and the exact `top -l 5 -stats pid,cpu,mem -pid 22332`
command was run. Relevant unedited process rows were:

```text
PID    %CPU MEM
22332  0.0  30M
PID    %CPU MEM
22332  1.0  30M-
PID    %CPU MEM
22332  0.3  30M
PID    %CPU MEM
22332  0.5  30M
PID    %CPU MEM
22332  0.8  30M
```

The five-sample arithmetic mean was 0.52% CPU, below the 0.7% limit, with approximately 30 MB resident memory. The
machine was under substantial unrelated load during the measurement (system-wide CPU use ranged from 30% to 38%).
The original battery-sampling preference was restored immediately afterward, and temporary benchmark files were
moved to `/tmp`.

Final regression verification:

- `swift test` exited 0 after building and linking all targets and the `BarometerPackageTests` bundle. The installed
  Command Line Tools runner still did not print an execution summary, as documented in P0-T5 and P1-T1.
- `swift run mbs-probe cpu` reported 19.2% total use, all 14 cores, 773 processes, 5,022 threads, load averages,
  uptime, and nonzero top-process CPU values.
- `swift run mbs-probe memory` reported 39.34 GiB used of 48.00 GiB, 51% normal pressure, swap, and top-process
  footprints.

## Barometer status-item identity migration

David explicitly authorized the one-time replacement of the pre-release `MenuBarStats.*` status-item autosave names
after Bartender matched and hid those legacy identities. The fixed production names are now `Barometer.CPU`,
`Barometer.GPU`, `Barometer.Memory`, `Barometer.Disks`, `Barometer.Network`, `Barometer.Sensors`,
`Barometer.Battery`, `Barometer.Weather`, `Barometer.Time`, and `Barometer.Combined`. The source table, focused
contract test, design, plan, and repository instructions were updated together. Earlier progress entries retain the
old names as historical evidence.

Verification:

- `swift test --filter IdentityContractTests` built every affected target and exited 0.
- `make run` rebuilt, signed, and launched `dist/Barometer.app` successfully.
- Bundle inspection still reported `CFBundleIdentifier = com.barometer.app`, `CFBundleName = Barometer`, and the
  ad hoc signature identifier `com.barometer.app`.
- Process inspection showed exactly one owner at
  `/Users/david/MenuBarStats/dist/Barometer.app/Contents/MacOS/Barometer`.
- Bartender's read-only cold-start catalog showed the current stable identities
  `axid:com.barometer.app:com.barometer.app:Barometer.CPU` and
  `axid:com.barometer.app:com.barometer.app:Barometer.Memory`. The prior `MenuBarStats.*` records remained only as
  older catalog history.

Bartender itself is configured with `GoldenGateNewItemsPlacement` set to `section = hidden`, so it intentionally
routes newly discovered menu bar items into its hidden section. A screen capture confirmed that this policy was in
effect after the successful identity migration. Barometer did not change Bartender's preferences; the new stable
identities now give Bartender and the user distinct items that can be moved to the visible section.

## Bundled status-item ownership correction

Feedback from the Thaw developer clarified the macOS 27 compatibility requirement: a menu bar item created by an
unbundled helper or command-line process has no application bundle identity for a menu bar manager to associate with
it. The production Barometer registry was already created by the main app process, but the `mbs-probe identity`
diagnostic violated the same architectural rule by creating a temporary AppKit status item from a naked SwiftPM
executable.

Removed all `NSStatusItem` creation and the AppKit dependency from `mbs-probe`, and removed the standalone
status-item probe. The identity command now prints constants only. Renamed the SwiftPM application product and
binary to `Barometer` so the product, `CFBundleExecutable`, on-disk executable, application name, and signing
identifier no longer rely on a copied binary rename. `AppDelegate` now validates the `Barometer.app` suffix,
`com.barometer.app` bundle identifier, and `Barometer` executable name before constructing `StatusItemRegistry`; a
naked `swift run Barometer` exits without touching `NSStatusBar`. The bundle assembly script also fails unless the
finished app contains exactly one executable and passes strict code-signature verification.

Verification:

- `swift build` built the renamed `Barometer` and dependency-free `mbs-probe` products successfully.
- `swift run --skip-build mbs-probe identity` printed `statusItemCreation=disabled`,
  `probeBundleIdentifier=none`, and the ten production `Barometer.*` constants.
- `swift run --skip-build Barometer` exited 0 in under one second. The unified log recorded
  `Refusing unbundled launch: bundle=none executable=Barometer isAppBundle=false`, and no Barometer process remained.
- `swift test --filter IdentityContractTests` exited 0.
- `make app` built and signed `dist/Barometer.app`; the new assembly validations passed.
- Bundle inspection found exactly one executable, `Contents/MacOS/Barometer`. `Info.plist` and `codesign` both
  reported `com.barometer.app`, with `CFBundleExecutable`, `CFBundleDisplayName`, and `CFBundleName` all set to
  `Barometer`.
- A controlled launch used only `open dist/Barometer.app`. The running process had bundle identifier
  `com.barometer.app`, and Bartender's read-only catalog associated both `Barometer.CPU` and `Barometer.Memory` with
  that bundle identifier. The app was stopped immediately after verification; Thaw was not launched or modified.

## macOS menu-bar registration diagnostics

Compared Barometer directly with the current `exelban/stats` source after a live Barometer build produced valid but
unplaced status-item scenes. Stats relies on `LSUIElement` instead of changing the process activation policy before
the AppKit run loop, and it creates only the status items used by active modules. Barometer now follows that startup
shape: the registry creates an item on first request, content is rendered before a hidden item is made visible, and
visibility is written only when it changes. The diagnostic self-test records the actual owner bundle, executable,
AX identity, rendered image properties, and status-scene geometry at
`~/Library/Logs/Barometer/identity.json`.

The hand-built bundle was also missing standard AppKit metadata present in Stats. Added `NSPrincipalClass =
NSApplication`, `CFBundleInfoDictionaryVersion`, the development region, and the Utilities application category.
Removed the redundant pre-run-loop `setActivationPolicy(.accessory)` call; `LSUIElement` remains the source of the
agent application policy.

Verification:

- `swift build --disable-sandbox` completed successfully with task-local Swift and Clang module caches.
- `swift test --disable-sandbox` built all test targets and exited 0. As previously recorded, this Command Line Tools
  runner did not print a test execution summary.
- `make run` rebuilt, ad hoc signed, and launched the corrected bundle. The diagnostic report showed one process at
  `dist/Barometer.app/Contents/MacOS/Barometer`, bundle identifier `com.barometer.app`, and only the implemented CPU
  and Memory status items.
- Both items had stable `Barometer.*` autosave and AX identifiers, empty button titles, nonempty template images,
  enabled visibility, and current accessibility values.
- macOS still assigned both scenes a zero-height fallback frame and wrote no Barometer entry to
  `com.apple.MenuBarAgent` even though Stats has existing placement records on the same Mac. The initial comparison
  suggested the macOS Allow in the Menu Bar switch, but subsequent unified-log inspection disproved that inference:
  MenuBarAgent created both Barometer status items with `isAllowed: true`, and all four FrontBoard scene-creation
  actions completed successfully. Bartender's diagnostics likewise discovered Memory but returned BT02 when trying
  to move its unplaced scene. The remaining controlled difference is that Stats runs from `/Applications` while
  Barometer runs from the repository's `dist/` directory; `/Applications/Barometer.app` does not exist. Testing a
  stable-path installation requires David's explicit approval because it writes outside the repository. No Apple,
  Bartender, Stats, or Thaw preference was changed by Barometer or the build process.

David explicitly approved installation into `/Applications`. `make install` rebuilt build 17, copied the signed app
to `/Applications/Barometer.app`, stopped the repository copy, and launched the installed copy. This resolved the
placement failure without changing any application or manager preferences:

- Process inspection showed exactly one Barometer process at
  `/Applications/Barometer.app/Contents/MacOS/Barometer`.
- The identity report showed the installed bundle path and the unchanged `com.barometer.app` identifier.
- CPU changed from a zero-height fallback frame to an unobscured 33 x 33 frame at `(1178, 1084)`.
- Memory changed from a zero-height fallback frame to an unobscured 39 x 33 frame at `(1139, 1084)`.
- MenuBarAgent accepted the installed client, created both status items with `isAllowed: true`, and completed scene
  hosting under the main Barometer process.
- Bartender refreshed the current stable identities
  `axid:com.barometer.app:com.barometer.app:Barometer.CPU` and
  `axid:com.barometer.app:com.barometer.app:Barometer.Memory`, both with the installed app's bundle identifier.
- `codesign --verify --strict` passed, and the installed `Info.plist` reported build 17 and
  `NSPrincipalClass = NSApplication`.

Because macOS 27 status-item placement depends on the stable installed bundle path, `make run` now delegates to
`make install`. `make app` remains the repository-only command for producing `dist/Barometer.app`; interactive menu
bar compatibility checks always launch `/Applications/Barometer.app`.

## P2-T1 Open-Meteo client

Added the dependency-free async Open-Meteo client, detailed forecast, geocoding, air-quality, weather-unit, WMO-code,
and lunar-phase models. Forecast requests include current conditions, 240 hourly points, and ten daily points. The
client uses an ephemeral `URLSession`, a 15-second request and resource timeout, a stable Barometer user agent, and
surfaces Open-Meteo HTTP error reasons. Real Boston forecast, geocoding, and air-quality responses were saved as test
fixtures. The weather tests cover detailed decoding, empty geocoding results, WMO descriptions and day/night symbols,
known new/full moon dates, and every lunar-phase SF Symbol name.

The command-line probe now supports `weather --lat N --lon N` and `geocode QUERY`. It remains a data-only executable
and does not import AppKit or create status items. The current Open-Meteo forecast, geocoding, and air-quality
documentation was checked before live verification; every requested variable remains supported.

Verification:

- `swift test --disable-sandbox --filter Weather` built `MenuBarStatsCoreTests`, linked
  `BarometerPackageTests.xctest`, and exited 0. The Command Line Tools runner still emitted no execution summary, as
  documented in Phase 1.
- `swift run --disable-sandbox mbs-probe weather --lat 42.3601 --lon -71.0589` contacted the live API and printed
  `Current 65.9°F, feels like 69.8°F, Overcast`, `Humidity 92%; wind 2 mph; AQI 49`, followed by ten dated daily
  rows from September 3 through September 12.
- `swift run --disable-sandbox mbs-probe geocode Boston` returned ten results. The first was Boston, Massachusetts,
  United States at `[42.35843, -71.05977]` in `America/New_York`.
- The first live probe inside the restricted command sandbox could not resolve the Open-Meteo host. Repeating the
  identical probe with explicitly approved network access succeeded; this was an agent sandbox restriction, not an
  application or API failure.
- `git diff --check` reported no whitespace errors, and the weather sources and tests contain no lines longer than
  120 columns.

## P2-T2 Weather monitor and cache

Added a per-location `WeatherMonitor`, a `WeatherMonitoringSession`, network-path observation, scheduler-triggered
manual refresh, and an atomic on-disk last-known-good cache. Production cache files live under
`~/Library/Application Support/MenuBarStats/weather/` and use stable hashed filenames so a location identifier
cannot escape the cache directory. A failed forecast refresh returns cached data, marks it stale once its fetch time
is at least two configured refresh intervals old, and retries after 1, 2, 4, and up to 60 seconds. Successful
forecast refreshes restore the normal 15-minute interval. Air-quality failure does not discard a usable forecast;
the most recent cached air-quality reading remains available.

The monitoring session interrupts the current 15-minute wait when the network transitions from unavailable to
available. Its resume operation also samples immediately after display wake. Tests inject path events and wall-clock
dates, allowing reconnect, cache-age, and backoff behavior to be verified without turning off the Mac's active
network connection.

Verification:

- `swift build --disable-sandbox` completed successfully with task-local Swift and Clang module caches.
- `swift test --disable-sandbox --filter 'WeatherMonitor|Scheduler'` rebuilt and linked the test bundle and exited 0.
- `swift test --disable-sandbox` rebuilt all application and test targets and exited 0. As previously recorded, this
  Command Line Tools runner emits no test execution summary.
- The weather-monitor tests verified a fresh write, cached fallback, the stale transition after two shortened
  intervals, exponential retry reset, failure propagation without a cache, safe cache filenames, and immediate
  refresh after an injected offline-to-online transition.
- The scheduler test verified that manual refresh cancels its long interval wait and samples immediately.
- A disruptive live Wi-Fi off/on test was not performed autonomously. The production observer uses the same
  `NWPathMonitor` transition covered by the deterministic test and will be wired to the app's saved locations in
  P2-T3.

## P1-F1 Dropdown process presentation corrections

Corrected two issues found during live Phase 1 review. The CPU history range picker now occupies its own full-width
row, so all five choices through `24h` fit inside the menu instead of clipping the last segment. Process metadata now
walks from an executable to its containing application bundle and prefers `CFBundleDisplayName` or `CFBundleName`.
Process rows use the live `NSRunningApplication` icon first, then the containing `.app` icon, then a file or
command-line fallback. The icon lookup is cached to avoid repeating workspace queries during live menu updates.

Verification:

- `swift test --disable-sandbox --filter 'processMetadata|Scheduler|WeatherMonitor'` rebuilt the affected source,
  UI, and test targets and exited 0.
- A synthetic `Parallels Desktop.app/Contents/MacOS/prl_vm_app` fixture verified containing-bundle discovery and
  display-name resolution.
- `swift run --disable-sandbox mbs-probe memory` reported PID 1102 as `Parallels Desktop` instead of `prl_vm_app`.
- `make app` completed a release build and strict ad hoc signature verification.
- `make run` installed and launched the corrected single-bundle app from `/Applications/Barometer.app`.

## P2-T3 Weather settings pane

Added schema-2 weather settings with ordered saved locations, a stable primary location, optional automatic current
location, independent temperature/wind/pressure/precipitation units, a 5–60 minute refresh interval, renderer mode,
and custom token template. Schema-0 and schema-1 settings migrate without losing CPU, Memory, appearance, or module
preferences. New and migrated Weather modules default to icon plus temperature.

The Weather settings pane searches Open-Meteo after a short debounce, displays location context, prevents duplicate
locations, and supports add, remove, reorder, and primary-location selection. Enabling current location starts a
low-power Core Location watch with three-kilometer accuracy and a five-kilometer distance filter. Coordinate changes
replace the stable `current-location` entry and restart that location's monitor; denied or unavailable location access
falls back to saved locations without making Weather unusable.

Weather monitoring is now wired into the main single-bundle process. Enabling Weather with a primary location starts
one cached monitoring session, changing the location, units, or interval replaces it, network reconnect and display
wake refresh it, and disabling Weather hides its existing permanent status item without removing it. The first menu
bar presentation supports temperature, icon plus temperature, conditions, high/low, precipitation, and template
modes while preserving the static Weather accessibility identity.

Both temperature systems are explicit: Weather independently offers Fahrenheit and Celsius, while General settings
provide a separate Celsius/Fahrenheit preference for Sensors, GPU, and Battery hardware temperatures.

Verification:

- `swift test --disable-sandbox --filter Settings` built all affected targets and exited 0.
- `swift test --disable-sandbox` rebuilt and linked all app and test targets and exited 0.
- Settings tests cover schema-0 and schema-1 migration, Fahrenheit/Celsius round trips, Weather defaults, ordered
  primary-location fallback, and the independent hardware-temperature unit.
- `swift build --disable-sandbox` compiled Core Location, Weather settings, monitoring-session replacement, and all
  six initial Weather menu bar modes under Swift 6 strict concurrency.
- Core Location permission was not requested during automated verification; it remains an explicit user action from
  the Weather settings pane.

## P2-T4 Weather menu bar renderer

Extracted Weather presentation into a deterministic core formatter and completed all six planned menu bar modes:
temperature, icon plus temperature, icon plus temperature and condition, daily high/low, precipitation probability,
and a custom token template. The formatter expands `{temp}`, `{cond}`, `{hi}`, `{lo}`, `{pop}`, `{wind}`, and
`{aqi}`, preserves unknown tokens for user correction, and appends a visible warning marker to stale cached data.
Temperature output includes its explicit °F or °C suffix. Accessibility values continue to use only the live value;
the Weather label and `Barometer.Weather` identifier remain static.

SF Symbols now receive the selected module palette before being composited. The final image remains a template only
in monochrome mode, preserving correct system tinting in both appearances while allowing configured colors when
monochrome mode is off.

Verification:

- `swift test --disable-sandbox --filter Weather` built and linked the Weather formatter tests and exited 0.
- Formatter coverage includes Fahrenheit, Celsius, stale state, conditions, high/low, wind, known custom tokens, and
  preservation of an unknown token.
- `swift build --disable-sandbox` compiled every renderer mode and the AppKit symbol-palette configuration under
  Swift 6 strict concurrency.
- System appearance was not toggled automatically because David previously reported an unwanted machine-wide
  appearance change. Light and dark visual review remains appropriate for the later Fable UI pass.
