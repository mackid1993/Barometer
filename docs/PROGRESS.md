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

## P2-T5 Weather dropdown

Added a 420-point-wide, scrollable Weather dropdown designed for dense iStat-style detail without clipping. It
contains a multicolor current-conditions header with apparent temperature and stale warning; a horizontally
scrollable 48-hour temperature curve with precipitation bars, condition symbols, temperatures, and probabilities;
ten daily rows with normalized low-to-high range bars; sunrise, sunset, and calculated moon phase; U.S. AQI, PM2.5,
and PM10; and a details grid for humidity, wind direction and speed, pressure, cloud cover, current precipitation,
and gusts.

The footer switches among saved locations, refreshes immediately, opens Apple's Weather app, and provides the
required linked Open-Meteo attribution. Pressure presentation converts Open-Meteo hPa data to the independently
selected hPa, inHg, or mmHg unit. All forecast dates and times use the forecast location's time zone. The generic
dropdown controller now accepts a content width while keeping the existing CPU and Memory menus at 320 points.

Verification:

- `swift build --disable-sandbox` compiled the complete dropdown and app integration under Swift 6 strict
  concurrency.
- `swift test --disable-sandbox` rebuilt and linked every application and test target and exited 0.
- `git diff --check` reported no whitespace errors, and the new UI sources contain no lines longer than 120 columns.
- The menu continues to use the common-mode tracking timer, so live samples and the stale indicator update while it
  remains open.
- A populated visual review requires a saved Weather location and remains for David's/Fable's UI pass; automated
  verification did not alter David's Barometer preferences to inject a test city.

## P1-F2 Icon-and-text optical spacing correction

Compared Barometer's Weather status item with David's installed Kelvin Shift source. Kelvin Shift places its glyph,
one text space, and value in a single AppKit title. Barometer cannot use a changing button title without violating the
macOS 27 status-item identity contract, so `IconTextRenderer` now reproduces that geometry inside its stable image:
the SF Symbol keeps its native aspect ratio, uses a vertically centered cap-height-sized box, and is separated from
the value by the measured width of one space in the actual menu bar font. This replaces the fixed square symbol box
and arbitrary three-point gap that made the cloud and temperature look disconnected.

Verification:

- Kelvin Shift was inspected read-only at `/Users/david/KelvinShift`; its app, preferences, and running state were
  not modified.
- `swift build --disable-sandbox` compiled the aspect-ratio and font-metric layout under Swift 6 strict concurrency.
- The implementation remains image-only: `NSStatusBarButton.title` stays empty, and the fixed Weather identity is
  unchanged.

## P1-F3 Weather symbol vertical alignment correction

Follow-up visual review showed that the Weather symbol's remaining mismatch was vertical rather than horizontal.
Added a font-relative upward optical offset to the native-aspect SF Symbol while leaving the temperature text on its
existing centered baseline. The adjustment applies consistently across symbol-and-text modes without changing item
width, title, label, or autosave identity.

Verification:

- `swift build --disable-sandbox` completed with zero warnings from Barometer sources.
- `make run` release-built, signed, installed, and launched the adjusted app from `/Applications/Barometer.app` for
  David's live visual check.

## P1-F4 Standardized menu bar typography

Replaced module-specific text placement with canonical menu bar layout metrics. Stacked labels and values now share
one leading edge and fixed row geometry, so CPU and Memory no longer shift horizontally according to the width of
each line. Icon-and-text renderers use the configured font size, one shared gap, and a font-descender-based optical
lift that aligns the visible SF Symbol with digits and capital letters without changing the status-item identity.

Added a dedicated `MenuBarStatsUITests` target covering leading edges, stacked row positions, symbol sizing, the
canonical icon gap, and optical vertical placement. Phase 4 now explicitly requires a compact, ordered
multi-temperature mode that places CPU, GPU, and other selected readings inside the single Sensors status item.

Verification:

- `swift test --disable-sandbox` built and linked all application and test targets, including the new UI tests, and
  exited 0.
- `make run` release-built, signed, installed, and launched `/Applications/Barometer.app`.
- Tight Retina screenshot review measured the Weather cloud and `77°F` visible centers within one pixel.
- David approved the installed result during live review: "That is sexy."

## P1-F5 Independent status-item spacing and sizing

Separated the two global size controls. Font size now affects menu bar type only, while Icon and graph size affects
SF Symbols and graph widths without rescaling text. Existing settings migrate their former combined effective size
into the font once, preserving the installed appearance. The settings schema remains forward-compatible with the
brief development build that wrote schema 4.

