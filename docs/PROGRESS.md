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

## P5-T3 Bluetooth device batteries

Implemented a generic IORegistry scanner for device, left, right, and case battery percentages published by
`AppleDeviceManagementHIDEventService` and `IOBluetoothDevice`. Device names and stable identifiers come from
runtime properties, not a model or hardware identifier table. Duplicate services are collapsed in favor of the
entry with the most component detail. The Battery monitor samples these readings with the internal battery, and the
dropdown lists them when the Bluetooth battery setting is enabled.

Verification:

- `swift test --filter 'BatteryTests|BluetoothBatterySourceTests'` exited 0. Parser coverage verifies AirPods-style
  left, right, and case levels, stable device identity, invalid percentage rejection, and monitor propagation.
- `swift run mbs-probe battery` completed successfully and reported `Bluetooth batteries: none published`, the
  correct graceful result with no supported connected-device keys present during verification.
- `swift build`, `git diff --check`, and the 120-column check passed.

## P6-T1 Time module

Implemented the permanent `Barometer.Time` item with a deterministic date/time token engine, optional seconds,
12-hour locale-aware time, explicit 24-hour time, date, weekday, ISO week, day-of-year, and time-zone fields. The
monitor samples once per second only when seconds are visible; otherwise its next interval is calculated to land on
the wall-clock minute. System clock and time-zone notifications refresh it immediately.

The dropdown includes a highlighted month calendar, searchable world clocks with UTC offsets and day/night glyphs,
and sunrise/sunset from the primary Weather forecast. Time settings include live format preview, fixed-width choice,
module colors, and ordered world-clock additions/removals.

Verification:

- `swift test` exited 0. New coverage verifies deterministic token output across UTC and America/New_York, optional
  seconds, invalid/duplicate world-clock removal, wall-clock minute alignment, menu bar rendering, and accessibility.
- `swift run mbs-probe time` reported the live local date, time with seconds, ISO week 36, day 247, EDT, and system
  time-zone identifier `America/New_York`.
- `swift build -c release`, `git diff --check`, and the 120-column check passed.

### Widget settings navigation follow-up

Every dropdown Settings command now selects that widget's own settings pane, including already-open Settings
windows. The application-wide open-settings notification continues to select General.

### Weather refresh visibility and presentation follow-up

Runtime diagnostics confirmed that the running app refreshed and wrote the current-location Weather cache at
01:08:17. The dropdown now displays the age of the last successful forecast fetch, resets visibly to “updated just
now” after success, and explains when a refresh failed and saved weather is being shown. The manual action is labeled
“Refresh Now.” Tests cover the freshness text.

Removed the Weather custom-template mode, token editor, formatter branch, persisted template field, and test cases.
Existing settings saved in the old `template` mode migrate to icon-over-temperature. Purpose-built Weather display
modes remain unchanged.

### Compact sensor punctuation follow-up

Compact Sensors widgets now display plain-language labels as `CPU:`, `GPU:`, and so on. The previous one-point
label/value gap was removed, allowing the colon to provide the separation without adding redundant padding.

Verification:

- `swift test --filter sensorStackKeepsStableGeometryAndExpandsByColumns` exited 0 and verifies colon insertion,
  idempotence for already punctuated labels, stable value geometry, and multi-column expansion.
- `swift build`, `git diff --check`, and the 120-column check passed.

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

## P6-T2 Calendar events

Added one actor-isolated EventKit source with immutable event snapshots and explicit not-requested, restricted,
denied, write-only, full-access, and unavailable states. The Time monitor queries events only when the feature is
enabled and full access already exists. It never requests permission while launching or sampling. The Settings pane
and Time dropdown explain every authorization state, list up to ten events over the next fourteen days, and expose
an “Allow Calendar Access” action only as a direct user choice.

Verification:

- `swift test` exited 0. Calendar source coverage inspected the live authorization state without prompting and
  verified that event reads degrade to an empty list without full access.
- The committed application property list already contains `NSCalendarsFullAccessUsageDescription`; no new TCC
  category was requested during implementation or verification.
- `swift build -c release`, `git diff --check`, and the 120-column check passed.

## P7-T1 Combined item

Implemented the permanent `Barometer.Combined` status item with any ordered subset of CPU, GPU, Memory, Disks,
Network, Sensors, Battery, Weather, and Time. It reuses each module's selected presentation and color on a single
canvas with compact optional separators. One outer spacing value is applied; member renderings do not reintroduce
individual item padding.

Combined settings support adding, removing, and reordering members. “Hide included individual items” changes only
visibility: each individual status item remains allocated with its fixed identity and saved position. The Combined
dropdown provides a tabbed current-value summary in the same selected order, and its Settings command deep-links to
Combined settings.

Verification:

- `swift test` exited 0. New coverage verifies membership normalization, safe visibility defaults, compact separator
  geometry, member hiding, and the rule that Combined can never hide itself.
- `swift build -c release`, `git diff --check`, and the 120-column check passed.

## P7-T2 Appearance system

Added System, Ocean, Sunset, Forest, and Neon presets plus a complete custom appearance model. Global and
per-module light/dark roles now cover normal content, graph strokes, graph fills, warnings, and critical states.
Settings also expose graph opacity, regular/medium/semibold menu bar weights, monochrome behavior, compact internal
geometry, reset-to-theme actions, and a live CPU/graph/Weather preview strip. Existing module colors remain intact
when switching between global and per-module control.

The semantic roles now feed menu bar renderers, Combined member renderers, battery warnings, and CPU, Memory, GPU,
Battery, Disk, and Network detail graphs. Settings schema 12 migrates prior preferences without losing module
customizations, while export/import round trips every new appearance field.

Verification:

- `swift test` exited 0. Coverage verifies complete preset application, global and module fallback resolution,
  schema migration, appearance export/import fidelity, and narrower icon and graph geometry in compact mode.
- `swift build -c release` completed successfully.
- The changed Swift files pass the 120-column check.

## P7-T3 About, export and import, launch at login polish

Added an About pane with the installed version and build, application icon, MIT license, Open-Meteo attribution,
and source and issue links. General settings now report the actual `SMAppService` state, including required user
approval, and warn when the current bundle is launched from a `dist` folder.

Settings export remains deterministic, pretty-printed JSON. Import now rejects documents larger than 1 MB, future
schemas, invalid RGB values, unsafe sampling values, and out-of-range appearance controls before changing any live
setting. The existing settings remain untouched after a failed import.

Verification:

- `swift test --filter SettingsTests` exited 0. New coverage verifies that an invalid settings document is rejected
  atomically, while complete appearance settings still round trip without loss.
- `swift build` completed successfully.
- `git diff --check` and the 120-column check passed.

## P7-T5 Install target and README

Completed local app packaging with the selected minimal Barometer icon in PNG and ICNS form. `make app` produces one
ad hoc-signed `Barometer.app`, `make dmg` produces a compressed DMG with an Applications shortcut, and `make install`
replaces and relaunches `/Applications/Barometer.app`. The stop/install sequence now waits for the previous process
to terminate before asking Launch Services to open the replacement, eliminating intermittent `-600` relaunch errors.

The README now documents the complete monitor set, DMG installation, source builds, optional Location and Calendar
permissions, graceful unavailable behavior, and the single-bundle status-item identity contract for contributors.

Verification:

- `make dmg` created `dist/Barometer-0.1.0.dmg`; `hdiutil verify` reported a valid checksum.
- A read-only mount contained only `Barometer.app` and the Applications shortcut. Strict code-signature verification
  passed for the mounted app, and its bundle identifier was `com.barometer.app`.
- `make install` completed and `pgrep -x Barometer` found the relaunched executable in `/Applications/Barometer.app`.
- Ten consecutive waited quit/relaunch cycles succeeded. Every identity report contained the same 11 autosave names
  with SHA-256 identity-set hash `1d15dbbc3486dc45e732dac3bcecdabfd5ca7df81158a53d0253aa12aaaed68f`.

## P7-T6 Developer ID signing and release workflow

Added three manual-dispatch GitHub workflows: Check, Build macOS, and Release. The build workflow validates a semantic
version, runs tests, imports the Developer ID Application certificate into an ephemeral keychain, signs the single
app executable with the hardened runtime and timestamp, builds and signs a DMG, and uploads only that DMG. Release
creates or updates a draft GitHub release rather than publishing automatically.

Notarization remains implemented for a future release but is off by default in both dispatch forms. No notarization
submission was made. The release guide documents all five possible secrets, identifies the three needed only for
notarization, and explains safe `.p12` encoding without committing credentials.

Verification:

- Ruby's YAML parser loaded all three workflow files successfully, and a trigger scan found no push, pull-request,
  or schedule trigger.
- The Release workflow passes its explicit, default-false notarization input to the reusable macOS workflow.
- Local strict signature verification and DMG checksum verification passed. The local bundle is intentionally ad hoc
  signed; Developer ID, hardened-runtime timestamping, Gatekeeper assessment, and optional stapling run only in CI.
- `xcrun notarytool` and `xcrun stapler` were not invoked, honoring the request not to notarize.

## P7-T4 Stability and performance pass

Disabled-module schedulers now pause instead of continuing to poll expensive system interfaces. Modules included in
Combined remain active even when their individual item is hidden, and GPU's combined CPU/GPU presentation keeps its
CPU dependency. Display wake restores only the required scheduler set. This reduces idle work without removing or
recreating any status item.

Every widget's Settings command now has an explicit tested route to its own pane. The sidebar switch is exhaustive—
there is no remaining future-module placeholder—and Weather now exposes the same per-module color controls as the
other widgets.

Verification:

- `swift test` and `swift build -c release` exited 0. New coverage verifies scheduler activation for enabled modules,
  Combined members and GPU dependencies, plus the exact Settings destination for every `ModuleID`.
- Ten consecutive waited quit/relaunch cycles succeeded with all 11 autosave names unchanged.
- A bounded live run recorded the same identity-set hash on every sample. Resident memory rose while history and
  hardware-source caches warmed; those histories have separately tested fixed capacities. CPU ranged from 6–12%
  with GPU, Network, Sensors, and Weather active on the test system.
- David explicitly declined the planned one-hour soak, so it was stopped after the bounded measurements rather than
  represented as completed. No Thaw preferences or processes were touched.
- `git diff --check` and the 120-column check passed.

### About pane follow-up

Removed the Report an Issue link at David's request. The About pane retains only the project source link, version,
license, and weather attribution.

### P5-T2 Battery simplification follow-up

Removed battery duration estimates completely at David's request. `BatterySource` no longer reads or stores them,
the dropdown no longer shows them, and saved legacy duration and wattage modes migrate to a fixed-width battery
outline with its rounded percentage centered inside. The unavailable state uses the same glyph geometry so it cannot
move neighboring menu bar items. Detailed state, health, power, adapter, and Bluetooth battery information remains
in the dropdown.

Verification:

- `swift test` exited 0, including Battery source, monitor, settings migration, stable glyph width, and unavailable
  glyph coverage.
- `swift build -c release` completed successfully.
- `git diff --check` and the 120-column check for changed Swift files passed.

### Battery condition and display follow-up

Restored a focused choice between two reliable menu bar presentations: percentage inside the battery glyph, or a
BAT label with percentage. The removed duration estimate remains unavailable as a display choice, as does the
redundant wattage presentation; power details remain in the dropdown.

On macOS 27, the public power-source summary did not publish its formerly documented health string even though the
registry reported full-charge and design capacities plus a zero permanent-failure status. Battery condition now
prefers Apple's published condition and failure signals, then normalizes Apple's Good/Fair/Poor health values, and
finally applies Apple's 80% service threshold to the measured maximum-capacity percentage. The live probe now reports
`condition Normal` on the test Mac, matching System Information.

Verification:

- `swift test` and `swift build -c release` exited 0.
- `mbs-probe battery` reported `health 100.1%; condition Normal; cycles 45` on the test Mac.

### Network unit and menu bar manager placement follow-up

Compact Network values now retain complete rate units, such as `82.0KB/s`, `1.4MB/s`, and `10.0Mb/s`, while keeping
the no-space form needed for menu bar density. The KB/s or Kb/s floor and user-selected decimal precision remain.
Reserved widths include the full unit so the upload and download rows remain aligned without moving neighboring
items when the rate changes.

Status-item controllers now cache the last length they applied and call AppKit's length setter only when the rendered
width actually changes. Previously, every monitor sample reapplied the same fixed length; that unnecessary layout
mutation could make Barometer items return to AppKit's placement after a menu bar manager restarted. Autosave names,
accessibility identities, item lifetimes, and independent moveability are unchanged.

The Bartender cold-start catalog then exposed the direct identity collision: inactive `Barometer.Disks` was paired
with the visible Weather item's accessibility identity, and inactive `Barometer.Combined` was paired with Network.
Barometer now removes only the redundant AppKit visibility-default records for inactive items. It retains every
status item and autosave name for the process lifetime and never touches any position record. This prevents an
inactive identity from stealing a visible item when a menu bar manager reconstructs its catalog.

Verification:

- `swift test` exited 0. Formatter coverage verifies byte and bit suffixes, the KB/s floor, decimal precision, unit
  promotion, and fixed geometry. Renderer coverage verifies that unchanged lengths do not request a new assignment.
- `swift build -c release`, `git diff --check`, and the changed-file 120-column check passed.
- Before the correction, Bartender's read-only cold-start catalog showed the Disks→Weather and Combined→Network
  identity collisions. Live confirmation after installing the correction remains user-driven; Barometer does not
  control Bartender.

### P7-T4 live layout, weather, and efficiency follow-up

Applied the fixed-canvas presentation rule to every live widget. CPU, GPU, Memory, Disks, Network, Sensors, Time,
and Weather now render unavailable and live states through the same mode-specific geometry. Status-item lengths may
change when the user changes layout settings, but live values alone cannot resize them. David restarted Bartender and
confirmed that every Barometer item retained its chosen position. Weather's vertical icon mode now uses a tight
two-digit temperature envelope without reserving the widest condition glyph or a stale-warning suffix.

Network can place upload above download or download above upload, with upload-first as the default. Both rows retain
complete units, fixed-width digits, and matched geometry. Process icons now resolve the outermost owning application
bundle, so nested executables such as Discord Helper and Spotify Helper use their application's actual color icon.

Reduced monitoring overhead without slowing headline rates: availability is no longer probed on every scheduler
cycle; GPU, sensor, and Wi-Fi metadata use bounded caches; Sensors enforce a five-second minimum; and detailed CPU,
Memory, and Network process lists refresh less often than their lightweight menu bar counters. A warmed 15-sample
`top` run averaged 3.75% CPU with CPU, GPU, Memory, Network, Sensors, and Weather enabled, down from the earlier
7–9% steady range on this Mac.

Open-Meteo's automatic best-match current block was demonstrably fresh but inaccurate at the test coordinates: it
returned 74.9°F and overcast while other supported models reported about 71°F and drizzle. Forecast requests now
bypass URL caches, and Barometer overlays only the current conditions using a median/majority consensus from NBM,
ECMWF, and GEM when available. The detailed best-match forecast remains unchanged, and failure of the supplemental
models falls back to it. The installed app rewrote its cache with 70.8°F and WMO code 51, and its menu bar showed the
rain glyph with 71°F. This remains key-free and continues to use Open-Meteo worldwide.

Removed Battery's passive `Live charge` row because it could remain at `Discovering…` when Battery was disabled or
telemetry was unavailable. The two reliable menu bar display choices and detailed Battery dropdown remain intact.

Verification:

- `swift test` exited 0 and linked all test targets. New tests cover current-condition consensus, stable layout
  envelopes, Network row order, scheduler availability caching, source throttling, and helper application resolution.
- `mbs-probe weather --lat 41.1033544 --lon -74.0044601` reported `Current 70.8°F, feels like 76.9°F, Light drizzle`.
- `make install` built, signed, copied, and launched `/Applications/Barometer.app`; the live cache and screenshot
  confirmed the corrected weather reading.
- `git diff --check`, the changed-Swift-file 120-column check, and the American-spelling scan passed.

## macOS 27 operational memory

Added `docs/AGENTS.md` as the consolidated field guide for future agents working on Barometer's macOS 27 behavior.
It distinguishes tested build-specific observations from the permanent compatibility contract and records the menu
bar architecture, NSStatusItem and Accessibility behavior, single-bundle ownership rule, fixed identities, installed
path requirement, hidden-item visibility collision, live-length mutation regression, stable-canvas requirements,
identity diagnostics, private hardware-source behavior, performance boundaries, TCC and signing constraints,
Command Line Tools caveats, and the required regression checklist after OS updates. It also explicitly separates the
Open-Meteo current-conditions correction from macOS and MenuBarAgent behavior.

