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

The same internal-spacing rule now applies to Network: three logical points separate each arrow from its live rate so
the gap remains optically visible after AppKit antialiasing. Sensor labels use the same gap. Separate sensor columns
retain a one-device-pixel separator based on `RenderContext`'s destination display scale. Unused stability width is
balanced on both sides of each visible pair instead of collecting entirely inside the pair or before the widget.
Prefix edges are snapped upward to the device-pixel grid before the separator is added. These internal rules do not
change AppKit's spacing between independently movable items.

Verification:

- An isolated defaults-suite test verifies both legacy Barometer application-domain values are removed.
- `swift test`, including geometry checks for the three-point dense-pair gap, pixel-snapped prefix edges, balanced
  reservation, and the one-device-pixel sensor-column separator, completed successfully.
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