Fixed the spacing regression without grouping modules. AppKit's variable-length status-item button added an
undocumented eight-point image inset on each side, even when Barometer's rendered spacing was zero. Each controller
now sets its permanent `NSStatusItem.length` to the exact rendered image width after every update. CPU, Memory, and
Weather therefore remain separate status items with separate `Barometer.*` identities and can be moved independently
by macOS, Bartender, or Thaw. The Combined workaround was removed from the active implementation and remains a later,
explicitly optional Phase 7 feature.

The shared renderer geometry now aligns SF Symbols from their published alignment rectangles, avoiding hard-coded
weather offsets. Regression tests cover independent text/graphic scaling, exact two-sided spacing, exact status-item
canvas length, shared stacked-label origins, and Weather symbol optical alignment.

Verification:

- `swift test --disable-sandbox` rebuilt and linked every app and test target and exited 0. The previously documented
  Command Line Tools runner behavior still omits a test-execution summary.
- `make run` release-built, ad hoc signed, installed, and launched `/Applications/Barometer.app`.
- `codesign --verify --deep --strict --verbose=2 /Applications/Barometer.app` reported the app valid on disk and
  satisfying its designated requirement.
- Live identity diagnostics reported exact button/image widths of 23/23 points for CPU, 29/29 for Memory, and 36/36
  for Weather. The three status-item windows were adjacent and independently positioned; the former variable-length
  buttons had been 16 points wider than their images.
- A tight Retina capture at `dist/menubar-independent-spacing-final.png` confirmed aligned CPU/MEM rows, aligned
  Weather glyph and temperature, and compact zero-added-spacing presentation without changing system appearance.

## P3-T1 Network source

Added interface identity and flags from `NET_RT_IFLIST2`, IPv4 and IPv6 addresses from `getifaddrs`, and primary
interface, router, and DNS data from SystemConfiguration. P3-T2 validation found that macOS 27 returned only the low
32 bits of the cumulative `if_msghdr2` byte fields despite the SDK exposing `if_data64`. The source now uses the
documented per-interface IFMIB table for full 64-bit counters while retaining `NET_RT_IFLIST2` for the interface
list. The configuration watcher reports changes to the main actor. CoreWLAN supplies power, signal, noise, channel,
band, transmit rate, and security; SSID and BSSID remain explicitly unavailable when the process lacks Location
authorization. The optional public-IP source is off by default and independently validates IPv4 and IPv6 responses.

Added the data-only `NetworkMonitor` rate calculation needed by the diagnostic probe plus `mbs-probe net [--watch]`
and `mbs-probe wifi`. No speed-test feature, file, or dependency is part of Barometer; verification only generated
temporary traffic and discarded its response.

Verification:

- `swift build --disable-sandbox` compiled all targets under Swift 6 strict concurrency.
- `swift test --disable-sandbox --filter 'network|publicIP'` rebuilt and linked the network smoke and address-parser
  tests and exited 0. The Command Line Tools runner still omits its execution summary.
- `swift run --disable-sandbox mbs-probe net` reported primary interface `en0`, IPv4 and IPv6 addresses, router,
  two DNS servers, current rates, and cumulative download/upload totals.
- `swift run --disable-sandbox mbs-probe wifi` reported a powered 6 GHz connection at -58 dBm, -92 dBm noise,
  576 Mbps transmit rate, and WPA3 Personal security. SSID and BSSID correctly reported that Location permission may
  be required.
- During `mbs-probe net --watch`, a temporary 100 MB download raised the measured receive rate from idle traffic to
  17.1, 32.4, and 37.0 MiB/s and increased the cumulative received total by about 110 MiB.
- The plan's Cloudflare traffic URL returned HTTP 403 on September 3, 2026. A reachable 100 MB test object was used
  instead and written directly to `/dev/null`; no file remained. This was a verification-endpoint deviation, not a
  source fallback.
- `git diff --check` passed, and the changed Swift files contain no lines longer than 120 columns.

## P3-T2 Network module

Completed the Network status item, live monitor, dropdown, and settings pane. The monitor calculates rates from
64-bit cumulative counters, handles counter resets without producing spikes, follows the primary interface by
default, supports an explicit interface selection, and refreshes immediately after network configuration changes.
Public IPv4 and IPv6 lookup remains off by default, is clearly disclosed in settings, and is cached for 15 minutes
when enabled.

The menu bar supports equal download/upload rows, one-line arrows and rates, a download-focused NET stack, and an
activity graph. The default two-row renderer replaces the rejected cramped text prototype with matched SF Symbol
arrows and identical monospaced typography. Values are right-aligned inside one stable field, so changing digit or
unit counts does not move the status item. Network settings offer 0, 1, or 2 decimal places; the selected precision
is applied consistently in the menu bar, accessibility value, preview, and dropdown.