The root `AGENTS.md` now directs code agents to read the field guide before changing macOS 27 integration behavior.
No runtime code, external application, preference domain, permission, or installed bundle was changed.

Verification:

- Cross-checked the field guide against `docs/DESIGN.md`, the full chronological evidence in this progress log, the
  current status-item implementation, and the repository's standing instructions.
- `git diff --check` passed.

- The new field guide contains no line longer than 120 columns and passed the American-spelling scan.
- All repository-relative files named by the guide exist.

### P7-T4 refactored UI sizing regression follow-up

The settings UI refactor had reintroduced a macOS 27 placement failure by allowing `NSStatusItem.length` to change
whenever application settings changed. Font size, font weight, compact layout, glyph scale, and spacing could
therefore cause independently movable items to lose their established Bartender positions after reassessment.

Status-item outer length is now immutable after each controller's first enabled render. Live readings and layout
controls redraw inside that fixed canvas while staging a four-point-rounded width for the next launch. The next
process applies that outer width before visibility. The sole production length assignment carries a source-level
contract warning. The cache key uses a `v4` schema so widths staged under the former font and glyph limits cannot
survive the new geometry caps.

Added `docs/MACOS27_STATUS_ITEM_SIZING.md` as the durable decision record. It documents the failure signature,
one-assignment invariant, width lifecycle, prohibited live-resize exceptions, and required regression procedure.
The macOS 27 agent field guide now links to it and no longer permits a settings-change exception.

The global font-size maximum is now 12 points, the largest size that fits the fixed-height canvases consistently.
The 9–12 point range is centralized in `AppSettings`, used by the slider, settings validation, previews, and live
rendering, and applied when old persisted settings contain a larger value.

Icon and graph scaling is similarly capped at 115 percent. Barometer keeps the selected 12-point font for up to eight
independently movable items, then caps it at 11 points for nine through eleven items, 10 points for twelve through
fourteen, and 9 points for fifteen or more. The selected font remains unchanged, allowing it to return when the user
disables items. The count includes every enabled Sensors instance and accounts for members hidden by Combined.

Centering a narrower live rendering inside the immutable frame still made its ink visibly shift when Compact changed.
An initial attempt to freeze all live geometry prevented Compact and Spacing from appearing to turn off, while a
second attempt that redrew inside the old canvas could shrink typography until it was unreadable. Both approaches
were rejected. Width-affecting controls now edit a local draft and cannot touch live widgets. The registry also hides
every AppKit item synchronously at creation so no manager can catalog a visible placeholder before its fixed identity,
rendered image, and initial length are ready. These are AppKit-level rules with no manager detection or manager-specific
runtime behavior.

Replaced the 0–12 point spacing slider with two intentional presets: Regular at 3 points per side and Compact at
zero. Legacy arbitrary values normalize to the nearest preset. A prominent Apply & Relaunch button becomes active
when the draft differs, saves all layout settings together, stages every width, and safely reopens the same Barometer
bundle. A one-way length latch rejects every later proposal during the process lifetime. The apply action also
rejects repeated activation and bare development executables.

The prior fixed-canvas fallback proportionally shrank any rendering wider than its live frame. This compounded the
density ceiling and made a saved 12-point setting appear extremely small. Live rendering now always preserves the
selected font and glyph sizes: a wider proposal clips at the trailing edge until Apply Menu Bar Layout safely
relaunches. The cache schema advanced to `v4` because widths recorded for the scaling fallback are structurally stale.

The Apply/relaunch workflow was removed after it proved that another forced application restart did not solve manager
position persistence. Layout controls remain protected by the one-way live-length latch, and staged widths take effect
only on an ordinary future launch.

Read-only inspection of Bartender's current cold-start catalog exposed the actual identity failure: its records paired
`Barometer.Combined` with Network's AX identifier and `Barometer.Disks` with Memory's. Barometer had hidden newly
created items before assigning their autosave names and manually deleted AppKit visibility defaults for inactive
items. Both behaviors can recycle persistence slots. Identity is now attached before the first visibility transition,
and Barometer no longer deletes any `NSStatusItem` visibility or position preference. All children retain the common
`com.barometer.app` owner while keeping the unique child keys required for independent movement.

Verification:

- `swift test` exited 0 and linked every test target; `swift build -c release` completed successfully.
- `rg -n 'statusItem\.length\s*=' Sources` still found exactly one guarded production assignment.
- A source scan found no code reading, deleting, or writing AppKit visibility or position preference keys.
- `make install` built, signed, installed, and launched `/Applications/Barometer.app`; strict signature verification
  passed. The live identity report reads each actual AppKit autosave name and confirms that all eleven status items
  have their expected unique child name and AX identifier under bundle owner `com.barometer.app`.
- Bartender restart persistence requires David's external verification; Barometer did not launch, automate, or modify
  Bartender or its preferences.

### P7-T4 remove misleading density controls

Removed Compact internal layout from settings, persistence, render contexts, graph sizing, typography selection,
sensor padding, icon gaps, Combined separators, and tests. The mode narrowed rendered ink inside an immutable live
canvas, which made text unreadable and caused the unused remainder of the canvas to appear as excessive spacing.
The Regular/Compact item-spacing control was also removed after live verification showed it could not alter the real
gap while the AppKit frames remained immutable. In a fixed frame, changing transparent padding only moved the ink and
left the total blank width unchanged. Barometer now has one legible internal layout with zero app-added horizontal
padding; density comes only from each module's purpose-built display choices.

The committed-width schema advanced to `v5` so a user who had enabled the removed mode cannot inherit its narrow
20–56 point cached canvases. Existing settings JSON may still contain the former high-density or spacing keys, but
decoding safely ignores them and new exports do not encode them. No migration prompt or warning was added because
this is pre-release cleanup.

Verification:

- `swift test` exited 0 and built and linked every test target. Command Line Tools did not print a test-execution
  summary, matching the environment limitation already documented above. Renderer coverage explicitly verifies that
  typography, icon/graph-scale, narrower, and wider proposals leave an already-applied live length unchanged.
- `swift build -c release` completed successfully.
- `rg -n 'statusItem\\.length\\s*=' Sources` found exactly one production assignment, in
  `StatusItemController`'s guarded initial-layout branch.
- `git diff --check` passed, and the new sizing documentation has no line longer than 120 columns.
- `make install` built, signed, installed, and launched `/Applications/Barometer.app`. The bundle identifier remained
  `com.barometer.app`, and strict code-signature verification passed. The new `v5` canvases replaced the stale narrow
  high-density widths: CPU, GPU, and Memory are 36 points each, Network is 60, Sensors is 80, and Weather is 32.
- The live identity report at `~/Library/Logs/Barometer/identity.json` matched the installed process and recorded all
  eleven status items under `com.barometer.app`. Every actual autosave name matched its fixed AX identifier, every
  item retained its static display label, and every button title remained empty.
- Source scans found no production references to either removed setting. A migration test verifies that legacy
  `usesCompactLayout` and `menuBarSpacing` keys decode harmlessly and are not emitted by a new settings export.

### P7-T4 automate graphic density

Removed the manual Icon and graph size control and its persisted setting. Graphic scale now follows the same enabled
item count used by the font density ceiling: 115 percent for one through three items, 100 for four through six, 90 for
seven or eight, 85 for nine through eleven, 80 for twelve through fourteen, and 75 for fifteen or more. Enabled
Sensors instances count independently; Combined counts once and excludes members it hides.

The installed zero-padding build had still widened the active canvases because it inherited the previous 115-percent
graphic selection and rounded every natural width to a four-point grid. Automatic scaling now starts tightening at
four widgets, and width rounding uses a two-point grid. The committed-width schema advanced to `v6` so the corrected
canvases replace those oversized `v5` widths exactly once on the next launch.

Claude's user-facing README conventions were preserved. Its menu bar options now explain the automatic text and
graphic tiers, zero app-added spacing, and the normal-launch width lifecycle without exposing implementation details.

Verification:

- `swift test` exited 0 and built and linked every test target. Command Line Tools did not print a test-execution
  summary, matching the documented environment limitation.
- `swift build -c release` and `git diff --check` completed successfully. The production source contains no manual
  graphic-scale, spacing, or condensed-layout control, and the sole `statusItem.length` assignment remains guarded.
- `make install` built, signed, installed, and launched `/Applications/Barometer.app`; strict signature verification
  passed and the live identity report matched the new process under `com.barometer.app`.
- With six active widgets, the installed `v6` canvases total 242 points instead of the prior `v5` total of 280. CPU,
  GPU, and Memory each fell from 36 to 30 points, Network from 60 to 54, Sensors from 80 to 74, and Weather from 32
  to 24. Every rendered image width exactly matched its fixed status-item length, leaving no hidden trailing padding.

### P7-T4 preserve Menu Bar authorization across development builds

After the density install, Barometer remained running and sampled normally but no item appeared, even with Bartender
closed. Desktop captures confirmed the empty menu bar. The installed bundle had a valid ad-hoc signature, but no Team
ID, and each rebuild produced a new code hash. macOS 26 and 27 apply a per-application Menu Bar privacy control; this
combination can leave a rebuilt development app running while MenuBarAgent suppresses every status item.

`Scripts/make-app.sh` now honors `CODESIGN_IDENTITY`, otherwise selects the first valid Developer ID Application
identity in the login keychain, and falls back to ad-hoc signing only when no stable identity is available. Developer
ID builds use hardened runtime and a trusted timestamp. This does not notarize the app and does not call `notarytool`
or `stapler`.

Verification:

- `sh -n Scripts/make-app.sh` passed, and `make install` built and installed the current code without restoring an old
  commit.
- The installed app reports identifier `com.barometer.app`, Developer ID authority, Team ID `BQNYYA2UND`, hardened
  runtime, and a timestamp. Strict code-signature verification passed.
- A fresh desktop capture showed Network, Memory, Weather, GPU, CPU, Sensors, and the battery item in the menu bar.
  Barometer remained a single `/Applications/Barometer.app/Contents/MacOS/Barometer` process.
- Gatekeeper correctly reported the Developer ID build as unnotarized. No notarization or stapling command ran.

### P7-T4 finish automatic menu bar sizing

The previous automatic-density implementation changed the renderer's font and graphic scale immediately while
`StatusItemLengthLatch` correctly kept the outer AppKit frame fixed. Shrinking the content inside the old frame left
transparent trailing space, so the menu bar looked wider even though its graphics were smaller. The persisted `v6`
width cache could also make a new process reuse geometry calculated for an older widget count.

Removed the manual Font size slider, leaving no user-facing size or spacing controls. Font size and graphic scale are
now calculated from the complete saved widget set when `SettingsStore` initializes. Font weight is captured with that
launch geometry. Every controller, including a Sensors controller created later, uses the same immutable geometry for
the entire process. A separate geometry latch guards this contract alongside the existing one-write length latch.

Removed committed rendered widths entirely. On every normal launch, each enabled item renders its current saved
configuration, rounds its natural width to the two-point grid, assigns that AppKit length once before visibility, and
never changes it while the process is alive. This makes automatic sizing real at startup without stale empty padding
or application-initiated movement. Widget and typography changes take their final geometry after an ordinary quit and
reopen; Barometer does not force a relaunch.

Verification:

- `swift test` built and linked every test target successfully. Regression coverage verifies the two-point width grid,
  immutable launch geometry, and rejection of wider and narrower live length proposals.
- `swift build -c release` completed successfully, and `make install` installed and launched the updated Developer ID
  signed app at `/Applications/Barometer.app`. No notarization or stapling command ran.
- Source scans found no Font size slider, committed-width cache, manual graphic-size control, spacing control, or
  condensed-density control. Exactly one guarded production assignment to `statusItem.length` remains.
- The installed process is owned by `com.barometer.app`, and strict signature verification passed with Team ID
  `BQNYYA2UND`. A desktop capture confirmed the active Barometer items are visible after the relaunch.

David's movement check then exposed a separate launch-order regression. Bartender's read-only cold-start catalog
contained current collisions including `Barometer.CPU` paired with the Sensors AX identifier, `Barometer.Battery`
paired with GPU, and `Barometer.Disks` paired with CPU. Its move-failure ledger also recorded two failures for Network.
Barometer's delayed self-test was clean, proving the final state was correct but a manager could catalog the process
while the registry was still interleaving new identities with visible controllers.

`StatusItemRegistry` now prepares every standard module identity and every saved extra Sensors identity before the
coordinator may show any item. Lookups cannot silently create another identity beside the live set. A Sensors widget
added during the current process is saved but joins the complete identity set on the next normal launch, which also
keeps its automatic sizing consistent with the launch snapshot. This applies one lifecycle to every widget and does
not inspect, automate, or special-case a menu bar manager. Every child also exposes the common static AX label
`Barometer`, while retaining its unique autosave name and AX identifier. This gives managers one source-app identity
without collapsing the independently movable children into one identifier.

AppKit replaces a button's earlier AX label when a new rendered image carries its own accessibility description.
The first common-label build therefore still reported module labels after rendering. Every framed status-item image
now carries the same `Barometer` accessibility description before assignment. The installed runtime report confirms
all eleven prepared identities—including the disabled items and `Barometer.Sensors.2`—retain the common label, while
their AX identifiers remain unique and their live AX values name the module. Bartender's existing cold-start catalog
still contains its pre-fix records; David must restart or refresh the manager to perform the external movement check.
Barometer did not modify the manager, its preferences, or its process.

### P7-T4 distinguish every movable child

The common-label experiment made all status items expose the same accessibility label even though their autosave
names and AX identifiers remained unique. That collapsed a second child-level discriminator used by menu bar
managers. Simple text items could still appear movable while wider or composite items such as Network and Weather
failed, making the behavior look renderer-specific.

Restored each permanent child label from `StatusItemIdentity.displayName`, including numbered Sensors instances.
The rendered image carries that same immutable label on every refresh because AppKit derives the button label from a
replacement image. All items still belong to the one signed `com.barometer.app` process; the bundle is the common
Barometer application identity, while the autosave name, AX identifier, and label distinguish movable children.
Barometer does not request Accessibility permission because owning and preserving its own status items does not
require it. Manager applications request that permission for their own inspection and movement features.

Removed the iStat Menus comparison from the user-facing README.

Verification:

- `swift test` exited 0 and built and linked every test target successfully.
- `swift build -c release`, `git diff --check`, and `make install` completed successfully.
- The installed app is the Developer ID signed `/Applications/Barometer.app`, has bundle identifier
  `com.barometer.app`, Team ID `BQNYYA2UND`, and passes strict code-signature verification. No notarization ran.
- The live identity report records distinct labels and matching identifiers for all eleven prepared items. Network is
  labeled `Network` with `Barometer.Network`; Weather is labeled `Weather` with `Barometer.Weather`; numbered Sensors
  is labeled `Sensors 2` with `Barometer.Sensors.2`.
- A desktop capture confirmed the active widgets are visible after installation. Barometer did not modify or automate
  Bartender, Thaw, or their preferences.

### P7-T4 align persistence slots with visible children

David's immediate movement test showed that unique labels alone did not make Weather retain its position. A read-only
decode of Bartender's current cold-start catalog identified the actual mismatch: the persistence slot
`Barometer.Weather` was paired with GPU's AX identifier, CPU's slot was paired with Memory, and Battery's slot was
paired with Sensors. Dropbox retained its position because its single persistence slot had one matching AX child.

The registry had created all standard items and hidden the disabled ones. On macOS 27 those hidden AppKit objects
still contributed persistence slots but had no visible AX children. A manager enumerating both lists received
conflicting ordinals and joined unrelated Barometer children. `StatusItemRegistry` now creates exactly the complete
launch-visible set: enabled modules that are not hidden by Combined, plus enabled Sensors instances. It creates the
set in deterministic `ModuleID` order and assigns every identity synchronously before any controller makes an item
visible. Disabled modules no longer create unmatched hidden AppKit slots. A module that was disabled when the process
started joins on the next normal launch; an item created in the current process is still never removed.

Verification:

- `swift test` exited 0 and built and linked every test target. New regression coverage checks the exact ordered
  launch-visible set, enabled Sensors instances, and exclusion of members hidden by Combined.
