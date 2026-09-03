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