The dropdown includes a dual download/upload history graph, interface picker, received and sent totals, copyable
local addresses, router and DNS values, Wi-Fi signal/noise/channel/transmit/security detail, and opt-in public
addresses. Settings include interface, bytes/bits, decimal precision, public-IP privacy, automatic/fixed graph
scale, graph style, colors, and sampling interval.
Graph style remains editable in every display mode so a user can configure it before switching to the graph.

User review also exposed a confusing color-control layout. All module panes now use canonical light-appearance and
dark-appearance rows. General settings add an optional global palette that resolves through the shared status-item
render context for every module without erasing saved per-module colors. Color rows explain when Monochrome mode or
the global palette makes a local picker inactive. The settings schema migrates older data to these defaults.

Phase 4's Sensors specification now requires multiple independently movable temperature widgets. Each widget has an
arbitrary ordered sensor selection and uses the same matched-type, stable-decimal discipline as the Network rows;
additional readings flow into compact two-row columns rather than being limited to a hard-coded CPU/GPU pair.

Verification:

- `swift test` rebuilt and linked all application and test targets and exited 0. Tests cover all four Network menu
  bar modes, stable two-row geometry, 0/1/2 decimal formatting, precision migration, counter resets, selected
  interface fallback, global palette migration, and global/per-module color resolution.
- `swift run mbs-probe net` reported `42.64 GiB` received and `124.83 GiB` sent for `en0`. The simultaneous
  `netstat -ibn -I en0` row reported 45,788,408,839 received bytes and 134,032,184,210 sent bytes, which convert to
  the same binary totals. This check caught and verified the IFMIB 64-bit correction without generating test
  traffic.
- `make run` release-built, ad hoc signed, installed, and launched `/Applications/Barometer.app` from the one
  application bundle. `codesign --verify --deep --strict --verbose=2` reported it valid on disk and satisfying its
  designated requirement.
- The live Retina capture at `dist/menubar-network-closeup.png` showed CPU, Memory, Network, and Weather as separate
  movable items. Network displayed equally sized, aligned download and upload rows with a consistent decimal.
- The defaults domain retained the fixed `Barometer.Network` status-item visibility key alongside the other nine
  permanent identities. The read-only Thaw defaults query returned no stored Barometer identifier because Thaw was
  not running; Barometer did not launch or modify Thaw.
- `git diff --check` passed, and the changed Swift files contain no lines longer than 120 columns.

## P3-T3 Disk source

Added a read-only Disk source that enumerates mounted volumes with `FileManager`, reports total/used/available
capacity, classifies internal/external/network attachment, and records removable, ejectable, and read-only state.
Mount sources are resolved with `statfs`. APFS synthetic volume names are walked through the IOKit service plane to
their physical `IOBlockStorageDriver`, so the root volume's `disk3s3s1` mapping correctly resolves to physical
`disk0` rather than relying on an invalid string-prefix assumption.

Physical-device sampling reads cumulative bytes, operations, and errors from the block driver's `Statistics`
dictionary and resolves the hardware product name from its parent Device Characteristics. The initial `DiskMonitor`
turns those counters into read/write bytes per second and operations per second, rejects counter resets, and keeps
volume and physical-device state in one timestamped sample. `mbs-probe disks [--watch]` exposes all of this without
creating status items or writing benchmark data.

Verification:

- `swift test --filter 'Disk|disk'` rebuilt the source, monitor, probes, and tests and exited 0. Coverage includes
  mounted root-volume capacity invariants, volume classification, mount-source parsing, elapsed-time rates, first
  samples, and counter resets.
- `swift run mbs-probe disks` reported the 926.35 GiB Macintosh HD with 321.04 GiB available, mapped its APFS root
  volume to `disk0`, and identified the physical device as `APPLE SSD AP1024Z`.
- A short `swift run mbs-probe disks --watch` observation showed ordinary background rates changing across samples,
  including 294.0 KiB/s read and 640.0 KiB/s write. No `dd`, benchmark, speed test, or temporary payload was used.
- `git diff --check` passed, and all changed Swift files stay within 120 columns.

## P3-T4 Disk module

Completed the independent `Barometer.Disks` status item, scheduler, mount-change refresh, dropdown, and settings pane.
Menu bar modes include a bidirectional activity graph with reads above and writes below the centerline, free-space
percentage, compact free bytes, and matched read/write rate rows. The graph supports line, area, and bar styles, and
graph style stays editable before the user selects the graph mode.