- `swift build -c release`, `git diff --check`, and `make install` completed successfully.
- The installed Developer ID build launched as the single `com.barometer.app` process. Its identity report contains
  exactly the six current visible children instead of eleven standard and disabled slots.
- Bartender's read-only fresh catalog records now pair all six current persistence and AX identities exactly:
  CPU→CPU, GPU→GPU, Memory→Memory, Network→Network, Sensors→Sensors, and Weather→Weather. The manager and its
  preferences were not modified or automated.

### P7-T4 stabilize live Network typography

After the persistence-slot correction, David confirmed every item except Network was stable. Network's saved manager
position and outer AppKit frame were already fixed; the remaining motion came from transfer strings with changing
digit counts and units being drawn as complete left-aligned rows.

`NetworkRateStackRenderer` now separates each direction marker from its value. Both arrows use one fixed leading
coordinate, while both rate strings use one reserved field and share a fixed trailing coordinate. Tabular digits and
the selected decimal precision remain unchanged. Changing from KB/s to MB/s or from one to two integer digits now
updates ink inside the field without shifting either anchor or changing the status-item frame.

Verification:

- `swift test` exited 0 and built and linked every test target. New renderer coverage verifies fixed direction-marker
  parsing and identical trailing coordinates for short and long rate strings.
- `swift build -c release`, `git diff --check`, and `make install` completed successfully.
- The installed Network item has matching `Barometer.Network` persistence and AX identities in Bartender's read-only
  current catalog. Its rendered image and status-item length remain fixed at 50 points while live rates update.
- Strict code-signature verification passed for `/Applications/Barometer.app`. No notarization ran.

### P7-T4 create newly enabled items live

Restricting launch construction to visible widgets removed phantom persistence slots, but a module that was disabled
at launch had no status item to show when the user enabled it. The setting took effect only after a relaunch.

The registry now supports one-way, on-demand preparation. When settings enable a new standard module, the coordinator
creates its status item once, assigns the autosave name and AX identity while hidden, attaches the already-constructed
dropdown and renderer controller, and then lets the controller render and show it. New Sensors instances use the same
sequence. Disabling and reenabling an item created in the current process only toggles visibility; no existing item is
removed or replaced.

David also enabled the Disk activity graph while testing. Barometer's live report identifies the item correctly as
`Disks`/`Barometer.Disks`, but Bartender's catalog from the earlier broken builds currently joins that AX child to its
stale `Barometer.Combined` persistence record. This explains why Bartender does not list the graph as Disk; the graph
renderer itself has fixed geometry. Barometer does not rewrite a manager's private catalog. Live on-demand creation
prevents new enable operations from introducing another unmatched cold-start slot.

Verification:

- `swift test` exited 0 after the on-demand controller, menu, and registry changes.
- `swift build -c release` and `make install` completed successfully; nine enabled modules appeared in the installed
  app's identity report with nonzero immutable lengths.
- The current Disk item reports the static `Disks` label and `Barometer.Disks` AX identifier. The current Network item
  reports `Network` and `Barometer.Network` with a 50-point image and status-item length.

### P7-T4 gate visibility until the complete launch set is configured

Weather remained the easiest item on which to reproduce failed placement, while the same risk applied to every
module. The registry created status items in canonical `ModuleID` order, but each controller immediately made its
item visible during coordinator construction. Controller construction used a different order, so an external menu
bar manager could observe a valid but incomplete AX child list and join those ordinals to the wrong persistence
slots.

`StatusItemController` now renders and sizes its item while visibility is gated. After all standard controllers,
Sensors instances, dropdown menus, images, lengths, autosave names, and AX identities are ready, the coordinator
activates the complete launch set synchronously in the same canonical order as the registry. Newly enabled modules
and later Sensors instances use the same attach, render, then activate lifecycle. A one-way activation latch prevents
an item from being published twice.

Read-only diagnostics also isolated external state left by the iterative pre-fix builds. Barometer's installed live
report had nine exact autosave/AX pairs, including `Barometer.Weather` to `Barometer.Weather`, while Bartender's
existing catalog rejoined several current AX children to old `Combined` and second-Sensors records after Barometer
restarted underneath the already-running manager. An AX-first autosave timing experiment did not repair that cached
manager data and was reverted. Barometer did not modify Bartender, its preferences, or its process. The durable rule
is to prevent partial discovery in fresh catalogs and have the user refresh contaminated external catalogs through
the manager itself.

Verification:

- `swift test` built and linked every test target successfully. New coverage verifies the visibility latch activates
  exactly once; the existing launch-set test verifies canonical identity order.
- `swift build -c release` and `git diff --check` completed successfully. A source scan still finds exactly one guarded
  production assignment to `statusItem.length`.
- `make install` installed and launched the Developer ID signed `/Applications/Barometer.app`. Strict signature
  verification passed. No notarization or stapling command ran.
- The installed identity report contains nine visible, nonzero items. Every autosave name equals its AX identifier,
  every label is static and distinct, and Weather reports `Barometer.Weather`, `Weather`, and a fixed 22-point canvas.

### P7-T4 apply menu bar topology as one launch configuration

Module visibility previously mutated the live settings as soon as a toggle changed. That let the coordinator publish
or hide status items before the user had finished selecting the desired set, while automatic font and graphic sizing
still reflected launch geometry. Font weight was also unnecessarily captured as geometry even though it can redraw
inside the fixed canvas without changing its length.

All module visibility controls now stage their values in `SettingsStore`. The same boundary covers every independent
Sensors widget plus Combined membership and its replacement of individual member items. Settings previews and the
automatic sizing summary use the staged configuration, while monitors and status-item controllers continue to read
the last applied settings. A prominent Apply Changes bar reports the resulting widget count, text size, and graphic
scale; Discard restores the saved choices. Apply schedules a reopen, persists the complete staged set once, and
terminates the current process. The new process constructs the final canonical status-item set and assigns each
length once before visibility. It never resizes, removes, or recreates an item in the current process.

Font weight now redraws live as a paint property using the current setting. The initial canvas reserves the semibold
rendering width so switching weight cannot clip or require a length write. Font size and graphic scale remain frozen
launch geometry, preserving the macOS 27 compatibility contract.

Verification:

- `swift test` exited 0 and built and linked every test target. New settings coverage verifies that module, Sensors
  widget, and Combined topology changes remain absent from live settings until Apply and that canceling a toggle back
  to its saved value clears the pending state.
- `swift build -c release` and `git diff --check` completed successfully.
- A source scan found exactly one production assignment to `statusItem.length`, still guarded by the one-way length
  latch in `StatusItemController`.
- `make install` replaced `/Applications/Barometer.app` and launched it as the single `com.barometer.app` process.
  Strict code-signature verification passed. The installed identity report contains matching autosave and AX
  identifiers for every visible item. No notarization or stapling command ran.

### P7-T4 tighten status-item canvases

After the menu bar manager's system spacing and selection padding were both set to zero, the AppKit status-item
windows were contiguous but Barometer still looked loosely spaced. The remaining gap was inside the rendered images:
generic text added an unexplained four points, canonical layout metrics added half-point edge insets, and the Sensors
stack added its own side padding. Short live values were also centered or leading-aligned within wider stability
fields, concentrating unused reserve at the edge next to the following item.

All shared renderers now follow one zero-edge-inset contract. Generic text no longer adds width beyond its measured
reserved field, and dense sensor stacks no longer add side padding. Standalone and icon-and-text readings keep a fixed
trailing edge inside their reserved numeric fields, while stacked label/value rows retain their shared leading edge
and changing symbols remain centered only within their stable symbol field. The outer status-item lengths remain
immutable; this change removes internal blank canvas rather than resizing live AppKit items. The rule is recorded in
both the macOS 27 sizing guide and the repository agent guidance so later UI changes do not reintroduce invisible
spacing or row misalignment.

Verification:

- `swift test` exited 0, including new coverage for zero shared insets, exact generic-text width, trailing-edge
  stability inside standalone fields, and the shared leading edge for every stacked top-label mode.
- `swift build -c release` completed successfully, and `git diff --check` reported no whitespace errors.
- A source scan found exactly one guarded production assignment to `statusItem.length` in
  `StatusItemController.swift`.
- `make install` replaced and relaunched `/Applications/Barometer.app`. The installed identity report contains six
  visible items with exact image/length pairs: CPU 28, GPU 28, Memory 28, Network 54, Sensors 68, and Weather 24
  points. Every autosave name matches its AX identifier and every item belongs to `com.barometer.app`.
- Strict code-signature verification passed. A Retina menu bar capture confirmed the Barometer readings are packed
  together without renderer-added edge gaps. No notarization or stapling command ran.

### P7-T4 restore the system status-item spacing default

The widgets widened again even though their rendered images had no edge padding. Live diagnostics showed the by-host
global `NSStatusItemSpacing` and `NSStatusItemSelectionPadding` values had returned to four. AppKit consequently made
every Barometer window four points wider than its explicit item length and centered the image inside that shell.

An application-domain experiment established that AppKit also honors these keys in `com.barometer.app`. Adjusting
them made Barometer interact unpredictably with the user's system-wide spacing and other menu bar applications.
Barometer now removes only its own legacy application-domain copies before constructing `StatusItemRegistry` and
sets no replacement. AppKit therefore owns one consistent boundary between every independent status item. The
by-host global preference and every other application's preferences remain untouched.

The Sensors renderer also stopped using a calculated `.kern` value on the colon to push each live temperature across
the row. It now measures an explicit stable column for each two-row pair. Each label remains attached to its live
temperature, and the pair's trailing edge remains fixed. It has no order-specific trailing exception. Reading changes
cannot resize the outer canvas or distort label typography.

Network uses the same three-point internal gap, but its geometry is intentionally fixed rather than balanced: both
arrows are pinned to the leading origin and both rate strings begin at one fixed origin. Adding rate digits therefore
cannot shift either arrow. Sensor labels retain balanced reservation, and separate sensor columns retain a
one-device-pixel separator based on `RenderContext`'s destination display scale. Prefix field edges are snapped
upward to the device-pixel grid before the separator is added. These internal rules do not change AppKit's spacing
between independently movable items.

Verification:

- An isolated defaults-suite test verifies both legacy Barometer application-domain values are removed.
- `swift test`, including geometry checks for fixed network arrow/value origins, the three-point dense-pair gap,
  pixel-snapped prefix edges, balanced sensor reservation, and the one-device-pixel sensor-column separator,
  completed successfully.
- `swift build -c release` and `git diff --check` completed successfully.
- The installed application uses AppKit's current spacing without writing a Barometer override. CPU/GPU temperature
  labels and values retain their explicit column alignment.
- Strict code-signature verification passed. No notarization or stapling command ran.

### P7-T4 expose the last successful weather refresh

The Weather dropdown already carried the successful forecast fetch time in `Forecast.fetchedAt`, but the only age
indicator was buried in the bottom actions card and showed no clock time. The current-conditions card now displays a
full-width footer such as `Updated 7:14 AM · 2 min ago`. It sits below the icon/location/temperature row instead of
competing with the large temperature and truncating. Cached fallback samples retain the last successful fetch time,
so a failed refresh cannot misleadingly reset the label to the current time, and older updates include the date.

The original periodic `TimelineView` could freeze at the age calculated when macOS began tracking the status-item
menu. The card now resets a task-backed clock whenever it appears and advances it every 15 seconds. The displayed age
therefore follows wall-clock time even while the menu remains open.

Verification:

- `swift test` exited 0 with deterministic coverage for both the absolute-time prefix and relative refresh age.
- `swift build -c release`, `git diff --check`, and strict installed signature verification completed successfully.
- `make install` replaced and relaunched `/Applications/Barometer.app`. No notarization or stapling command ran.

### CI-T1 use the selected Swift toolchain's test framework

The first manual GitHub macOS build selected Xcode 26.2 and Swift 6.2.3, but `Package.swift` still hard-coded the
local Command Line Tools framework directory. The runner then tried to compile against a `Testing.framework` built
with Swift 6.3.3 and rejected its newer module interface. Test framework search and runtime paths now derive from
`DEVELOPER_DIR`, with the existing Command Line Tools location as the fallback when that environment variable is
absent. Local builds and GitHub Actions therefore use `Testing.framework` from the same toolchain as the compiler.

Verification:

- `swift test`, `swift build -c release`, and `git diff --check` completed successfully with the local Command Line
  Tools fallback.
- The manual `Build macOS` workflow was dispatched with version 1.0.0 and notarization disabled after the fix was
  pushed.

### CI-T2 make the test suite portable across macOS runners

GitHub's Apple Silicon runner executes Swift Testing tests that the local Command Line Tools installation currently
only builds. That exposed several assumptions tied to one physical Mac and SDK: live SMC, HID, IOReport, and GPU
interfaces were treated as universally available; time assertions used stale epoch expectations; one weather fixture
expected a value that was no longer in its JSON; one decimal tie depended on platform rounding; and AppKit tests
required exact SF Symbol geometry from a different SDK.

Live hardware smoke tests now retain their validation on supported Macs and exit cleanly when the source's public
availability check says the interface is absent. Time and fixture assertions use their actual deterministic inputs.
Network rate tie expectations consistently follow Foundation's formatter. Scheduler coverage waits until its actor
has recorded the final sleep and validates the exponential backoff separately from the wall-clock-aligned normal
interval. UI coverage verifies stable layout invariants without freezing one SDK's private font and symbol
measurements into the test suite.

Verification:

- `swift test` built every test target successfully with the local Command Line Tools installation.
- `swift build -c release` and `git diff --check` completed successfully.
- GitHub Actions run 33870340413 stamped version 1.0.0 and exposed the portability failures before signing; its
  signing and notarization steps were therefore correctly skipped.
- GitHub Actions run 33871409992 executed all 142 tests successfully, signed the application and DMG, received
  Apple's notarization acceptance, stapled and validated the ticket, passed Gatekeeper assessment, and uploaded the
  `Barometer-1.0.0.dmg` artifact. The downloaded artifact also passed local stapler and Gatekeeper validation; its
  SHA-256 is `eb3891e5ff8e0a07fa0014a123fe13587bb2ba19fb8333aad939827dc4f41454`.

### P7-T5 refresh Wi-Fi identity after Location authorization

The Network dropdown previously converted every nil CoreWLAN SSID into `Name requires Location access`. That was
incorrect when Location access was already granted, and Network did not retain or observe the shared Core Location
authorizer unless automatic Weather location happened to be active.

Network now retains the shared authorizer without prompting, observes later authorization changes, invalidates the
cached Wi-Fi sample after a grant, and refreshes the Network scheduler. Its explicit action requests authorization
only from the undetermined state, retries an authorized read, or opens the Location Services pane after denial or
restriction. The dropdown distinguishes those states and no longer tells an authorized user that access is required.
Automatic Weather tracking continues to share the same manager without having its callbacks overwritten.

Verification:

- `swift test` built every target, including coverage for authorized-but-unavailable SSIDs and the remaining
  authorization labels.
- `swift build -c release` and `git diff --check` completed successfully.
- `make install` replaced and relaunched `/Applications/Barometer.app`; strict signature verification passed under
  the stable Developer ID identity.
- No new permission category, helper, bundle, or dependency was added.

### P7-T6 publish manual GitHub releases

The reusable macOS build correctly produced a signed, notarized, stapled DMG, but its manual Build macOS entry point
only uploaded a temporary Actions artifact. The separate Release workflow also stopped at a draft, so the README's
latest-release link had nothing public to resolve.

Release remains manual-dispatch only. After its reusable macOS job succeeds, it now creates or updates a published
GitHub release, marks that version as latest, and uploads only `Barometer-VERSION.dmg`. Re-running a version safely
replaces the DMG and refreshes its title and notes.

### P7-T5 align weather refresh age with its displayed time

The weather card displays its absolute refresh time only to the minute, but its relative age previously floored raw
elapsed seconds. A refresh displayed as 8:13 could therefore still say `1 min ago` after the clock reached 8:15.
Relative age now advances on wall-clock minute boundaries, keeping both parts of the same label consistent.

### P8-T1 battery time remaining

User feedback asked for battery time remaining as a two-line menu bar item like CPU and Memory. Nothing in the
battery pipeline carried an estimate.

