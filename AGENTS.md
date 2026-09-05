# AGENTS.md

Standing rules for any coding agent working in this repository. These override defaults.

## What this is

Barometer: a free, open source (MIT) macOS menu bar system monitor that replaces iStat Menus and works with menu bar
managers (Thaw, Bartender) on macOS 27. Design: `docs/DESIGN.md`. Plan: `docs/PLAN.md`. Progress log:
`docs/PROGRESS.md` (create it on first use). Read `docs/AGENTS.md` before changing macOS 27 integration behavior.

## Environment

- macOS 27.0 beta on an Apple M4 Pro MacBook Pro. SwiftPM uses the Xcode 27 command-line toolchain: Swift 6.4 and
  SDK 27.0. The local bundle is `/Applications/Xcode-beta.app`; GitHub uses the `xcode-27` runner.
- Build with SwiftPM: `make build`, `make test`, `make app`, `make run`, `make stop`. The Makefile selects Swift 6.4;
  direct `swift` commands need the same `DEVELOPER_DIR`. Never use `xcodebuild`. Never add an `.xcodeproj`.
- Zero third-party dependencies in v1.
- Thaw (`com.stonerl.Thaw`), iStat Menus, and Stats are installed. Never modify them, their preferences, or their launch agents. Do not launch Thaw; ask David to run it when a check needs it.

## The identity contract (never break this)

Full text in `docs/DESIGN.md` section 3.5. Short form:

1. The packaged `Barometer.app` process owns every status item. No command-line executable, helper, XPC service, or
   second bundle may create one. The app must validate its bundle identity before constructing `StatusItemRegistry`.
2. Bundle identifier `com.barometer.app`. Never change it.
3. Autosave names are fixed: `Barometer.CPU`, `Barometer.GPU`, `Barometer.Memory`, `Barometer.Disks`, `Barometer.Network`, `Barometer.Sensors`, `Barometer.Battery`, `Barometer.Weather`, `Barometer.Time`, `Barometer.Combined`. Extra instances are `Barometer.Weather.2` and so on. `ModuleID` in `MenuBarStatsCore` is the only place these strings live.
4. `NSStatusBarButton.title` is always empty. Menu bar content is an `NSImage` in `button.image`.
5. `setAccessibilityIdentifier(autosaveName)` and `setAccessibilityLabel(displayName)` once, never changed. The
   bundle identifies the owning Barometer app; the unique identifier and stable child label distinguish movable items.
   Live readings, including the module name, go in `setAccessibilityValue` only.
6. Never set the status item window's title. Never remove a status item; toggle `isVisible`. No `.removalAllowed`.
7. Single running instance.

## Code rules

- Swift 6 language mode with strict concurrency. No `@unchecked Sendable` without a comment explaining why. No `DispatchQueue.main.async` where `@MainActor` works.
- Layering: `CSystemSources` <- `SystemSources` <- `MenuBarStatsCore` <- `MenuBarStatsUI` <- `Barometer`. Nothing below `MenuBarStatsUI` imports AppKit or SwiftUI.
- Every system data source has an `isAvailable` check and degrades to "unavailable" in the UI. Private APIs (IOHID event client, IOReport, SMC) are wrapped in one type each in `SystemSources` and used nowhere else.
- No force unwraps or `try!` outside tests. Errors are logged with `os.Logger`, subsystem `com.barometer.app`, one category per module.
- Formatting: 4-space indent, 120 columns, `// MARK:` sections, doc comments on public API.
- American spelling everywhere: code, comments, commit messages, docs, UI strings. Examples: color, behavior, initialize, optimize, canceled, gray, center, license.

## Workflow rules

- Work the phases in `docs/PLAN.md` in order. Do not start the next phase without David's review unless told to continue.
- Every task ends with its "Verify" commands run and the output recorded in `docs/PROGRESS.md` under the task ID.
- Commit after every task: `P2-T1: add Open-Meteo client`. No attribution lines, no co-author trailers.
- If a data source does not behave as `docs/DESIGN.md` says, record what you observed in `docs/PROGRESS.md`, choose the nearest working approach, and explain it in the commit message. Do not invent values.
- Ask before: changing the bundle identifier or autosave names, adding a dependency, installing software, requesting a new TCC permission category, or touching anything outside this repository.
- Do not run `sudo`. Nothing in v1 needs root.
- Temporary files go in `dist/` or the system temp directory, never in the repository root.