The dropdown shows aggregate read/write activity, a live bidirectional history graph, user-facing volume usage bars,
mount points, free capacity, physical device names, per-device rates and operations, and eject buttons only for
removable or ejectable volumes. Eject uses AppKit's throwing `unmountAndEjectDevice(at:)` API and surfaces failures
inline. Settings select the free-space volume, independently hide any listed volume, hide macOS implementation
volumes as a group, choose decimal or binary units, set the sampling interval, and use either module colors or the
global palette.

`VolumeMountWatcher` observes mount, unmount, and volume-rename notifications without polling and immediately
refreshes the existing scheduler. Disk sampling joins CPU, Memory, Network, and Weather in display-sleep and
battery-aware scheduling. The settings schema migrates prior builds to the Disk defaults without changing saved
Network decimals, global colors, or other module preferences.

Verification:

- `swift test` rebuilt and linked all targets and exited 0. Tests cover rate calculation and reset handling,
  binary/decimal formatting, hidden and system-volume filtering, startup/selected volume fallback, settings
  migration, all four menu bar modes, and bidirectional graph construction.
- `make run` release-built, ad hoc signed, installed, and launched `/Applications/Barometer.app`. The running
  process is the single bundled executable; no helper was created.
- A temporary 100 MB APFS `MBSTest` disk image appeared as an external volume with 98.9 MiB free, then detached
  cleanly. Unified logging recorded `Mounted-volume list changed` for both attachment and ejection. The image and its
  temporary directory were deleted afterward.
- The dropdown's AppKit eject action compiled against the current macOS 27 SDK. Automated clicking was not attempted
  because `osascript` lacks Accessibility access, and the project rules prohibit requesting a new TCC permission for
  this check. A user click remains the appropriate final interaction check for a removable test volume.
- `codesign --verify --deep --strict --verbose=2 /Applications/Barometer.app` reported the bundle valid on disk and
  satisfying its designated requirement.
- The runtime identity report recorded `Barometer.Disks`, accessibility label `Disks`, an empty button title and AX
  title, and owner bundle `com.barometer.app`. The item remains permanently allocated and hidden with `isVisible`
  when disabled.
- `git diff --check` passed, and all changed Swift files stay within 120 columns.

## P4-T1 C shim target

Expanded the existing `CSystemSources` bridge into the single declaration boundary for hardware-private APIs. It now
defines the IOHID temperature and power event types and field calculation; declares the event-system client, service
event, and floating-value functions; declares IOReport channel discovery, merging, subscriptions, samples, deltas,
simple values, and state residency; and defines the read-only AppleSMC external-method ABI structs and read command
constants.

The bridge imports Apple's public IOHID client/service reference types from the installed SDK and declares only the
private entry points missing from those headers. The SMC surface intentionally exposes no write command constant or
write wrapper. All declarations remain in `CSystemSources`; higher layers will access one wrapper type per private
source rather than redeclaring symbols.

Verification:

- `swift build` recompiled `shim.c`, every Swift target, `mbs-probe`, and Barometer and completed successfully.
- The installed SDK's IOHID headers and the current Stats Sensors bridge were compared for pointer ownership,
  integer widths, and IOReport return types before the declarations were added.
- P4-T1 introduces declarations but no IOReport call sites, so the plan's `nm` symbol check remains intentionally
  pending until P4-T3 links the first IOReport source.

## P4-T2 IOHID temperature source

Added an actor-isolated IOHID temperature source that creates one event-system client, caches the matched service
list, and reuses both across samples. Each read fetches current temperature events, discards non-finite, nonpositive,
and implausibly high values, then averages duplicate product names. Friendly labels map PMU die sensors, the battery,
SSD, and PMU calibration sensor without losing their raw hardware names.

The C shim now exposes the event-field calculation and balanced event release as ordinary functions because Swift
cannot import the function-like field macro or directly release the private opaque event pointer. Client and service
objects remain under Swift Core Foundation ownership. `mbs-probe temps` prints the normalized name, Celsius value,
raw name, and number of duplicate services contributing to each reading.

Verification:

- `swift test` rebuilt and linked every target and exited 0. Deterministic coverage verifies friendly naming,
  invalid-value rejection, duplicate averaging, and sample counts; a live smoke test verifies unique, valid sensors.
- `swift run mbs-probe temps` reported Battery at 31.40 °C, SSD at 34.00 °C, PMU at 51.82 °C, and all 14 SoC die
  sensors between 50.15 °C and 55.83 °C. No negative `PMU tdev` readings were emitted.
- The raw machine exposed three same-named IOHID services per die and six battery services. The source averaged those
  duplicates and retained their counts instead of arbitrarily selecting one service.
- `swift build` completed under Swift 6 strict concurrency. `git diff --check` passed, and all changed Swift files
  stay within 120 columns.