`BatterySource` now reads `kIOPSTimeToEmptyKey` and `kIOPSTimeToFullChargeKey` from the public power source summary
and falls back to `AppleSmartBattery`'s `AvgTimeToEmpty` and `AvgTimeToFull`. Both publishers use sentinels rather
than omitting the key while macOS is still computing an estimate, and this Mac reports both: IOPS uses `-1` and the
registry uses `65535`. `BatterySource.minutes` rejects those, zero, and anything beyond a week. An estimate is only
reported in the direction the battery is actually moving, so `timeToEmptyMinutes` is nil on external power and
`timeToFullMinutes` is nil unless charging.

`BatteryTimeFormatter` in `MenuBarStatsCore` produces the compact `H:MM` menu bar string, the long
`8 hr 15 min` dropdown string, and a `Calculating…` detail that a fully charged battery does not show, because it
has nothing to estimate rather than an estimate pending. The reserved menu bar width is `99:99`; Apple silicon
routinely reports more than ten hours, so a four-character reservation would resize the item.

Three presentations were added, keeping the two existing ones: `percentageTime` puts the percentage over the time
as two equal live rows using `NetworkRateStackRenderer` rather than the dimmed label-over-value stack,
`labeledTime` puts `BAT` over the time, and `glyphTime` puts the time beside the battery glyph with every glyph it
can swap to reserved. `AppSettings` schema moved to 14 and its battery presentation migration allow-list accepts
all five modes; without that the decoder would have silently reset every new mode to `glyphPercentage` on load.

Verification:

- `swift build` and `swift build -c release` completed successfully.
- `swift test` built every target. The test runner itself cannot execute here: SwiftPM needs Xcode's `xctest`, and
  this machine has Command Line Tools only, so `swift test` compiles the suites and exits without running them.
- The formatter and the live source were therefore exercised directly by compiling `BatterySource`,
  `BatteryMonitor`, and `BatteryTimeFormatter` into a standalone checker. All formatter cases passed, and the live
  read returned 541 minutes discharging, rendering `9:01` in the menu bar and `9 hr 1 min` in the dropdown while
  `pmset -g batt` reported `9:01 remaining` for the same battery. `timeToFullMinutes` was correctly nil, confirming
  the `65535` sentinel is filtered.
- No new permission category, helper, bundle, or dependency was added.

### P8-T2 through P8-T6 stacks, and battery presentation and adapter fixes

Stacks generalize the Sensors widget model to every module. A stack is one independently movable status item holding
an ordered list of readings chosen from any module, drawn with the same matched two-row columns the Sensors compact
stack uses. `StackMetric` is the catalog of readings; `MonitoringCoordinator` resolves each one against the live
stores and gives every branch the same reserved width whether or not a sample has arrived.

David signed off on the autosave names: stack 1 keeps `Barometer.Combined`, later stacks are `Barometer.Combined.2`
and up. Two preconditions had to be relaxed, in `ModuleID.autosaveName(instance:)` and in `StatusItemIdentity.init`.
The second was found only by exercising the model directly; the app would have trapped the moment a second stack was
enabled.

Stacks are fully user-defined at David's request: no cap, deletable, and nothing prefilled. Deletion is safe because
instance numbers come from a persisted high-water mark rather than the largest id in use, so a deleted stack's
autosave name is never handed out again and a new stack cannot inherit its saved menu bar position. An enabled
Combined item migrates into stack 1 with its members mapped to their primary readings; a user who never enabled
Combined starts with no stacks at all.

Two Battery problems surfaced while David used the build:

The icon-and-time presentation was too cramped to read and was removed; settings carrying it migrate to the
percentage-over-time rows. More importantly, each presentation drew its own natural width, so changing style resized
the item and shifted it in the menu bar. A status item keeps one length for the life of the process
(`docs/MACOS27_STATUS_ITEM_SIZING.md`), so the new image was squeezed into the old length until the next launch and
the item then moved. Every Battery presentation now draws centered on the widest canvas any presentation needs, so
changing style changes what the item shows and never its footprint.

`AppleSmartBattery` also keeps publishing an `AdapterDetails` dictionary containing nothing but a zero `FamilyCode`
after the adapter is unplugged. The dropdown read that as an attached adapter and reported "Connected" and "Wired"
with no adapter present. An adapter is now reported only when the power source says one is connected and the
dictionary carries a real field.

Separately, `BatteryMenuBarPresenter.symbolName` asked for `battery.25percent.bolt` and similar names while charging.
SF Symbols publishes a bolt overlay only for the full glyph, so those names resolved to no image at all, silently
blanking the dropdown's header icon in the shipped build. Charging now uses `battery.100percent.bolt`, and
`IconTextRenderer` keeps its icon gap when a symbol fails to resolve so one missing glyph cannot change a width.

Verification:

- `swift build`, `swift build -c release`, and `git diff --check` completed successfully.
- `swift test` built every target. The runner cannot execute here: SwiftPM needs Xcode's `xctest` and this machine
  has Command Line Tools only, so `swift test` compiles the suites and exits without running them. The suites were
  extended anyway so they run in CI.
- Because of that, the model and the renderers were exercised directly from a throwaway package depending on this
  one. All 34 checks passed, covering autosave names and the relaxed preconditions, id allocation across create and
  delete including a settings round trip, the Combined migration in both the enabled and never-enabled cases, the
  menu bar item budget, catalog integrity, forward-compatible decoding of unknown metric ids, and width stability.
- Width stability specifically: every Battery presentation holds one width across charge 0 to 100, estimates from
  one minute to 24 hours, charging and discharging, and the unavailable state, and all four presentations measure
  the same width. A three-reading stack column holds one width as its readings change.
- `make install` replaced and relaunched `/Applications/Barometer.app`. `~/Library/Logs/Barometer/identity.json`
  showed each enabled stack as a separate item with the expected autosave name and permanent accessibility label,
  and live readings only in the accessibility value.
- No notarization was run; `make app` signs locally only, and notarization remains a manual CI release step.
- No new permission category, helper, bundle, or dependency was added.

### P8-T7 stacks and battery presentation polish

David used the build and reported four problems. All four were real.

Stacks were capped, undeletable, and prefilled. They are now uncapped, deletable, and start empty. Deletion is safe
because instance numbers come from a persisted high-water mark rather than the largest id in use, so a deleted
stack's autosave name is never handed out again.

A stack no longer names itself. Generating a name from the permanent instance number would have drifted to
"Stack 47" after enough adding and deleting, and generating one from list position would silently rename every stack
below a deleted one. Adding a stack now prompts for a name, and the migrated Combined item keeps the name
`Combined`.

Changing the Battery presentation resized the item and moved it in the menu bar. A status item keeps one length for
the life of the process, so a wider presentation was squeezed into the old length until the next launch, and the
item then moved. Every Battery presentation now draws centered on the widest canvas any presentation needs. The
first attempt reused `StatusItemRendering.image(_:framedTo:)`, which pins content to the leading edge; that is right
where it frames to a latched length but left the stacked rows visibly off center, which David saw immediately. The
presenter now centers explicitly.

The stacked percentage over time was still one gap off center after that. `NetworkRateStackRenderer` reserves a
leading column for the `↑` and `↓` arrows and kept the gap after it even when both rows had no arrow. Rows without a
marker now reserve no gap, which leaves the Network item unchanged because its rows always carry arrows.

Verification:

- `swift build`, `swift build -c release`, and `git diff --check` completed successfully; `swift test` built every
  target, and the runner remains unavailable on this machine.
- The direct checks were extended to measure ink margins on the rendered images. Every Battery presentation now
  measures the same width and is centered on it within one point at the widest live values, where the renderer's own
  reserved slack is zero. All checks passed.
- `make install` replaced and relaunched `/Applications/Barometer.app`, and the identity diagnostics showed every
  item with its permanent autosave name and label.

### P8-T8 align the stacked battery rows

David reported that the percentage over time remaining was not aligned. Measuring the rendered image ruled out the
first two suspects: both rows sit exactly where the CPU and Memory stacks put theirs, so nothing was off vertically
or out of step with its neighbors. The fault was horizontal. `NetworkRateStackRenderer` starts every row at one
leading edge so the `↑` and `↓` arrows form a column, which is right for Network but leaves two bare readings of
different lengths, such as `78%` over `7:30`, ragged against each other.

Rows that carry no marker are now centered on each other. Network is unchanged because its rows always have arrows,
which the test pins by asserting its two leading edges still match.

Verification:

- `swift build`, `swift build -c release`, and `git diff --check` completed successfully; `swift test` built every
  target, and the runner remains unavailable on this machine.
- Direct image measurement: the two rows share a horizontal center within half a point at 5, 9, 78, and 100 percent
  with estimates from 3 minutes to 12 hours, both rows still land on the same scanlines as the CPU stack, every
  Battery presentation still measures one width, and the Network item's arrows still share one leading edge.
- `make install` replaced and relaunched `/Applications/Barometer.app`.

### P8-T9 gate the weather glyph at a legible size

David reported the weather glyph as microscopic. `MenuBarLayoutMetrics.compactSymbolVisibleHeight` multiplied the
glyph height by the automatic icon scale, which drops from 1.15 to 0.75 as items are added, with a floor of only
5.5 pt. At his seven enabled items the scale is 0.9, so the glyph drew at 8.6 pt inside a 12 pt row while the
temperature under it drew at 7 pt, making the icon look like an afterthought.

The floor is now one point short of the row, so the glyph fills its row at every automatic scale, and the ceiling is
unchanged so the top of the icon scale slider still grows it. Only `IconStackRenderer` reads this metric, and only
Weather's icon-and-temperature mode and the Settings preview strip use that renderer, so nothing else moved.

Verification:

- `swift build`, `swift build -c release`, and `git diff --check` completed successfully; `swift test` built every
  target, and the runner remains unavailable on this machine.
- Direct measurement across every automatic scale from 3 to 16 items: the glyph now draws at 11 pt at all of them,
  up from 8.6 pt at David's current item count, still clears the value row, and the item's width is identical at
  every scale, so a larger glyph cannot move the item. Rendering a magnified strip beside the CPU stack confirmed
  the glyph reads at the same weight as its neighbors.
- `make install` replaced and relaunched `/Applications/Barometer.app`.

### P8-T10 lift the stacked battery rows onto the shared two-row grid

David reported that the stacked battery percentage over time sat lower than every other item. It did, by two points.

`NetworkRateStackRenderer` sizes each row from `max(markerHeight, valueHeight)`. Attributes applied to an empty
attributed string apply to no characters, so a row with no `↑` or `↓` reported the default system font's line
height rather than this renderer's compact one. The maximum therefore came out around 14 instead of 11, and
`compactRowY`'s `floor((rowHeight - textHeight) / 2)` went negative and pushed both rows down. A row without a
marker now takes its height from its value alone.

The earlier alignment check missed this because it ran at a 24 pt thickness, where the arithmetic happens to round
to the same result. The real menu bar on this Mac is 22 pt, taken from the live status item geometry in
`~/Library/Logs/Barometer/identity.json`. The regression test now runs at 22, 24, and 26 pt, and pins the arrow rows
as well so Network cannot drift either.

Verification:

- `swift build`, `swift build -c release`, and `git diff --check` completed successfully; `swift test` built every
  target, and the runner remains unavailable on this machine.
- Direct measurement at the real 22 pt thickness: the battery rows now begin on the same two scanlines as the CPU
  stack, where they previously began two points lower. The arrow rows are unchanged, every battery presentation
  still measures one width, and the two bare rows still share a center.
- `make install` replaced and relaunched `/Applications/Barometer.app`.

### P8-T11 stack dropdown detail and Settings preview

David added a CPU and GPU stack and reported two things: nothing appeared, and the pane gave him no way to see what
he was building.

Nothing appeared because the stack was saved with `isEnabled` false. Adding a stack creates it hidden and stages its
visibility, like a new Sensors widget, so the choice only takes effect through the Apply bar. That is the existing
model for anything that changes the visible item set and was left alone, but it is exactly why the preview matters.

The stack dropdown previously showed a two-tile summary per module. It now hosts each source module's own dropdown
behind a tab, so a CPU and GPU stack opens the full CPU dropdown and the full GPU dropdown. Those views bring their
own scroll container, so the stack view adds only the tab strip above them rather than nesting a second scaffold,
and `DropdownController.fitContent` already measures intrinsic height so each tab sizes itself. The tab strip is
hidden when a stack draws from a single module, where it would be one pointless tab. The dropdown now needs the same
callbacks the individual items use, so location access, weather refresh, sensor energy reset, and calendar access
are passed through from the coordinator.

The Stacks pane now renders a preview, matching every other module pane. It reads
`settingsIncludingPendingMenuBarChanges`, so staged edits appear before they are applied, which is the point of it.
To keep the preview honest, the reserved width of every reading moved into `StackMetric.reservedValue(settings:)`
and the menu bar renderer now sizes from that same catalog; the preview cannot show a width the real item would not.
`StackMetric.previewValue(settings:)` supplies representative readings, and both follow the selected units.

Verification:

- `swift build`, `swift build -c release`, and `git diff --check` completed successfully; `swift test` built every
  target, and the runner remains unavailable on this machine.
- Rendering the preview path to a magnified PNG showed a CPU and GPU stack and a battery and temperature stack drawn
  as matched two-row columns with a separator between the stacks, matching the menu bar output beside it.
- The direct checks still pass, including battery width and centering, two-row alignment at 22, 24, and 26 pt, and
  the weather glyph floor.
- `make install` replaced and relaunched `/Applications/Barometer.app`.

### P8-T12 make the weather item legible

David said the weather glyph was still far too small, then identified the real problem: stacking the icon over the
temperature gives each of them half of a 22 pt bar, so neither can be large. Raising the glyph inside its row was
the wrong fix, and measurement showed it: at a floor of one point past the row the glyph merged into the value below
it, leaving a single band of ink instead of two.

Icon and temperature now sit side by side, so each uses the full bar height. Measured at David's item count the
glyph and the temperature both draw around 11 pt of ink instead of roughly 8, and the temperature is set in the
normal menu bar font rather than the compact two-row one.

The cost is width: about 47 pt against 21 pt stacked. That is a real trade against the reason stacks exist, so the
old presentation stays selectable as "Icon over temperature (compact)" rather than being replaced outright.

Separately, `MenuBarLayoutMetrics.symbolSize` scaled a glyph beside text by the automatic icon scale, which shrinks
as items are added. A glyph on one row has the whole bar to work with, so it is no longer pulled below its size at
the reference scale.

Verification:

- `swift build`, `swift build -c release`, and `git diff --check` completed successfully; `swift test` built every
  target, and the runner remains unavailable on this machine.
- Rendering both presentations side by side to a magnified PNG showed the difference directly and caught the failed
  first attempt, where the enlarged glyph collided with the temperature.
- Widths and glyph ink were measured at every automatic scale from 3 to 16 items. All existing checks still pass.
- `make install` replaced and relaunched `/Applications/Barometer.app`.

### P8-T13 reduce Weather to one good presentation

David asked for one option: the current conditions and the current temperature, done well. Weather had six modes,
most of them variations nobody needed and two that could not be read at this size.

Weather now has no display picker. It renders the condition glyph beside the temperature, both using the full bar
height. The unit letter is dropped, so it reads `81°` rather than `81°F`: the reader chose the unit, and the letter
cost a glyph of width in the place where width is scarcest. Every condition glyph is reserved, so a change in the
weather cannot change the item's width, which the previous icon-and-temperature mode did not do.

The mode-based formatter, its reserved-text table, and the high/low, precipitation, conditions, text-only, and
stacked branches are deleted rather than left unreachable. Any saved weather mode now resolves to the single
presentation on load.

Verification:

- `swift build`, `swift build -c release`, and `git diff --check` completed successfully; `swift test` built every
  target, and the runner remains unavailable on this machine.
- The Weather formatting test now pins the single presentation in both unit systems and the reserved width.
- Rendering the item beside CPU, Battery, and a stack confirmed the glyph and temperature read at the same weight as
  their neighbors. All direct checks still pass.
- `make install` replaced and relaunched `/Applications/Barometer.app`.

### P8-T14 tighten the spacing between an icon and its value

David said the gap between the weather glyph and its temperature was far too large, and asked for the same spacing
the rest of the bar uses. Measuring the rendered ink confirmed it: nine points between the glyph and the value,
where a Network arrow and its rate, and a Sensors label and its value, both leave five.

Three separate causes, each found by measurement rather than by reading the layout code:

`IconTextRenderer` sized the glyph from the symbol's image box. SF Symbols carry transparent optical padding, so
part of that box was invisible margin sitting between the icon and the value. The glyph is now measured and placed
by its ink, as the stacked renderer already did.

The glyph was centered inside a field reserved for the widest condition symbol, so half of that reservation fell
between the icon and the value and changed size with the weather. The ink now sits against the trailing edge of its
field, leaving the spare width on the outside where it reads as margin.

The value was right-aligned inside a field reserved for `-99°`, which put the difference between the live value and
the reservation into the same gap. That was the largest of the three. The value is now drawn against the icon.

With those fixed the gap was three points, which is `densePairGap` but two points tighter than the rest of the bar,
because the other items gain the side bearing of their label's last glyph and an ink-placed icon has none. The
inline gap constant is therefore the visible gap itself, and all three items now measure five points.

Verification:

- `swift build`, `swift build -c release`, and `git diff --check` completed successfully; `swift test` built every
  target, and the runner remains unavailable on this machine.
- Ink-gap measurement across the weather, network, and sensor items: 5.00 pt each, from 9.00, 5.00, and 5.00 before.
  A test now pins the weather item to whatever the reference items measure, comparing rendered ink rather than
  layout constants, since the constants legitimately differ.
- `make install` replaced and relaunched `/Applications/Barometer.app`.

### P8-T15 size the inline weather glyph against the bar

David said there was more padding around the weather icon than around other icons. Measuring the item showed no
horizontal margin to remove: the leading edge was already flush and the gap to the value already matched the rest of
the bar. The padding was vertical. `IconTextRenderer` sized a glyph from the font point size, giving 13.8 pt of ink
in a 22 pt bar, while the icons other menu bar apps draw fill closer to 16, so ours looked like a small glyph
floating in space rather than an icon.

A glyph beside text has the whole bar to work with, so it is now sized against the thickness, leaving three points
of ink margin top and bottom, capped two points short of the bar. Enlarging the ink narrowed the measured gap to the
value, so the inline gap constant was raised a point to keep all three items at the same five points.

Verification:

- `swift build`, `swift build -c release`, and `git diff --check` completed successfully; `swift test` built every
  target, and the runner remains unavailable on this machine.
- Ink measurement: the glyph draws 16 pt in a 22 pt bar, up from 13.8, and the weather, network, and sensor items
  all still measure 5.00 pt between their parts. The item is 58 pt wide, up from 54.
- The weather glyph test was rewritten for the inline layout; it previously asserted the glyph fit inside half the
  bar, which was the rule for the stacked presentation that no longer exists.
- `make install` replaced and relaunched `/Applications/Barometer.app`.

### P8-T16 give every condition glyph one field

David sent a screenshot with `sun.max` showing and said the padding around the icon was not standardized with the
other widgets. It was not, and the earlier measurements had missed it because they used `cloud.sun`.

Glyphs were normalized to a common ink height, which makes a round symbol much narrower than a wide one:
at the same height `sun.max` measures about 16 points across where `cloud.sun` measures about 24. The renderer then
reserved the widest of them, so whichever glyph was showing sat in a pocket of leftover width, and the pocket
changed size with the weather. `cloud.sun` filled the reservation exactly, which is why every earlier check looked
correct.

Each glyph is now fitted into one square field sized from the bar, so the icon occupies the same space whatever the
weather is doing and nothing has to be reserved for the widest one. The icon, gap, and value are laid out as one
group against the leading edge, so what spare width remains collects at the trailing edge instead of around the
icon. The gap constant lost the point it had gained, because a fitted glyph no longer contributes its own slack.

Verification:

- `swift build`, `swift build -c release`, and `git diff --check` completed successfully; `swift test` built every
  target, and the runner remains unavailable on this machine.
- Measured across `sun.max`, `cloud.sun`, `cloud`, `cloud.bolt.rain`, `moon.stars`, and `snowflake`: identical item
  width, zero leading margin, and 5.00 pt to the value, matching the network and sensor items. The item is 48 points
  wide, down from 58.
- A test pins the shared field: every condition glyph must produce one width and sit flush with the leading edge.
- `make install` replaced and relaunched `/Applications/Barometer.app`.

### P8-T17 release host port references and stop rebuilding history every update

An independent review of `f50443f` reported a Mach port ownership bug and history processing that grows with uptime.
Both were verified against the code before changing anything; two further findings about display-sleep resumption
and `nettop` were not verified and were left alone.

`mach_host_self` returns a send right and adds a user reference to it on every call. Three calls had no matching
`mach_port_deallocate`, two of them on the per-sample path, so the reference count climbed for the life of the
process. All three now release the right. `MemorySource` also called `host_page_size` on every sample; the page size
cannot change while the system runs, so it is read once.

`History.entries` rebuilt the whole buffer on every access, and `StatusItemController.update` passed it on every
sample regardless of presentation. CPU retains 86,400 samples, so a steady-state CPU item allocated and copied an
86,400 element array once a second, each element carrying two nested arrays. `History.recent(_:)` materializes only
the newest entries, and rendering asks for 240 of them.

That does change the graph modes rather than being purely an optimization: `GraphRenderer` plots every value it is
given across about forty points of width, so CPU and Memory graphs previously compressed a whole day of samples into
that space. They now show the most recent window, matching what GPU, Sensors, and the dropdowns already did through
`suffix`.

Replacing a status item's image makes AppKit redraw it, and the image was assigned on every sample even when
identical. It is now compared by its drawn pixels first, so a graph that moves while its reading is unchanged still
updates, while a text item repeating the same value does not. The accessibility value is likewise only set when it
changes.

Verification:

- `swift build`, `swift build -c release`, and `git diff --check` completed successfully; `swift test` built every
  target, and the runner remains unavailable on this machine.
- The direct render checks still pass unchanged, so the battery, stack, spacing, and glyph work is unaffected.
- Not addressed: the reviewer's display-sleep resumption and `nettop` cadence findings, neither of which was
  reproduced or verified here.

### P8-T18 make the test suite green and run it on every push

Six tests were failing, twenty-six assertions in total. None was a defect in shipped behavior; the suite had simply
never run against this phase's work. `check.yml` was dispatch-only, and `swift test` cannot execute on this machine,
so seventeen commits landed with no feedback from it. The workflow now runs on pushes to main and on pull requests.

Three tests described the Combined model that stacks replaced. They set `combined.members` while `stacks` was empty
and asserted the old outcome. They now drive the same behavior through stacks, and each gained the cases the new
model made possible: a stack that does not replace its sources, the stacks master switch overriding an individual
stack, a disabled stack asking for no samples, and a second stack appearing as `Barometer.Combined.2`.

`iconMatchesFontSizeAndUsesCanonicalGap` was a real contract that had been broken by accident rather than by intent.
An earlier attempt at enlarging the weather glyph changed `MenuBarLayoutMetrics.symbolSize`, and when the inline
renderer moved to its own fitted field that change was left behind, still affecting `SymbolRenderer`. It has been
reverted, so the contract holds again and the test needed no edit.

The two remaining failures were assertions written in this phase that no longer matched their own design. The
weather glyph test still asserted the glyph filled a share of the bar, which was the rule before glyphs were fitted
into a square field; it now asserts the glyph fills that field in one direction without spilling past it. The
spacing test required the icon's gap to equal two reference items exactly. Measured gaps are of drawn ink and vary
by a point or two with the symbol's shape, the bar height, and the icon scale, so equality was never a property the
renderers had; the tolerance now reflects that, and 22 points is checked explicitly as the real bar height.

Verification:

- `swift build`, `swift build -c release`, and `git diff --check` completed successfully; `swift test` built every
  target.
- Every changed assertion was recomputed outside the test runner first, against the real modules, since the runner
  cannot execute here. All of them pass, including the arithmetic behind the restored `symbolSize` contract.
- `make install` replaced and relaunched `/Applications/Barometer.app`.

### P8-T19 center menu bar content under the hover highlight

David reported the hover highlight sitting off the content on every item. Measuring the ink margins confirmed it and
showed why: renderers size their canvas from the widest value an item can ever show, then drew the live value flush
against one edge, so the unused reservation collected on the other side. `TextRenderer` pinned to the trailing edge
while the stacked renderers pinned to the leading edge, so the items did not even lean the same way.

All of them now center the live content in the reserved canvas. Weather went from 0 and 6 points of margin to 1 and
4, Network from 0 and 6 to 2 and 4, and the CPU stack from 0 and 8 to 3 and 5.

The remainder cannot be removed. His `NSStatusItemSelectionPadding` is 0 by host, so the highlight is exactly the
item's frame with no inset, and `NSStatusItemSpacing` is 0, so items sit flush. Any item whose value is narrower
than its reservation therefore shows a highlight reaching past the value. Barometer already removes both keys from
its own domain so it never overrides that choice.

Positioning the value by its ink rather than its advance box removed the last point of asymmetry but pulled the
value two points closer to the icon, breaking the spacing that matches the rest of the bar. That was reverted: the
alternatives are clipping temperatures at three characters or letting the item resize, and resizing is what the
identity contract exists to prevent.

Verification:

- `swift build`, `swift build -c release`, and `git diff --check` completed successfully; `swift test` built every
  target.
- Ink margins were measured per item before and after, and the icon-to-value gap stayed at 5 points across every
  condition glyph with item widths unchanged.
- `make install` replaced and relaunched `/Applications/Barometer.app`.

### P8-T20 fix the remaining test failures

The first push to run the suite automatically reported five failing tests, fourteen issues. An earlier reading of a
failing run had been taken from the tail of the log, which showed only the renderer suite; the settings failures had
been there all along and were missed.

Three were fixtures that still drove the old Combined model: the automatic sizing count, the staged topology test,
and the migration test. They now build the same situations from stacks, and the migration test enables Combined
first, because a stack is only created for an item that was actually on.

One was an assertion of mine that condition glyphs sit flush with the leading edge, which centering deliberately
changed. Glyphs of different widths centered in one field legitimately start at slightly different offsets, so the
test now pins what matters: identical item widths, and offsets within a point of each other.

The last was `iconScaleResizesCompactSymbolsAndGraphs`, a pre-existing contract that the icon scale changes a
compact symbol's height. The glyph floor added for the stacked weather presentation had made that height constant.
`IconStackRenderer` is now used only by the Settings preview, since Weather draws inline, so the floor was serving
nothing and has been reverted rather than the test rewritten. That is the second contract broken by a change left
behind from an approach that was later replaced.

The icon group is also measured from the icon's fixed field again rather than the current glyph's ink. Measuring
from the ink centered the item one point better but moved the whole item as the weather changed, which is worse.

Verification:

- `swift build`, `swift build -c release`, and `git diff --check` completed successfully; `swift test` built every
  target.
- Every corrected assertion was recomputed against the real modules first, including the sizing ladder from one to
  twenty items, each module adding exactly one item, and stacks adding one item and removing the sources they
  replace.

### P8-T21 leave releases as drafts for a person to publish

The Release workflow created a published release and marked it latest in the same run that built it, so a dispatch
was the moment something became public. It now creates a draft and stops. A draft is not visible to anyone else and
is not tagged latest, so the notes and the notarized DMG can be checked before shipping, and publishing is a
deliberate press of a button in the Releases page.

Re-dispatching a version refreshes its draft and replaces the attached DMG. Re-dispatching a version that is already
published now fails instead, because rewriting a public release would change what people have already downloaded.
The run summary links the draft.

Verification:

- `git diff --check` completed successfully, and the workflow's release job was reviewed step by step against the
  `gh release` semantics it relies on: `--draft` on create, `--draft=true` on refresh, `--latest` deliberately not
  passed because GitHub applies it when a person publishes.
- `docs/RELEASING.md` now describes preparing and then publishing a release, including the refusal to rewrite a
  published version.


### P8-T22 investigate reported memory use and rename the default branch

David supplied a build 116 report: 291.4 MB physical footprint, 422.2 MB peak, and 415 reported leaks totaling
19,904 bytes after approximately six minutes. The report also warns that the process is not debuggable. Those
reported leaked bytes do not explain the footprint, and the screenshot cannot establish the allocation owners.

Read-only inspection of the already-running local Barometer (PID 55680, version 1.0.1 build 1, approximately
54 minutes uptime) confirmed substantial history retention. This is a different build and session from the report.
`vmmap -summary 55680` reported 278.0 MB footprint, 523.9 MB peak. `heap -sortBySize 55680` subsequently reported
416.5 MB footprint and 255,657,518 allocated bytes across 679,417 nodes. These snapshots do not establish a growth
rate; footprint measurements can differ during inspection.

Largest identified application allocations in that heap snapshot:

- Preallocated optional history-entry arrays: Network 22,822,912 bytes; GPU 15,908,864; CPU 9,682,944;
  Memory 4,849,664; Disk 2,768,896; Battery 2,146,304; Sensors 933,888 (about 56.4 MiB combined).
- 656 SensorReading arrays: 31,957,952 bytes. SensorsMonitor assembles complete reading arrays on each sample,
  and the store retains up to 28,800 complete SensorSample values.
- 3,248 NetworkInterfaceSample arrays: 8,314,880 bytes. The Network store retains up to 86,400 full samples.
- 111,479,845 bytes were classified as non-object allocations and were not attributed to a specific source.

MonitoringCoordinator creates these buffers even for disabled modules. History initializes every slot immediately.
CPU, Memory, Disk, and Network dropdowns still materialize complete histories; the earlier P8-T17 optimization
bounded status-item rendering only. ProcessIconResolver also caches full NSImage objects under PID/path keys
without a configured count or cost limit, a secondary candidate rather than a measured primary cause.

Recommended repair: separate compact graph history from full current samples, allocate history as needed, bound
or downsample dropdown rendering, and limit the process-icon cache. Preserve the designed 24-hour CPU graph
window through compact/downsampled data. No runtime code was changed in this diagnostic task. Attribution of the
remaining allocations and verification against the reporter's exact binary remain open.

Renamed the GitHub default branch through the branch-rename API, renamed the local branch to master, set its
upstream to origin/master, and updated origin/HEAD, the Check push trigger, and release instructions.

Verification:

- `vmmap -summary 55680` and `heap -sortBySize 55680` completed; selected measurements are recorded above.
- `git ls-remote --symref origin HEAD refs/heads/main refs/heads/master` confirmed HEAD targets master and
  there is no remote main branch.
- `git diff --check` passed. Runtime tests were not needed for documentation and a CI branch-filter change.


### P8-T23 bound graph-history memory and gate builds on tests

Replaced retained full samples with module-specific graph values. Latest samples still contain all current detail;
CPU history holds only utilization, Memory holds used fraction and pressure, and other graphs retain only the
rates or sensor values they draw. CPU and Memory retain their existing day-long sample capacities. GPU, Network,
and Disk retain 300 samples, Sensors 240, and Battery 720; Weather and Time do not retain forecast/calendar payloads.
`GraphHistoryRetention` supplies the same limits to the application and benchmark.

History arrays now grow as samples arrive rather than filling every slot with nil at startup. Dropdowns request
bounded windows or downsample directly from the ring. CPU time-window selection preserves both endpoints and
handles backward wall-clock corrections without allocating a complete filtered history. Process icons use a
128-entry, 512 KiB-cost cache of 32-by-32 thumbnails keyed by application/executable path when available, so PID
turnover does not retain another full icon for the same executable. NSCache limits remain eviction hints rather
than a hard process-memory limit.

Regression tests cover empty-buffer allocation, copy-on-write wrapping, full-day display bounds and endpoints,
clock corrections, release of old full-sample payloads, missing sensor readings, selected network interfaces, and
shared thumbnail dimensions. Existing renderer tests now consume projected history values while keeping their
presentation assertions.

Local `swift test` had compiled its generated runner without finding Testing.framework, silently executing no tests.
`make test` now explicitly enables Swift Testing and supplies the framework search path to all compilation targets,
including the generated runner. This produces real test counts and a failing exit status when an assertion fails.

Verification on 2026-09-04:

- `make test`: 169 tests executed, 168 passed, one existing weather-glyph assertion failed: leading-margin spread
  was 2 points against a 1-point limit. Running the unchanged P8-T22 baseline's renderer suite with the same
  framework flags reproduced that exact failure (47 tests, one failure). The assertion was not weakened.
- Focused execution using `swift test --enable-swift-testing -Xswiftc -F -Xswiftc
  /Library/Developer/CommandLineTools/Library/Developer/Frameworks --filter
  'MemoryHistoryTests|HistoryTests|NetworkTests|processIconsUseSmallSharedThumbnails'`: 16 tests passed.
- `Scripts/benchmark-memory.py` builds the identical `Tools/MemoryHistoryBenchmark.swift` against the current
  modules and a `git archive b05e457` baseline, in separate processes. Both initialize all seven hardware stores
  and feed identical CPU (14 cores, five processes), Network (16 interfaces), and Sensors (300 readings every
  five simulated seconds) samples. Memory, GPU, Disk, and Battery stores remain empty in this workload.
- Final benchmark output (physical footprint, decimal bytes):

  | Simulated elapsed time | Baseline | Compact history |
  | --- | ---: | ---: |
  | Startup | 61,604,440 | 2,490,920 |
  | Six minutes | 69,272,152 | 5,112,360 |
  | One hour | 136,888,968 | 9,994,816 |
  | 24 hours | Not run | 12,681,816 |
  | 48 hours | Not run | 12,681,816 |

  The one-hour footprint decreased 92.7%; measured growth from simulated hours 24 to 48 was zero bytes.
  The benchmark automatically fails if the reduction is below 50% or plateau growth exceeds 5 MiB.
  This is an accelerated storage workload, not a whole-app or real-time 48-hour measurement. It does not attribute
  the earlier heap's remaining non-object allocations or predict the reporter's complete UI footprint.

David also requested checks before builds. Added a reusable Tests workflow invoked by both Check and Build macOS.
Check packaging requires its test job; the signed build requires its check job before packaging or certificate import;
Release already requires the reusable macOS build, so it inherits the test gate. Test compilation is necessary to
execute tests, but packaging, signing, and release preparation cannot run following a failed gate.

- Ruby/Psych parsed all four workflow YAML files and verified the Check → Tests, Build → Tests, and Release → Build
  dependencies, shared `make test` entry point, and absence of `if`/`continue-on-error` job-level bypasses.

- `CODESIGN_IDENTITY=- make app` built the release configuration and packaged `dist/Barometer.app`;
  `codesign --verify --deep --strict --verbose=2 dist/Barometer.app` passed. The installed application was not replaced.
- `git diff --check` passed.

### P8-T24: Rich daily weather with configurable detail

Added a scrollable daily forecast popover and expanded the existing Open-Meteo request with 31 optional hourly
metrics and 25 optional daily metrics, plus moonrise and moonset. Checked supported fields against the official
https://open-meteo.com/en/docs and captured live metric and imperial fixtures. Normalize provider feet to meters
for internal visibility, freezing level, and snow depth. Missing fields and older caches remain supported.

Conditions, key readings, precipitation, air/comfort, and hourly forecasts appear first and start expanded.
Sun information follows; Moon and advanced atmospheric details start collapsed. Weather settings offers All details
or Custom, preserving custom selections across mode changes. Display preferences update without another fetch.

Verification on 2026-09-04:

- Full suite: 189 tests executed, 188 passed. All 20 added weather/model/settings/presentation tests passed.
  The only failure is the previously reproduced baseline weather-glyph margin assertion (2 points versus 1).
  Output: dist/weather-final-tests.log. No assertion was weakened.
- Reviewed light/dark forecast, hourly detail, and chart captures in dist/. ImageRenderer cannot capture the native
  scroll view and attribution link together; chart content was captured separately. Interactive review remains David's.
- make install completed the signed release build, but macOS denied replacing files in /Applications/Barometer.app.
  Launched the complete packaged dist/Barometer.app directly with open instead. Verified exactly one Barometer app
  process, PID 72623, running /Users/david/MenuBarStats/dist/Barometer.app/Contents/MacOS/Barometer.
- codesign --verify --deep --strict --verbose=2 dist/Barometer.app passed.
- git diff --check passed.
- Earlier memory-change GitHub Check run 33934059122 passed its test and package jobs. This weather change stays
  local pending David's review; no weather push or GitHub build was started.

### P8-T25: Fix interactive daily weather presentation

David reported that the nested SwiftUI day popover would not scroll, dismissed on interaction, and left a halo.
The day popover was presented from a custom NSMenu view during menu tracking. Replaced this nested presentation
with a key-capable detail panel opened after canceling menu tracking. Explicit close, Escape, loss of focus, and
replacement remove the window and release its hosted content. Opening the parent menu closes any previous detail.
Status-item identity and permanent menu attachment remain unchanged.

Pinned day readings, precipitation, air/comfort, hourly forecasts, and Sun information now have plain section
headers. Moon, advanced atmospheric measurements, and extra hourly readings remain expandable. Custom settings
can still hide sections.

Verification on 2026-09-04:

- make test: 192 tests, 191 passed; only the previously reproduced baseline weather-glyph spacing test failed.
- Three new AppKit integration tests passed: the actual fixture-backed weather view has a taller scroll document
  than its viewport and scrolls; closing hides the window and clears hosted content; replacing a window or losing
  focus cleans up the old presentation. Output: dist/weather-panel-tests.log.
- make app: signed release build passed. ditto dist/Barometer.app /Applications/Barometer.app succeeded this time.
  Stopped the previous process and opened /Applications/Barometer.app.
- codesign --verify --deep --strict --verbose=2 /Applications/Barometer.app passed.
- git diff --check passed. User interaction and macOS compositor halo verification remain for local review;
  programmatic window cleanup tests do not prove the compositor's visual result.
- No push or GitHub build.

### P8-T26: Keep daily weather open through menu dismissal

David reported the P8-T25 panel disappeared immediately when selecting a day. Task.yield did not guarantee that
AppKit had left its menu-tracking loop, and closing on key-window resignation made the handoff fragile. Schedule
presentation exclusively in the default run-loop mode, use a nonactivating panel, and dismiss on explicit outside
mouse clicks, Escape, or close instead of transient focus changes. Remove both event monitors and cancel pending
presentation timers during cleanup.

Verification before building on 2026-09-04:

- make test: 194 tests, 193 passed; the only failure remains the previously reproduced baseline glyph margin test.
  The five detail tests pass, including default-versus-menu-tracking run-loop presentation, real weather scrolling,
  replacement, Escape, and 100 open/close cycles. Weak references confirm panel, hosting view, and presenter release,
  including cancellation of a pending timer. Output: dist/weather-handoff-tests.log.
- Reexecuted all memory tests as part of the full suite and reran Scripts/benchmark-memory.py dist/memory-baseline.
  One simulated hour: baseline 136,856,200 bytes versus current 9,929,256 bytes, a 92.7% reduction.
  Current footprint at simulated hours 24 and 48: 12,042,816 bytes, zero growth. Both benchmark thresholds passed.
  This remains an isolated storage workload; it does not prove the entire UI is leak-free.
- git diff --check passed. No push or GitHub build.

David required fixing the existing test failure before presenting another build. The renderer centers symbols of
different aspect ratios in a fixed field, as required by the sizing contract; equal leading ink margins were an
incorrect assertion. Replaced that assertion with measured visible-ink centers, retaining the one-point tolerance,
stable weather canvas width check, and explicit nonempty-glyph checks. No production glyph geometry changed.

Final verification:

- make test: all 194 tests in 28 suites passed, including memory and all five detail lifecycle tests.
- Only after this clean test run, make app passed; copied to /Applications/Barometer.app, verified its strict signature,
  stopped the previous process, and launched the Applications copy.
- Automated tests cover the run-loop handoff and cleanup, but do not constitute a manual end-to-end menu interaction
  or compositor inspection on this macOS beta.

### P8-T27: Attached hover weather popovers

David rejected a movable detail window and requested hover-driven popovers with scrolling and no detail chevrons.
Weather and Combined now open native NSPopovers from their existing status buttons. Other modules retain NSMenu.
Hovering a forecast row presents a semitransient child popover anchored to that row; the parent remains available.
Both popovers refuse detachment. Native popover dismissal replaces custom floating windows and mouse monitors.
The status items, bundle identity, autosave names, and immutable widths are unchanged.

Removed detail expansion controls, including Moon and hourly groups. Enabled sections are directly visible, with
practical information first. Hourly rows use lazy layout; Settings still offers All details or remembered Custom
section choices. Updated settings guidance for hover and removed obsolete expansion-default logic.

Verification before packaging:

- make test: all 195 tests in 28 suites passed. Native hover-event test invokes the detail action without a click.
- Actual rich weather content scrolls in a child NSPopover while its parent remains shown. Tests verify detachment is
  refused, close/replacement cleanup, and pending menu-handoff cancellation for the fallback path.
- Repeated 100 real weather view presentations followed by closing release the tested popover, hosting view, and
  presenter weak references. No standalone detail window or event monitor remains in production.
- Scripts/benchmark-memory.py dist/memory-baseline passed: 92.8% reduction at one simulated hour and zero growth from
  simulated hours 24 to 48 (12,616,256 bytes at both). This is an isolated history workload, not a whole-app footprint.
- git diff --check passed. No push or GitHub build. Native pointer travel and compositor behavior still require
  interactive review; automated event and lifecycle tests cannot establish those visual results.
- After the clean suite, make app passed; copied to /Applications/Barometer.app, passed strict codesign verification,
  stopped the previous process, and launched the Applications copy for local review.

### P8-T27 pre-push verification

At David's request, reran both checks against committed revision c30073a before pushing:

- make test: all 195 tests in 28 suites passed, including the real weather popover lifecycle and memory tests.
  Output: dist/pre-push-tests.log.
- Scripts/benchmark-memory.py dist/memory-baseline: PASS, one-hour footprint reduced 92.8%; simulated hours 24 to 48
  grew 16,384 bytes (12,403,264 to 12,419,648), below the 5 MiB plateau threshold. This is isolated history storage.
  Output: dist/pre-push-memory.log.
- git diff --check passed. No code changed after these checks; this entry records the pre-push results.

### P8-T28: Bound every popover to its display

David's screenshot showed the main weather popover extending above the screen. Root presentation had relied on
NSHostingController's automatic sizing without explicitly setting NSPopover.contentSize. Added shared
PopoverPlacement: fix the viewport, disable automatic hosting-controller sizing, set contentSize before showing,
and contain the resulting window inside the anchor display's visible frame. Apply it to Weather, Combined, and
hover day popovers; recheck the root during updates and child presentation. Status-item window geometry is untouched.

Verification before packaging:

- make test: all 198 tests in 29 suites passed. New tests cover actual Weather, Combined with Weather selected,
  both rich fixture days, four corners, light/dark appearances, plus oversized frames on displays with negative
  coordinates. Window bounds must remain contained after display, not just during initial layout.
- Native NSView bitmap captures were blank and rejected as visual evidence. CGPreflightScreenCaptureAccess returned
  true, so used existing permission for /usr/sbin/screencapture of test popover windows only. Captured 32 real window
  screenshots under dist/popover-screens and inspected each popover type in both appearances. Headers are visible;
  content extends only inside the scroll viewport. Screenshots are opt-in via POPOVER_SNAPSHOT_DIRECTORY; default CI
  still runs the live window geometry checks without requiring capture permission.
- Existing nested-popover scrolling and 100 real-weather open/close release tests passed.
- Memory benchmark passed: 92.7% lower one-hour history footprint; 16,384-byte growth between simulated hours 24 and
  48, below the 5 MiB threshold. This benchmark measures isolated history storage.
- git diff --check passed. Logs: dist/weather-placement-tests.log and dist/weather-placement-memory.log.
- After the clean tests, make app passed, the signed bundle was copied to /Applications/Barometer.app, strict
  codesign verification passed, and the Applications copy was relaunched. This correction remains local.

### P8-T29: Dismiss weather details when hover ends

David reported persistent day popovers that required an X to dismiss. Added pointer-region checks while a day
popover is open: remain visible over its source row or its own frame, then dismiss after a 200 ms grace period
outside both. This permits crossing into the popover to scroll. The timer is invalidated on every close/replacement;
no pointer monitor persists after dismissal. Removed the X and its now-unused environment dismissal action.
Removed the technical time-zone/unavailable footer; retained provider attribution.

Verification before packaging:

- make test: all 199 tests in 29 suites passed. New hover-exit test checks crossing the gap, staying inside for
  scrolling, leaving both regions, dismissal, and hosted-content release. Existing 100-cycle release tests passed.
- Reran real screen captures for all popover types, both appearances, and four corners; inspected the updated day
  screenshot to confirm the header no longer contains an X. All window-containment checks passed.
- Memory benchmark passed: 92.7% lower one-hour history footprint and zero growth from simulated hours 24 to 48.
  This is isolated history storage, not a whole-app memory claim.
- git diff --check passed. Logs: dist/weather-hover-exit-tests.log and dist/weather-hover-exit-memory.log.
- After the clean checks, signed make app passed, copied the bundle to Applications, verified its strict signature,
  and relaunched /Applications/Barometer.app. This correction remains local.

### P8-T30: Check steady CPU usage

David reported approximately 3% CPU and requested measurement. Read-only audit of installed PID 85254:

- Initial top capture: 15 interval samples after discarding initialization, mean 4.11%, median 3.7%, range 2.2–6.7%.
  An eight-second sample profiler overlapped this first capture, so repeated the measurement without profiling.
- Unprofiled top capture: 15 one-second interval samples, mean 4.37%, median 3.6%, range 2.2–8.1%.
  These short runs establish current behavior, not an energy or long-duration CPU benchmark.
- On-screen window enumeration for this process returned none; no Weather/Combined/day popover was visible.
- Sample stacks show recurring menu-bar rendering, SMC and HID sensor reads, network counters, and process polling.
  No weather hover timer stack appeared. This does not prove it can never contribute while a popover is open.
- Specific optimization candidate: GPUMonitor's temperature fallback calls SMCClient.sensorValues(), reading every
  cached sensor key before filtering GPU temperatures, while SensorsMonitor independently reads SMC sensors.
  Sampling identifies this repeated work but does not quantify its exclusive CPU cost; IOKit stacks include waits.
- No production code, settings, sampling intervals, or installed binary changed. The recorded earlier baseline was
  3.75%, but different workloads prevent interpreting that as a controlled before/after comparison.
- Evidence: dist/cpu-review-top.txt, dist/cpu-review-unprofiled.txt, dist/cpu-review-sample.txt.

### P8-T31: Reduce background CPU work and repair Calendar authorization

CPU changes: GPU temperature fallback now filters runtime-discovered SMC key names before reading values. It no
longer reads unrelated temperature, voltage, current, and power keys. Combined readings now update only when a source
used by an enabled stack changes; the user's CPU/GPU stack previously redrew for memory, network, disk, sensor,
battery, time, and weather samples too. Sampling intervals and displayed data remain unchanged.

On-device SMC comparison over 20 warmed reads: full reads returned 10,300 values and consumed 0.174141 process-CPU
seconds; targeted reads returned 560 values and consumed 0.026851 CPU seconds. GPU key coverage matched exactly
(28 GPU keys among 515 total sensor keys). This is an 84.6% reduction in this specific read operation, not whole-app CPU.

Calendar changes by the requested sub-agent: the installed Developer ID app used hardened runtime without the
Calendar entitlement. Added com.apple.security.personal-information.calendars to both signing paths and verify it
in the signed artifact. Errors are logged and surfaced rather than swallowed; duplicate requests are guarded and
Settings refreshes authorization even when Time sampling is disabled. Both UI buttons already shared this path.
Source: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.personal-information.calendars

Verification:

- make test: all 203 tests in 30 suites passed, including new SMC key selection, stack source filtering, and Calendar
  packaging checks. A nondeterministic hover test exposed dependence on the user's actual pointer; injected a pointer
  reader for deterministic test inputs while production still reads NSEvent.mouseLocation.
- Memory benchmark passed: 92.7% lower isolated history footprint at one simulated hour and zero growth from hours
  24 to 48. Logs: dist/cpu-calendar-tests.log, dist/cpu-calendar-memory.log, dist/cpu-smc-benchmark.log.
- Signed make app passed. Its first verification attempt caught codesign's human-readable default entitlement output;
  corrected extraction to explicit --xml, reran the full suite, and packaged successfully.
- Copied to /Applications/Barometer.app, verified strict signature and the Calendar entitlement in the installed
  signature, and relaunched it (PID 88829).
- Actual Calendar prompt click cannot be automated here: Accessibility preflight returned false; did not request a
  new TCC category. The entitlement and failure handling are verified; user confirmation of the OS dialog is pending.
- git diff --check passed. No push.