## P4-T3 IOReport source

Added a cached IOReport source with independent runtime-discovered subscriptions for `Energy Model`, the older
`PMP` energy-counter fallback, `CPU Stats`, and `GPU Stats`. Each reading uses two snapshots across one monotonic
interval and Apple's delta function. Energy conversion honors the channel's reported J/mJ/uJ/nJ unit, strips the
`INT64_MIN` unpopulated sentinel, and avoids double-counting core rails when aggregate cluster rails are present.

Frequency tables are discovered from every `pmgr` property whose name begins with `voltage-states`; no Mac model,
core count, or voltage-state property number is compiled into Barometer. Raw Hz, kHz, and MHz tables are normalized
by magnitude, repeated states remain in index order, and runtime state counts select lower-, middle-, upper-tier CPU
and GPU tables. DOWN, IDLE, and OFF residency is excluded from the active-frequency weighted average but included in
the active percentage denominator. Raw states and energy channels remain in the source model for field diagnostics.

The CLT SDK contains no IOReport link stub even though `/usr/lib/libIOReport.dylib` is present in the dyld shared
cache. Direct references therefore failed at link time on macOS 27. The C bridge now opens that system path and
resolves every IOReport symbol behind null checks. A removed framework or symbol makes the source unavailable rather
than preventing Barometer from launching.

Verification:

- `swift test` rebuilt and linked every target and exited 0. Tests cover exact J/mJ/uJ/nJ conversion, dynamic Hz/kHz
  normalization, repeated performance states, residency weighting, aggregate CPU-rail recognition without fixed
  core counts, and live runtime-discovered IOReport channels.
- `swift run mbs-probe freq` discovered seven distinct frequency tables at runtime. Representative readings were
  ECPU 733 MHz, PCPU 4,355 MHz, and GPU 338 MHz; all carried live active-residency percentages and state names.
- `swift run mbs-probe power` reported GPU power and ANE availability consistently. One idle sample also reported
  CPU 1.127 W and DRAM 0.190 W from aggregate cluster rails. Subsequent macOS 27 samples, including a temporary
  four-process CPU load, marked every CPU rail unpopulated while GPU continued changing. Barometer reports CPU power
  unavailable for those intervals rather than `0 W` or a sentinel-derived negative value. P4-T4 will test read-only
  SMC power keys as the nearest legitimate fallback; no value was invented and all temporary load processes exited.
- `nm .build/debug/mbs-probe | grep -c IOReport` returned 465, confirming the bridge and source are present in the
  linked probe despite runtime resolution. `git diff --check` passed, and all changed Swift files stay within 120
  columns.

## P4-T4 SMC source

Added an original actor-isolated AppleSMC client that opens the standard user client without privileges and exposes
only metadata, index enumeration, and byte-read commands. The C ABI intentionally contains no write command. Key
metadata is cached by four-character code; full key enumeration and the runtime-curated list of numeric temperature,
power, current, and voltage sensors are each cached for the connection lifetime.

The value model preserves raw bytes and type metadata while decoding big-endian unsigned integers, little-endian
floats, unsigned fan fixed point, generic signed and unsigned 16-bit fixed point, fan descriptions, and character
arrays. Fan discovery uses the reported `FNum` count and reads current/minimum/maximum speeds without changing modes
or targets. `mbs-probe smc --list` and `mbs-probe fans` expose the source for testing and future hardware reports.

Verification:

- `swift test --filter SMC` rebuilt and linked the decoder and live-hardware tests and exited 0. Coverage includes
  integer, float, signed/unsigned fixed-point, string, four-character-code, key enumeration, and fan paths.
- `swift run mbs-probe smc --list | wc -l` returned 3,462 keys, well above the plan's 100-key threshold.
- The live SMC probe reported two fans around 1,350 and 1,460 RPM, with 1,350 RPM minima and 5,777 RPM maxima.
- Read-only power keys included `PSTR` at 28.67 W, `PZC0` at 9.32 W, `PZC1` at 12.49 W, and charger power `PHPC`
  at 8.25 W during the sample. These remain raw runtime-discovered sensors; no Mac model or count selects them.
- `rg` confirmed no SMC write command or write method exists in the bridge or source. `swift build`,
  `git diff --check`, and the 120-column check passed.

## P4-T5 Sensors module

Added `SensorsMonitor`, which independently samples IOHID, AppleSMC, and IOReport and merges every available source
into normalized temperature, fan, power, voltage, and current groups. The monitor derives hottest overall, CPU, and
GPU temperatures at runtime, rejects SMC calibration and threshold values that are not credible live operating
temperatures, and continues reporting remaining sources when one private interface is unavailable. It contains no
model identifier, core-count table, or hardware-specific branch.