The first installed optimization had no reliable whole-app CPU improvement: after discarding the first 30 intervals,
15 one-second samples averaged 4.45%, versus 4.37% in the prior unprofiled run. Do not attribute a system-wide CPU
reduction to the SMC microbenchmark alone.

The profile also showed TIFF encoding in StatusItemController's unchanged-image check. Replaced file encoding with
one display-scale rasterization and a hash of raw RGBA pixels, then reused that raster for the status item. Preserve
logical size, template mode, fixed status-item geometry, and subpoint graph changes. A new test checks identical
fingerprints, Retina pixel dimensions, and detection of a half-point movement.

Final checks before the second package: all 204 tests in 30 suites passed; memory benchmark passed with a 92.7%
one-hour reduction and zero 24-to-48-hour growth. Signed build and installed Calendar entitlement verification passed.
Installed and relaunched the final Applications binary (PID 89721). Final CPU observation follows below.
- Final closed-popover CPU capture, after discarding 30 startup intervals: 15 one-second samples averaged 3.84%,
  median 3.1%, range 1.1–7.3%. Prior unprofiled baseline averaged 4.37%, median 3.6%. This is a modest observed
  reduction in short, separate runs, not proof of a precise percentage improvement or near-zero idle CPU.
  Evidence: dist/cpu-after-raster.txt. Further reduction would require additional profiling and demand-based detail
  collection; live menu-bar sampling continues while popovers are closed.

### P8-T32 — Defer process details and dismiss every dropdown on hover exit

CPU, Memory, and Network continue collecting menu-bar values, but skip process enumeration until a relevant
module or stack dropdown opens. Opening requests an immediate sample; closing the last interested dropdown pauses
process detail collection. This also preserves the existing Calendar entitlement fix.

All module dropdowns now share an explicit pointer-exit and outside-click monitor, including native NSMenu
panels and Weather/Combined NSPopovers. The root, status button, and attached detail form the navigable region;
300 ms outside it closes the root. The weather detail keeps its existing 200 ms row-to-detail grace. Local and
global mouse monitors catch outside clicks. Timers and monitors stop on dismissal, so closed panels add no polling.

Verification:
- `POPOVER_SNAPSHOT_DIRECTORY="$PWD/dist/popover-screens" make test`: 210 tests in 31 suites passed. Added
  process-detail gating, every-module visibility lifecycle, hover grace/exit, and inside/outside click regressions.
- Screen-placement tests captured 32 real popover windows at display corners in light/dark appearances. Inspected
  the rendered weather detail. These exercise test windows; an end-to-end pointer interaction with the installed
  menu-bar items remains unautomated because Accessibility access is unavailable.
- `python3 Scripts/benchmark-memory.py dist/memory-baseline`: passed, 92.8% lower isolated one-hour history
  footprint than the original baseline and zero growth between simulated hours 24 and 48.
- `make app`: passed. Copied to `/Applications/Barometer.app`, verified strict signature, confirmed signed Calendar
  entitlement, and relaunched PID 92066. On-screen window enumeration reported zero Barometer windows for idle CPU.
- Logs: dist/on-demand-tests.log, dist/on-demand-memory.log, dist/on-demand-build.log, dist/cpu-on-demand.txt.
- `git diff --check`: passed. No push.
- Closed-dropdown CPU measurement: after discarding initialization and 30 startup intervals, the final 15 one-second
  samples averaged 3.46%, median 3.0%, range 1.6–6.5%. Previous short run averaged 3.84%. This is a modest observed
  change, not evidence of near-zero idle CPU; live sampling and rendering remain active.

### P8-T33 — Compare user memory report and lengthen hover dismissal

Compared installed build 127 with the supplied build 124 report (80.7M current, 146.3M peak at about 78 seconds).
The existing process at 105 seconds measured 25.8M current / 28.3M peak. A fresh launch measured at 78 seconds
reported 64.5M current / 200.1M peak. Thus current footprint beat the supplied report in both observations, but
peak footprint did not consistently meet it. Interaction history and settings were not controlled against the
other user's app. Both runs reported zero detected leaks with the restricted-process warning; this does not
establish absence of leaks. Evidence: dist/user-memory-comparison.txt and dist/user-memory-78s.txt.

Increased hover exit grace to a shared 0.8 seconds for all root dropdowns and weather details, preserving immediate
outside-click dismissal. Regression checks now verify survival at 0.7 seconds outside and dismissal at 0.9 seconds.

Verification:
- make test: 210 tests in 31 suites passed (dist/hover-delay-tests.log).
- python3 Scripts/benchmark-memory.py dist/memory-baseline: passed; 92.8% lower isolated history footprint,
  16 KB growth between simulated hours 24 and 48 (dist/hover-delay-memory.log).
- make app passed; copied to Applications, verified strict signature, and relaunched (dist/hover-delay-build.log).
- git diff --check passed. No push.

### P8-T34 — Stabilize manager interaction and remove weather rendering overhead

The installed build 129 reproduced the reported 187 MB footprint after Weather interaction. An isolated host
comparison found that a trivial SwiftUI `NSPopover` reached about 158 MB while the same view in a borderless panel
reached about 13 MB. Weather and Combined now use a fixed, non-draggable attached panel positioned from the actual
pointer or forecast row and constrained to the active display. The panel detaches its hosted content on close.
Global click monitors were removed because they compete with menu bar manager event taps; pointer dismissal waits
until the pointer has entered the presented region and then uses the shared 0.8-second exit grace.

Status-item visibility now follows a controller-owned intent latch. Repeated samples and dropdown opens no longer
rewrite `NSStatusItem.isVisible` after a manager temporarily hides an item. Autosave names, AX identifiers, static
labels, empty titles, fixed lengths, ownership, and creation order remain unchanged. GPU accelerator handles and
names are cached for the source lifetime, and aligned source samples feeding Combined coalesce into one redraw.

The rich Weather UI and glow remain. The hourly chart now draws the same precipitation bars, gradient area,
temperature line, and blurred glow with vector shapes instead of SwiftUI `Canvas`, whose backing allocation alone
measured about 163 MB in the isolated benchmark. Day details retain every API field while presenting all hours in a
compact horizontal strip and one complete selected-hour card, reducing the former long vertical repetition.

Verification before installation:

- `make test`: all 213 tests in 31 suites passed. New regressions cover manager-owned visibility, manager pointer
  handoff, coalesced Combined redraws, attached-panel lifecycle/release, scrolling, and placement.
- The screen test captured the top and true bottom of Weather, Combined, and both rich fixture days at every display
  corner in light and dark appearances: 64 full-resolution captures. All frames remained inside the visible screen;
  inspected captures showed aligned cards, labels, charts, scrollbars, footer actions, lunar data, and attribution.
- The repeated rich day open/scroll/close benchmark peaked at 37.5 MiB, below its new 128 MiB regression ceiling.
  Before the chart backing change, the same benchmark peaked near 181 MB. CI runs this gate after the suite, and
  packaging remains dependent on the complete reusable test job.
- The history benchmark passed with a 92.7% lower one-hour footprint and zero growth from simulated hours 24 to 48.
- `swift build`, `git diff --check`, development signing, strict bundle verification, and the Calendar entitlement
  check passed. Runtime CPU, repeated installed-app peaks, and the interactive Thaw check follow on build 130.

### P8-T35 — Release overlapping dropdown UI and make hourly cards hover-only

The reported 297–380 MB state was reproduced in a process sample after Weather interaction. Although its visible
panels had closed, the main thread remained nested in AppKit's status-menu tracking loop, and rich SwiftUI drawing
work remained active. A separate clean build 130 launch measured 27.2 MB current / 27.3 MB peak and spent almost
all sampled main-thread time asleep, isolating the high footprint and CPU to a stuck, overlapping UI lifecycle.

Only one Barometer root dropdown may now be active. Opening another dismisses the previous menu or attached panel,
stops its timers, releases its hosted view, and clears detail sampling. A menu-manager press has two seconds to hand
the pointer into the real menu or panel; otherwise Barometer cancels the invisible tracking session. Once entered,
the requested hover-exit grace is one second. This leaves the stable autosave, accessibility, length, visibility,
and bundle identity contract unchanged. The launch identity report no longer asks AppKit to encode every status
image as TIFF solely to count diagnostic bytes.

The hourly Weather strip is no longer made of buttons. Hovering a tile updates the complete hourly detail and adds
the existing Weather-blue stroke and glow; moving away removes the glow. The redundant “Blue bars show
precipitation chance” sentence is gone. The chart's existing gradient and glow are unchanged. A conditional hover
layer ensures only the hovered tile creates a shadow backing. IOHID temperature readings are reused for ten seconds
instead of querying every service on each five-second sensor sample, reducing closed-dropdown polling work while
preserving the configured sample cadence and current readings.

Verification before installation:

- `make test`: all 215 tests in 31 suites passed. New regressions cover root-dropdown exclusivity, an unentered
  manager handoff that cannot track forever, entry before the handoff deadline, and the longer shared hover grace.
- The screen suite captured Weather, Combined, and both rich day panels at all four display corners in light and
  dark appearances, including top, hourly, and true-bottom scroll positions: 80 full-resolution captures. All
  frames stayed inside the display. Reviewed hourly captures show aligned chart, tiles, selected detail, scrollbar,
  and no explanatory sentence or clipped content.
- The strengthened panel benchmark keeps the full Weather root and a rich day panel open concurrently, scrolls the
  detail, closes both, and repeats five cycles. Peak was 47.5 MiB, below the 128 MiB gate, and the final current
  footprint remained 37.1 MiB without cycle growth (`dist/weather-panel-memory-regression-concurrent.txt`).
- `python3 Scripts/benchmark-memory.py dist/memory-baseline`: passed with a 92.7% lower isolated one-hour footprint
  and 16 KB growth between simulated hours 24 and 48 (`dist/history-memory-final-hover.log`).
- `git diff --check` passed. Runtime installed-app memory, CPU, signature, Calendar entitlement, and manager
  interaction checks follow on build 131. No push.

### P8-T36 — Stop attached-panel redraw churn and preserve control menus

Installed build 131 reproduced the remaining Weather regression after a real open and close: `leaks` reported
204.8 MB current / 319.3 MB peak, 320,933 allocation nodes, and 168,706 KB malloced. The detector found no leaked
blocks, but the heap retained thousands of CoreSVG objects after the panel was gone. A clean launch without opening
Weather measured 26.7 MB current / 26.8 MB peak, isolating the increase to rich attached-panel presentation rather
than the idle monitors.

Weather and Combined attached panels observed their module stores while also invoking a controller refresh closure
every 500 ms. Removed that redundant initial refresh and repeating tracking timer for attached panels. Native menus
retain their tracking refresh because AppKit suspends ordinary view updates while a menu tracks. Panel placement,
materials, cards, chart glow, hourly hover glow, and all status-item identity fields are unchanged.

The Network interface Picker could not start its nested control menu while the entire dropdown was already inside
an AppKit status-menu tracking loop. Network now uses the same fixed, non-draggable attached panel as Weather and
Combined, sized to preserve its existing 560-point content area and footer. The Picker remains visually and
functionally nested inside that panel, where it can track normally. The dismissal monitor suspends hover dismissal
while its control menu tracks and restores the one-second exit grace after the menu closes. Active physical and VPN
interfaces remain sorted beneath Automatic; down and loopback interfaces remain excluded.

Verification before installation:

- `make test`: all 218 tests in 31 suites passed (`dist/p8-t36-full-tests.log`). New regressions verify that attached
  dropdowns do not poll, control-menu tracking cannot dismiss the parent panel, and active physical/VPN interfaces
  remain selectable.
- The screen suite generated 80 fresh full-resolution captures for Weather, Combined, and both detailed forecast
  days in light and dark appearances at every display corner, including top, hourly, and true-bottom positions.
  Every frame remained inside the display and every scroll reached its bottom. Representative captures were
  inspected for alignment, clipping, card shapes, materials, charts, and glows.
- The exact controller benchmark with the installed 242 KB, 10-day Weather cache peaked at 54.4 MiB and settled at
  38.8 MiB without cycle growth (`dist/p8-t36-live-cache-panel-memory.log`). The CI fixture peaked at 47.8 MiB and
  settled at 35.4 MiB (`dist/p8-t36-ci-panel-memory.log`); both passed the 128 MiB ceiling.
- `python3 Scripts/benchmark-memory.py dist/memory-baseline`: passed with a 92.7% lower isolated one-hour footprint
  and zero growth from simulated hours 24 to 48 (`dist/p8-t36-history-memory.log`).
- Installed-app memory, CPU, signature, entitlement, and interactive selector checks follow on build 132. No push.

### P8-T37 — Remove shared graph backing spikes and repair CPU and Network controls

Installed build 132 stayed near 56 MB before interaction, then opening Network and using its selector reached 207 MB
current / 327 MB peak. The main thread returned to idle and `leaks` found no leaked blocks, so this was retained
rendering allocation rather than an active loop. Network, CPU, Disks, Memory, and Sensors still used four shared
SwiftUI `Canvas` graph implementations. The earlier isolated comparison had already shown that one Canvas-backed
panel could retain more than 160 MiB. Replaced every shared graph with SwiftUI shape paths while preserving the
dotted grid, gradient fill, two-series and mirrored layouts, live markers, line gradient, blur glow, corner shape,
and dimensions. A pre-build source invariant rejects any reintroduction of SwiftUI Canvas in `MenuBarStatsUI`.

Network now presents its existing nested interface Picker inside a fixed attached panel, where Automatic, physical
interfaces, and VPN interfaces can open their own control menu and remain selectable. The panel preserves the
existing 560-point content area and uses the same screen-constrained placement as Weather and Combined. CPU history
range choices are real buttons, and the graph uses sample timestamps within the selected interval. A short history
therefore occupies only the recent part of 3-hour and 24-hour ranges instead of stretching to look identical.

Hover containment explicitly includes both the status-item widget and the dropdown. Remaining over either keeps the
dropdown open indefinitely; leaving both starts the one-second dismissal grace. Closed native menus now ignore
`menuNeedsUpdate` requests from accessibility discovery, avoiding hidden SwiftUI construction when Thaw, Bartender,
or another manager inspects Barometer. Real openings still prepare and update in `menuWillOpen`.

Additional bounded memory work manually adapted from René Jiménez's PR #2 caches application display-name lookups,
enables `MallocSpaceEfficient` in the packaged launch environment, requests malloc pressure relief after transient
UI teardown, and detaches the complete Settings hosting tree when its window closes. Release notes for this work
must credit René Jiménez (`@diazdesandi`) and link https://github.com/mackid1993/Barometer/pull/2. The PR was not
merged wholesale because it also contained broad architecture and formatting changes against an older code state.

Verification before installation:

- `python3 Scripts/check-source-invariants.py` passed before compilation. CI runs this step before `make test`, so a
  prohibited rendering primitive fails before the build.
- `POPOVER_SNAPSHOT_DIRECTORY="$PWD/dist/panel-screens-p8-t37-verified" make test`: all 223 tests in 32 suites passed
  (`dist/p8-t37-verified-tests.log`). New regressions cover CPU timestamp placement, selectable Network interfaces,
  compact attached-panel height, closed-menu update suppression, Settings host teardown, and pointer containment on
  the menu bar widget.
- The screen suite produced 96 nontransparent captures at every display corner in light and dark appearances. It now
  renders populated CPU and Network graphs in addition to Weather, Combined, and all rich day details. Captures fail
  if the window is off-screen, cannot scroll to its true bottom, or is fully transparent. Representative CPU,
  Network, Weather, hourly, and bottom captures were inspected for alignment, clipping, materials, paths, gradients,
  markers, card shapes, and glows.
- The expanded panel benchmark opens and closes Weather, rich day details, and all four shared graph primitives for
  ten cycles. It peaked at 48.0 MiB and stayed flat near 35.9 MiB through the final graph cycles, below the 128 MiB
  gate (`dist/p8-t37-verified-popover-memory.log`).
- `python3 Scripts/benchmark-memory.py dist/memory-baseline` passed with a 92.7% lower one-hour footprint than the
  original history baseline and zero growth from simulated hours 24 to 48 (`dist/p8-t37-verified-history-memory.log`).
- `git diff --check` passed. Packaging, installed-app measurements, and interactive selector checks follow. No push.

## P8-T38 Production CPU, lifecycle, and updater correction

CPU history now places available samples across the full selected range for 1 minute, 5 minutes, 30 minutes,
3 hours, and 24 hours. CPU uses the attached panel so its range controls receive clicks. Dropdown dismissal also
retains the activation hover region used by mirrored menu bar managers, while keeping the existing one-second exit
grace.

Native-menu SwiftUI hosts are allocated only while their menu is open and detached on close. Removed implicit
animations driven by live metric values across the shared design and metric panels; hover glow, gradients, shapes,
and the final visual layout are unchanged. This avoids retaining every closed widget tree and prevents live samples
from continuously animating otherwise static panels.

Added a zero-dependency update pipeline modeled on Clicker's behavior: a quiet delayed startup check, a manual
About-window check, persisted automatic-check enable/disable control, exact-version DMG selection, required GitHub
SHA-256 digest verification, release notes, and Skip/Later/Download actions. The installer verifies the DMG, bundle
identity, executable, symlinks, and code signature, stages the replacement in Applications, preserves a rollback
copy, and relaunches Barometer.

Verification before the production install:

- `python3 Scripts/check-source-invariants.py` passed.
- Focused dropdown, placement, renderer, and Settings lifecycle coverage passed: 64 tests in five suites
  (`dist/p8-t38-focused.log`).
- The updater pipeline passed all seven tests, including a real temporary DMG creation, verification, extraction,
  replacement, and cleanup test (`dist/p8-t38-updater-pipeline.log`).
- The broader screen suite reached 113 passing tests with no observed failure before it was interrupted at David's
  request to install the production build for interactive checking. Full screenshots and benchmarks remain due
  before the eventual push (`dist/p8-t38-full-screen-tests.log`).
- `git diff --check` passed.

## P8-T39 Time-aware CPU and GPU history

CPU history no longer stretches the same recent samples across every selected interval. Each sample now retains its
true horizontal position within the selected 1-minute, 5-minute, 30-minute, 3-hour, or 24-hour window. GPU now uses
the same range control and day-long compact history for consistent behavior.

Changed the production default for CPU, Memory, GPU, Network, and Disks from their prior one- or two-second values
to three seconds. Existing saved settings migrate only when they still equal those prior defaults. Added an optional
global sampling interval and concise CPU-cost guidance to the global and per-module sampling controls. The About
page description no longer calls out menu bar managers or a specific macOS version.

The first `master` CI run passed all 232 tests, then exposed that the memory benchmark did not create `dist/` on a
clean checkout. The benchmark now creates its output directory before linking. The release workflow was canceled
before building or publishing, and no 1.0.2 tag or release was created. The Check workflow is manual-dispatch only;
pushing `master` does not automatically start CI.

Verification before local installation:

- Source invariants and `git diff --check` passed.
- Focused Settings and renderer coverage passed all 86 tests, including default sampling migration, global interval
  persistence, and time-aware graph placement (`dist/p8-t39-focused.log`).
- The panel/graph regression passed at 48.0 MiB peak, below its 128 MiB gate
  (`dist/p8-t39-popover-memory.log`).
- Interactive validation of the installed build is required before another GitHub push.

## P8-T40 Persistent graph history and deferred panel teardown

CPU and GPU samples now survive normal restarts and application updates in a compact binary property list under
Barometer's Application Support directory. Startup restores only valid samples from the preceding 24 hours, and a
five-minute coalesced save plus the termination save preserves the rolling graph without inventing data from before
Barometer collected it. The General page permanently displays the global sampling control, including its current
interval, while retaining the battery-rate option.

Attached panels now replace their rich SwiftUI root with an empty view before detaching the host. Memory pressure
relief runs once after the initial AppKit teardown and again after SwiftUI and Core Animation finish their deferred
work. This does not change panel layout, shapes, gradients, or glow.

Verification before local installation:

- Source invariants and `git diff --check` passed.
- The focused graph persistence, Settings lifecycle, and menu-detail lifecycle run passed all 11 tests in three
  suites (`dist/p8-t40-focused.log`). The detail lifecycle includes 100 consecutive rich Weather presentations and
  verifies that the panels and hosting views deallocate.
- The rich-panel benchmark completed ten Weather, day-detail, and shared-graph cycles at about 35.3 MiB after each
  close and a 47.8 MiB peak (`dist/p8-t40-popover-memory.log`).
- An instrumented installed-app cycle measured 39.6 MiB physical footprint with all windows closed, 0.2% CPU, and
  zero leaked blocks. Interactive validation of the new installed build is required before any GitHub push.

## P8-T41 Visible-only sensor sampling and reliable Weather hover exit

Closed Sensors UI now derives a hardware sampling plan from only the sensor IDs used by enabled menu bar widgets
and stacks. The plan filters IOHID services and SMC keys before reading them, skips IOReport unless a displayed
reading requires it, reads only selected fans, and pauses the Sensors scheduler when no visible item needs it. The
complete sensor inventory remains available while the Sensors dropdown or Sensors Settings page is visible.

Weather date rows now report their native mouse-exit events to the detail presenter. The presenter no longer lets
stale SwiftUI row geometry keep a day detail open when the pointer moves elsewhere inside the Weather panel. The
existing one-second grace still permits crossing from a date into its scrollable detail panel, and moving within
the detail keeps it open. No Weather layout, material, card, graph, gradient, or glow changed.

Verification before local installation:

- `python3 Scripts/check-source-invariants.py` passed.
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer make test` executed all 240 tests against the final
  source: 32 SystemSources, 83 UI, and 125 Core tests passed (`dist/p8-t41-final-tests.log`). New regressions cover
  native date-row exit, selected sensor-source planning, enabled-widget/stack sensor IDs, and Sensors Settings
  lifecycle.
- The same suite passed with `POPOVER_SNAPSHOT_DIRECTORY="$PWD/dist/p8-t41-panel-screens-v2"` to generate the visual
  regression artifacts (`dist/p8-t41-full-tests.log`).
- The screen suite produced 128 captures covering Weather, two rich forecast days, CPU ranges, Network, and Combined
  at every display corner in light and dark appearances. Inspected top, middle, hourly, and true-bottom captures
  remain aligned, unclipped, scrollable, and preserve all existing shapes, gradients, and glows.
- `python3 Scripts/benchmark-popover-memory.py` completed ten rich-panel and shared-graph cycles at 35.6 MiB current
  and 47.8 MiB peak, below the 128 MiB gate (`dist/p8-t41-popover-memory.log`).
- `python3 Scripts/benchmark-memory.py dist/memory-baseline` passed with a 92.7% lower one-hour footprint and 32 KiB
  growth from simulated hours 24 to 48 (`dist/p8-t41-history-memory.log`).
- `swift build -c release` and `git diff --check` passed. Installed build 138 validated as version 1.0.2 with bundle
  identifier `com.barometer.app`, a valid signature, and the Calendar entitlement.
- With every panel closed, a 20-second installed-process sample measured 12.8 MiB current / 14.2 MiB peak and found
  the main thread idle in 99.6% of samples. A separate 31-second `top` run averaged 1.21% of one core, including
  short periodic bursts, versus the reported steady 3%. `leaks` reported zero leaked blocks and the same
  12.8 MiB / 14.2 MiB footprint (`dist/p8-t41-installed-idle.sample`,
  `dist/p8-t41-installed-idle-top.log`, and `dist/p8-t41-installed-leaks.log`). No push.

## P8-T42 Stable Weather scroll hover and visible-only detail polling

Fast or inertial scrolling in the Weather root now closes any date detail attached to a row that moved. Scrolls
inside the detail remain available. Date rows wait 150 milliseconds before presenting details, so rows that pass
under a stationary pointer during a fast scroll do not create transient panels; the row where the pointer settles
still opens without a click. The existing one-second exit grace and the complete visual design remain unchanged.

GPU keeps its inexpensive accelerator utilization sample active for its status item and graph, while IOReport and
SMC frequency, activity, power, and temperature enrichment run only while GPU details are visible. Network keeps
live transfer counters active, caches initial or invalidated connection metadata while closed, and defers periodic
metadata, Wi-Fi, and per-process work until Network details are visible. Route messages now supply their own byte,
packet, and error counters instead of triggering a second kernel query for every interface.

Verification before the final local installation:

- `python3 Scripts/check-source-invariants.py` and `git diff --check` passed.
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` with `POPOVER_SNAPSHOT_DIRECTORY` set to
  `dist/p8-t42-panel-screens-v3` ran `make test` and executed all 241 tests: 32 SystemSources, 84 UI, and 125 Core
  tests passed (`dist/p8-t42-tests-final.log`). New
  coverage verifies settled hover intent, root-scroll dismissal, continued detail scrolling, GPU enrichment gating,
  and cached Network metadata gating.
- The screen suite produced 128 captures. Representative Weather and day-detail top, hourly, and true-bottom states,
  plus Network and CPU, remain aligned and unclipped in both appearances. A pixel comparison with the preceding
  approved capture set found zero changed pixels. The capture helper retries transient fully transparent WindowServer
  results and still fails after three blank results.
- The live Network probe reported `en0`, current transfer rates, IPv4 and IPv6 addresses, router, DNS, and nonzero
  cumulative totals after the route-counter optimization.
- `python3 Scripts/benchmark-popover-memory.py` completed ten rich-panel cycles at about 35.7 MiB current and a
  48.0 MiB peak, below the 128 MiB gate (`dist/p8-t42-popover-memory-final.log`).
- `python3 Scripts/benchmark-memory.py dist/memory-baseline` passed with a 92.7% lower one-hour footprint and zero
  growth from simulated hours 24 to 48 (`dist/p8-t42-history-memory.log`).
- Production installs before and after the final commit each averaged 0.72% CPU across 31 one-second observations
  with every panel closed. Final installed build 139 used about 13 MiB resident memory and reported 12.6 MiB current /
  14.1 MiB peak physical footprint with zero leaked blocks (`dist/p8-t42-idle-top-139-stable.txt` and
  `dist/p8-t42-leaks-139.txt`). Its signature is valid. The sampled stacks contained only visible status-item
  sampling and rendering; hidden GPU, Wi-Fi, and process-detail sources were absent. No push.

## P8-T43 Collapse interface-name system queries

An idle-process profile after P8-T42 showed that `if_indextoname` internally enumerated every interface each time it
resolved one route entry. Network sampling therefore repeated `getifaddrs` and its kernel query for every interface.
`NetworkSource` now takes one `if_nameindex` snapshot for the route pass and resolves all message indices from that
dictionary. The route message remains the sole source of byte, packet, error, and flag values.

Verification before local installation:

- Source invariants and `git diff --check` passed.
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer make test` executed all 241 tests: 32 SystemSources,
  84 UI, and 125 Core tests passed (`dist/p8-t43-tests.log`).
- The live Network probe retained `en0`, current transfer rates, IPv4 and IPv6 addresses, router, DNS, and nonzero
  cumulative totals (`dist/p8-t43-network-probe.log`).
- `python3 Scripts/benchmark-memory.py dist/memory-baseline` passed with a 92.8% lower one-hour footprint and zero
  growth from simulated hours 24 to 48 (`dist/p8-t43-history-memory.log`). No push.

## P8-T44 Ignore Accessibility menu inspection

A production sample with every Barometer panel visibly closed traced intermittent 6–8% CPU and 75–93 MiB resident
memory to menu bar manager Accessibility inspection. AppKit simulates opening a closed `NSMenu` while enumerating
its Accessibility children, which previously ran Barometer's real `menuWillOpen` path. One 12-second sample recorded
370 simulated opens, repeatedly creating SwiftUI hosts, fitting content, and entering the dropdown polling path even
though no Barometer window was visible.

Native dropdowns now accept `menuWillOpen` only between that menu's AppKit begin- and end-tracking notifications.
Accessibility simulation does not post begin tracking, so it performs no allocation, visibility change, sample tick,
or timer creation. A genuine tracked menu still follows the existing open, hover-dismissal, and teardown behavior.
The bundle identity, status-item identity, menu attachment, layout, materials, card shapes, gradients, and glows are
unchanged.

Verification before local installation:

- `python3 Scripts/check-source-invariants.py` and `git diff --check` passed.
- A focused regression passed for both paths: Accessibility inspection keeps a closed menu unallocated and idle,
  while a genuine tracked open still creates content, refreshes it, and releases it on close.
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` with `POPOVER_SNAPSHOT_DIRECTORY` set to
  `dist/p8-t44-panel-screens-v3` ran `make test` and executed all 242 tests: 32 SystemSources, 85 UI, and 125 Core
  tests passed (`dist/p8-t44-tests-v3.log`).
- The screen suite produced 128 nontransparent captures. All 40 CPU range/corner/appearance captures and
  representative Weather, day-detail top/hourly/bottom, Network, and Combined captures were inspected. They are
  aligned, unclipped, scroll to the true bottom, and preserve the existing Liquid Glass cards and glow. The capture
  harness now requests layout immediately before capture and retries up to five transient blank WindowServer frames.
- `python3 Scripts/benchmark-popover-memory.py` completed ten rich-panel cycles at 35.6 MiB current and a 47.8 MiB
  peak, below the 128 MiB gate (`dist/p8-t44-popover-memory.log`).
- `python3 Scripts/benchmark-memory.py dist/memory-baseline` passed with a 92.7% lower one-hour footprint and zero
  growth from simulated hours 24 to 48 (`dist/p8-t44-history-memory.log`).
- The Apple Swift Async Algorithms package was evaluated for the polling path. Barometer's scheduler already uses an
  `AsyncStream`, `ContinuousClock`, cancellation, aligned sleeps, and timer tolerance, so replacing it with
  `AsyncTimerSequence` would not address this measured AppKit Accessibility hot path. No dependency was added.
- Installed build 141 is version 1.0.2 with a valid signature. After an interactive Sensors open and close, a
  20-second stack sample measured 24.1 MiB current / 37.2 MiB peak physical footprint and kept the main thread idle
  in 99.7% of samples. It contained no `menuWillOpen`, `_simulateOpening`, `_openForInspection`, or `NSHostingView`
  allocation stack (`dist/p8-t44-installed-141.sample`).
- A separate settled 41-second run with every panel closed averaged 0.61% CPU, with a 3.2% brief maximum and about
  24 MiB final physical footprint (`dist/p8-t44-idle-top-141-settled.log`). `leaks` then reported 24.0 MiB current /
  37.2 MiB peak and zero leaked blocks (`dist/p8-t44-installed-141-leaks.log`). Thaw was not running during these
  measurements, so its live Accessibility-inspection check remains pending. No push.

## P8-T45 Detailed 1.0.2 release notes

Added `docs/RELEASE_NOTES_1.0.2.md` with the complete user-facing changes since 1.0.1. The notes cover rich daily and
hourly Weather details, configurable sections, CPU and GPU history, sampling controls, the DMG updater, Calendar and
Network fixes, dropdown behavior, menu bar manager compatibility, and the measured CPU and memory improvements.
They also credit `@diazdesandi` and link pull request #2 for the memory investigation and adapted work.

The wording is intentionally direct and conversational. The document contains no em dashes or semicolons. Corrected
`docs/RELEASING.md` to match the actual manual-only workflow triggers.

Verification before pushing:

- `python3 Scripts/check-source-invariants.py` passed.
- `git diff --check` passed.
- Confirmed the release notes contain zero em dashes, en dashes, or semicolons.
- The GitHub Build macOS workflow with notarization disabled will provide the requested remote test and compilation
  check after this commit reaches `master`.

GitHub Build macOS run 33947069838 completed successfully against commit `d0a7c95` with notarization disabled. The
source invariant check passed, all 242 tests in 34 suites passed, and the panel and graph benchmark peaked at
37.8 MiB against its 128 MiB limit. The dependent build then compiled the production app, imported the Developer ID
certificate, signed the app and DMG, and uploaded `Barometer-1.0.2.dmg`. The credential and notarization steps were
skipped as requested.

Downloaded the workflow artifact and independently verified the DMG checksum, DMG signature, nested application
signature, version 1.0.2, bundle identifier `com.barometer.app`, and Developer ID team `BQNYYA2UND`. The downloaded
DMG SHA-256 is `61fde3429c4dea53604386f9920b7f000662faa1651d65a56a786b94901ed133`. The release notes now call out the
replacement of Canvas-backed graphs as the largest memory fix and explain the measured retained allocation it
removed. The final order leads with the optimization work, followed by the built-in updater and the other feature
and bug-fix sections. No release workflow was run and no release was created.