IOReport power deltas now accumulate GPU, ANE, CPU, and DRAM energy whenever those rails are populated. The known
`PSTR` whole-system SMC rail uses trapezoidal integration between fresh samples. Both paths reject non-finite,
negative, and stale intervals and expose resettable session totals in joules or watt-hours. Missing or unpopulated
rails remain unavailable rather than becoming invented zero readings.

The AppleSMC audit added a compile-time 80-byte ABI assertion, rejects short transport responses, and decodes signed
integer, `iof`, and Apple Silicon `ioft` values. Direct inspection of runtime keys confirmed that `ioft` is required
for real GPU and thermal readings on this Mac. Numeric decoding remains separate from sensor semantics, so a numeric
threshold or configuration key is not automatically presented as a live temperature.

Completed the Sensors dropdown with grouped sparklines, source labels, selectable Celsius or Fahrenheit formatting,
configurable zero-to-two decimal places, duplicate hiding, and resettable session energy. The normal UI exposes only
human-readable summaries and verified roles. Undocumented SMC identifiers such as `Tp…` and `PP…` stay behind the
explicit advanced firmware-sensors toggle; old widgets selecting one fall back to useful temperature and fan data.
Settings expose line, area, and bar graph styles without disabling the control. Every menu bar widget supports text,
compact two-row stack, history graph, and fan modes. Users can create multiple separate widgets and arrange any
ordered set of discovered readings in each one. Values reserve stable numeric widths, while additional pairs expand
into new two-row columns.

Each widget is a permanent status item owned by the packaged app process. Instance one remains
`Barometer.Sensors`; later instances are `Barometer.Sensors.2`, `.3`, and so on. Removed widgets become disabled
tombstones, so an identity is never reused. The title remains empty and live readings only update AXValue.

Read-only inspection of the installed iStat Menus archive's English localization confirmed its public sensor
categories and presentation vocabulary: temperature, fan RPM, amperage, frequency, power, voltage, simple/detailed
views, raw sensor labels, and dual-value menu bar presentation. It did not contain a readable cross-model raw-key
table. Barometer therefore retains its original runtime enumeration and conservative generic labeling rather than
copying proprietary mappings. VirtualSMC, SMCKit, iSMC, macpow, and power-monitor source were consulted only to
cross-check the public AppleSMC transport convention and byte formats; no source was copied.

Verification:

- `swift test` rebuilt and linked all source, core, UI, and test targets and exited 0. New coverage verifies signed,
  floating, and `ioft` SMC decoding; settings schema 7 migration; widget identity normalization and non-reuse;
  Celsius/Fahrenheit precision; duplicate preference; stale-sample rejection; trapezoidal energy integration; all
  four widget modes; stable stack geometry; and horizontal expansion for four selected readings.
- `swift run mbs-probe sensors` reported a hottest temperature of 76.98 °C, GPU temperature of 55.22 °C, both fans
  at 1,357 and 1,433 RPM, system power at 20.29 W, adapter power at 30.42 W, battery power at 0.69 W, GPU power at
  0.65 W, and live session energy. Values vary with workload and cooling state.
- `swift build -c release` completed successfully. Swift 6.2.3 initially diagnosed an optimizer cycle while importing
  actor-isolated destructors. Immutable IOReport subscription handles now have a documented Sendable boundary and
  are released by a nonisolated destructor; the optimized build retains strict concurrency and completes normally.
- `make app` produced `dist/Barometer.app`. `codesign --verify --deep --strict --verbose=2` reported it valid on disk
  and satisfying its designated requirement. Its identifier is `com.barometer.app`, and its only executable is
  `Contents/MacOS/Barometer`.
- `make install` replaced and launched `/Applications/Barometer.app`. The runtime identity report contains
  `Barometer.Sensors`, AX label `Sensors`, empty button and AX titles, and owner bundle `com.barometer.app`. The item
  remains allocated but hidden because the user's Sensors preference is currently disabled.
- `git diff --check` passed, and all changed Swift files stay within 120 columns.

## P4-T6 GPU source and module

Added `GPUAcceleratorSource`, a vendor-neutral IORegistry reader that enumerates `IOAccelerator` services and parses
their live `PerformanceStatistics` dictionaries. It reports device, renderer, and tiler utilization plus system,
allocated, and driver memory when each published key is valid. Names come from the live service; no model identifier
or accelerator class is compiled into the selection logic.

Extended the existing IOReport wrapper to read current GPU temperature gauges alongside power and performance-state
residency. Temperature scaling is inferred from each runtime value and constrained to credible operating values.
`GPUMonitor` combines accelerator utilization and memory with optional IOReport frequency, activity, power, and
temperature. SMC GPU temperatures are a read-only fallback when IOReport does not publish a usable gauge.

Completed the independent `Barometer.GPU` status item, scheduler, dropdown, and settings pane. Menu bar choices are
a stable-width labeled percentage, line/area/bar history graph, or optional CPU/GPU rows. The GPU remains its own
movable status item by default. The dropdown presents utilization history, device/renderer/tiler values, memory,
frequency, power, and temperature using the global hardware Celsius/Fahrenheit preference. Sampling participates in
display sleep and battery-aware scheduling; module and global color behavior matches the other modules.

Verification:

- `swift test` rebuilt and linked all targets and exited 0. New tests cover runtime statistics parsing, invalid
  utilization rejection, temperature scaling and sentinels, live IOAccelerator discovery, IOReport temperature
  bounds, and every GPU menu bar mode.
- `swift run mbs-probe gpu` reported 44.0% device, 43.0% renderer, and 29.0% tiler utilization; 3.27 GiB in use of
  8.11 GiB allocated; 338 MHz; 0.49 W; and 55.9 °C.
- A short `swift run mbs-probe gpu --watch` observation reported 35–41% device utilization across six consecutive
  samples, satisfying the plan's above-20% activity check without adding a benchmark or speed test.
- `make install` completed an optimized release build, ad hoc signed and installed the single
  `/Applications/Barometer.app` bundle, and launched it. `codesign --verify --deep --strict --verbose=2` reported the
  installed bundle valid on disk and satisfying its designated requirement.
- The runtime identity report contains `Barometer.GPU`, AX label `GPU`, empty button and AX titles, and owner bundle
  `com.barometer.app`. The status item remains allocated but hidden while the saved GPU toggle is off.
- `git diff --check` passed, and all changed Swift files stay within 120 columns.

### Compact menu bar geometry follow-up

Standardized every two-row renderer on one shared grid and one compact point size. CPU, memory, GPU, Sensors,
network, and weather now use identical upper and lower row centers. Sensors compose each label and reading into one
attributed line so proportional labels and monospaced temperatures share a real text baseline. Internal content
insets, sensor label gaps, and column gaps are reduced without changing the user-controlled spacing value. GPU now
reserves the compact `0–99%` range instead of permanently reserving an extra digit for the rare exact `100%` reading.

The network stack now places compact down/up arrow glyphs directly beside its readings and uses one-character rate
suffixes in the menu bar while retaining full units in the dropdown. Stable-width placeholders still reserve the
selected decimal precision and the normal two-digit magnitude. A live three-digit rate expands the canvas instead
of clipping. Kilobytes per second, or kilobits per second in bit mode, are the minimum display units, preventing
idle traffic from constantly changing raw byte-level values. Temperature placeholders reserve credible Celsius and
Fahrenheit maxima instead of an unnecessarily wide three-digit value in both scales.

Weather's default display now stacks the condition glyph over the temperature. Its existing status item and mode
identifier are unchanged, so the item remains independently movable and existing settings migrate without action.
Long condition text continues using the horizontal presentation selected by its separate mode.

The Sensors dropdown now explains that session energy is energy used since Barometer opened and spells out `joules`
and `watt-hours` instead of showing unexplained `J` or `Wh` abbreviations.

The Network monitor now samples macOS's own cumulative per-process external-network accounting every five seconds,
calculates download and upload rates, resolves executable paths to application display names, and exposes the ten
most active processes. The dropdown shows configurable top-process rows with real app icons and separate download
and upload rates. The source degrades to an explicit unavailable state and never requires root, a bundled helper, or
a hardware-specific identifier.

Verification:

- `swift test` rebuilt and linked every target and exited 0. Added coverage verifies that stacked weather is narrower
  than horizontal icon-and-temperature rendering, network and sensor canvases remain stable as values change, and
  session-energy units use plain language. Process-network coverage verifies CSV quoting, PID extraction, duplicate
  row aggregation, and invalid-row rejection.
- `swift build -c release` completed successfully.
- `swift run mbs-probe net --watch` produced per-process deltas after the second five-second accounting snapshot. A
  live sample resolved ChatGPT, Spotify, mDNSResponder, Codex (Service), Vivaldi Helper, and Dropbox, with independent
  receive and send rates. The probe was then stopped and no sampling process remained running.
- `make install` rebuilt, signed, installed, and launched the first density build. After the GPU width adjustment, a
  normal AppleScript quit request did not return while the running app was in use. Only that Barometer process was
  terminated; the final bundle was copied to `/Applications/Barometer.app` and relaunched directly.
- A live Retina menu bar capture at font size 10 and spacing 0 confirmed matching two-row baselines, directly adjacent
  network arrows and values, baseline-aligned CPU/GPU sensor rows, and the weather glyph centered above `75°F`. The
  runtime identity report measured CPU at 21 points, GPU at 23 points, memory at 23 points, and weather at 13 points;
  GPU was 29 points before removing its permanent `100%` reservation. Network fell from 50 to 44 points after using
  the two-digit rate reservation, and the installed menu bar showed `↓4.53K` and `↑4.24K` without byte-level units.
- `codesign --verify --deep --strict --verbose=2 /Applications/Barometer.app` passed. The installed identifier remains
  `com.barometer.app`, and `Contents/MacOS/Barometer` remains its only executable.
- `git diff --check` passed, and all changed Swift files stay within 120 columns.

### Fixed network width follow-up

Compact network rates now promote to the next unit before rounding would require a third integer digit. For example,
`99.99K` advances to `0.10M` instead of expanding to `100.00K`. The existing two-digit fixed-width reservation can
therefore cover normal rates across K, M, G, and T units without moving neighboring status items or restoring the
visibly empty three-digit slot. Full dropdown rates retain conventional 1,000-based unit boundaries.

Verification:

- `swift test` exited 0. New coverage checks the rounding boundary, unit promotion, conventional full-rate format,
  and identical rendered widths across compact K, M, and G values.
- `swift build -c release` and `make app` completed successfully. The final bundle was installed and launched from
  `/Applications/Barometer.app`; strict code-signature verification passed.
- With the saved one-decimal setting, the runtime identity report records a 38-point Network image and status item.
  That reservation now remains 38 points as live rates promote between compact units.
- `git diff --check` passed, and all changed Swift files stay within 120 columns.

## P5-T1 Battery source

Design alternatives considered before implementation:

- IOPS alone uses a public normalized API and provides charge state and time estimates, but not the detailed health,
  current, voltage, temperature, cycle, or adapter values required by the design.
- IORegistry alone exposes the detailed runtime keys, but state and time fields are less stable across hardware and
  OS versions. The selected design merges IOPS summary data with optional runtime `AppleSmartBattery` and
  `AppleSmartBatteryPack` properties and degrades each missing field independently.

Implemented a normalized battery source that combines IOPS charge/state estimates with optional battery-pack,
electrical, thermal, health, cycle, condition, low-power-mode, and adapter details. Signed current conversion handles
the unsigned integer representation published by IORegistry. Time remaining is shown only while charging or
discharging, so a Mac connected to AC without actively charging does not present a false zero-minute estimate.

Verification:

- `swift test --filter BatterySourceTests` rebuilt the package and exited 0. Coverage verifies signed 32-bit current,
  battery temperature scaling and invalid sentinels, capacity-based health, and live value ranges.
- `swift run mbs-probe battery` reported the internal battery at 90.0% on AC, 99.9% health, 45 cycles, 31.29 °C,
  12.570 V, 0.000 A, and 0.00 W. It identified the connected 140W USB-C Power Adapter and correctly reported time
  remaining as unavailable in the on-AC state.
- `swift build` and `git diff --check` completed successfully.

## P5-T2 Battery module

Implemented the permanent `Barometer.Battery` item, ten-second scheduler, immediate power-source refresh path,
bounded charge history, and four compact presentations: labeled percentage, a charge-level glyph, remaining time,
and signed-direction-neutral wattage. The item can remain hidden while AC is connected without being removed, so its
identity and saved menu bar position remain stable. Percentage, time, and wattage canvases reserve their maximum
normal widths to prevent neighboring items from shifting.

The dropdown now shows charge history, state, remaining time, Low Power Mode, condition, maximum capacity, cycle
count, Celsius or Fahrenheit temperature, voltage, signed current, signed power, and connected adapter details.
Settings expose visibility on AC, display mode, sampling interval, normal module colors, and the low-battery warning
threshold. Missing source fields remain explicitly unavailable.

Verification:

- `swift test --filter BatteryTests` exited 0. Coverage verifies production settings defaults, consistent time and
  wattage formatting, injected source mapping, all four renderer modes, accessibility text, and stable 42-to-100%
  image geometry.
- `swift run mbs-probe battery` reported 90.0% on AC, 99.9% health, 45 cycles, 31.09 °C, 12.571 V, and the 140W
  USB-C Power Adapter. Time remaining correctly stayed unavailable while connected but not charging.
- The power observer now refreshes Battery immediately on AC/battery transitions in addition to changing sampling
  multipliers. Physical unplug/replug confirmation remains a live installation check.
- `git diff --check` passed, and the changed Swift files contain no lines longer than 120 columns.
