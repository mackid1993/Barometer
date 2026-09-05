# macOS 27 field guide for Barometer agents

This file is the project's durable operational memory for macOS 27. Read it before changing status-item identity,
menu bar layout, application packaging, permissions, or hardware sources. The normative product design remains in
`DESIGN.md`; the chronological evidence remains in `PROGRESS.md`.

Unless stated otherwise, these findings were observed on macOS 27.0 beta build 26A5425a (Darwin 27.0.0), on an
Apple M4 Pro MacBook Pro with 48 GB of memory. Treat an OS update as a reason to reverify them, not as permission to
silently discard the compatibility contract.

## Tested environment and hard constraints

- Development uses the Xcode 27 command-line toolchain through SwiftPM: Swift 6.4 and the macOS 27.0 SDK. The local
  bundle is `/Applications/Xcode-beta.app`; GitHub uses the `xcode-27` runner and its default `Xcode.app`.
- Barometer still targets macOS 26. Any macOS 27-only SDK symbol must have an availability gate and a working macOS
  26 fallback.
- Build with SwiftPM and the repository scripts. Never add an Xcode project or require `xcodebuild`.
- The production identity is `Barometer.app`, executable `Barometer`, bundle identifier `com.barometer.app`.
- Interactive compatibility checks must use `/Applications/Barometer.app`, installed with `make install`.
- Do not use `sudo`. Every implemented hardware path is read-only and works without a privileged helper.
- Thaw, Bartender, iStat Menus, and Stats are external test references. Never modify their preferences, launch
  agents, bundles, or processes. Do not launch Thaw; ask David when a live Thaw check is needed.

## What changed in the macOS 27 menu bar

Through macOS 26, menu bar managers could treat each status item as a separate status-level window. On the tested
macOS 27 build, WindowServer exposes one `Menubar` window plus a `MenuBarAgent` window. Managers reconstruct logical
items primarily through Accessibility and the window list. Multiple items from one application may initially be
treated as a group unless the manager can recover stable per-item identities.

This makes bundle ownership, AX identity, and lifecycle stability functional requirements rather than polish. A
visually correct item with unstable identity is broken because it cannot reliably retain its hidden/visible section
or position.

### Identity observed by menu bar managers

Thaw's macOS 27 implementation builds a persistent tag shaped like `namespace:title[:index]`:

- `namespace` is the bundle identifier of the process that owns the item.
- The title component can be derived from the status window name and the AX title, description, identifier, or value.
- A changed identity is treated as a new item and may be placed into the manager's new-item section.

Bartender's read-only catalog represented working Barometer items with identities such as
`axid:com.barometer.app:com.barometer.app:Barometer.CPU`. Its Golden Gate diagnostics can report a healthy runtime
and no visibility error while an individual item still fails placement if that item's identity or scene is wrong.

iStat Menus 7.30 illustrates both the useful and dangerous parts of this model. Its menu items share one owner,
`com.bjango.istatmenus.status`, but some identity-bearing titles contain live values. Thaw has a bundle-specific
normalization for those titles; a weather condition word can still change the identity. Barometer must never rely on
a menu bar manager adding a special case for it.

### Verified `NSStatusItem` and AX behavior

The repository probe established the following behavior on macOS 27:

| Operation | Status window title | AX label | AX title |
| --- | --- | --- | --- |
| Set `autosaveName` | Becomes the autosave name | Unchanged | Unchanged |
| Set `button.title` to a live value | Unchanged | Inherits the value unless overridden | Becomes the live value |
| Set an explicit AX label | Unchanged | Becomes the explicit label | Unchanged |
| Clear `button.title` and set an image | Unchanged | Retains the explicit label | Becomes empty |

Therefore, live text in `NSStatusBarButton.title` is an identity hazard even when the window title does not change.
Draw all visible menu bar text into an image and expose the changing reading only as AX value.

## The compatibility contract

These rules are normative and must not be weakened during refactors:

1. The packaged main process owns every status item. A command-line probe, helper, login item, XPC service, or second
   application bundle must never create one.
2. Validate the main bundle before constructing `StatusItemRegistry`. An unbundled `swift run Barometer` invocation
   must exit without touching `NSStatusBar`.
3. Keep the bundle identifier `com.barometer.app` and executable name `Barometer` unchanged.
4. Keep the fixed autosave-name table in `ModuleID` unchanged:

   | Module | Autosave name |
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

5. Number extra instances permanently as `.2`, `.3`, and so on. Removed instances become disabled tombstones;
   never reuse an identity for different content.
6. Keep `button.title` and AX title empty. Use `button.image` with `.imageOnly` and `.scaleNone`.
7. Set the AX identifier to the autosave name and the AX label to the static module name exactly once. Put live data
   only in AX value.
8. Never assign the status item's window title.
9. Create each requested status item once and retain it for the process lifetime. Hide with `isVisible`; do not remove
   and recreate it, and do not use `.removalAllowed`.
10. Run only one Barometer process. A second launch activates the existing settings window and exits.
11. Never reorder status items in application code. Leave position to macOS and the user's menu bar manager.

All status-item ownership must remain inside the one `Barometer.app` bundle. The earlier command-line identity probe
was removed because even a temporary item from an unbundled executable has no application bundle identity on macOS
27 and can pollute a manager's discovery state.

## Placement, visibility, and geometry findings

### A stable installation path matters

The same valid bundle behaved differently depending on launch path. From the repository's `dist/`
directory, MenuBarAgent accepted the client and completed scene creation, but CPU and Memory received zero-height
fallback frames and Bartender could not place them. Installing the unchanged identity at
`/Applications/Barometer.app` produced normal 33-point-high frames and restored manager placement.

Use `make app` to assemble an artifact, but use `make install` for every live menu bar test. Do not diagnose manager
compatibility from a repository-path launch.

### Launch shape and bundle metadata matter

- `LSUIElement` is the source of the agent application policy. Do not set the accessory activation policy before the
  AppKit run loop.
- Keep `NSPrincipalClass = NSApplication`, `CFBundleInfoDictionaryVersion`, the development region, and the Utilities
  application category in the generated `Info.plist`.
- The bundle must contain exactly one executable, `Contents/MacOS/Barometer`, and pass strict signature verification.
- Render content before making a newly requested item visible, and write visibility only when it actually changes.

### Hidden-item identity can collide during manager discovery

Bartender cold-start diagnostics exposed a real collision: an inactive `Barometer.Disks` record was paired with
Memory's AX identity, and inactive `Barometer.Combined` was paired with Network's. The safe behavior is narrow:

- Assign the autosave name and AX identity synchronously before the item's first visibility transition.
- Never remove or edit AppKit's visibility, preferred-position, or restore-position defaults.
- Never delete the actual status item merely to clear the collision.
- Barometer settings remain the visibility source of truth.

After this correction, David restarted Bartender and confirmed that all Barometer positions persisted.

### Live values must not resize status items

Reassigning even the same `statusItem.length` on every sample caused items to return to AppKit placement after a menu
bar manager restarted. A later UI refactor reintroduced the failure through a settings-change exception: changing the
font size, glyph scale, or the former density controls wrote a new live length and made items move again.

The rule is absolute: each controller may assign `statusItem.length` at most once per process lifetime, before making
the item visible. There is no exception for a user-initiated layout change, a debounced update, a manual recompute
command, or assigning the same numeric value. `StatusItemController` must remain the only production writer.

Font size and graphic scale are automatic and captured once from the complete saved widget set when the process
starts. Font weight is a live paint property and must redraw immediately inside the fixed canvas without assigning
`statusItem.length`; the initial canvas reserves the semibold rendering width so a later weight change cannot clip.
The one-way geometry latch prevents later settings changes from shrinking ink inside an
immutable frame and creating transparent trailing space. The one-way length latch prevents live AppKit resizing. Do
not persist rendered widths: every normal launch must render the current saved configuration, round its natural width,
and assign it once before the item becomes visible.

The complete decision, algorithm, prohibited alternatives, and regression checks are in
[`MACOS27_STATUS_ITEM_SIZING.md`](MACOS27_STATUS_ITEM_SIZING.md). Read it before changing menu bar typography,
rendered widths, or status-item lifecycle code.

Barometer adds zero horizontal padding around item canvases, including generic text, label/value stacks, sensor
stacks, icon-and-text rows, symbols, and vertical icon stacks. Do not expose item-spacing controls: changing
transparent padding inside an immutable frame only redistributes the same blank area and cannot change the actual item
spacing. Standalone numeric readings remain trailing-aligned inside their reserved fields. Ordinary stacked
label/value widgets share one leading edge; dense Sensors and Network pairs follow the compact rule below. Do not add
generic width allowances, half-point insets, or renderer-specific side padding.

Sensor stacks use explicit stable-width columns. Three logical points separate each label from its live reading,
and unused reservation width is balanced on both sides of the pair. Network is deliberately different: both arrows
are pinned to one leading origin and both values begin at one fixed origin after the three-point gap. A live rate may
never move an arrow. Snap prefix field edges to the device-pixel grid before adding a gap; a fractional glyph advance
can otherwise consume it. Never add a trailing exception based on the following widget or synthesize spacing with
flexible kerning.

Do not set `NSStatusItemSpacing` or `NSStatusItemSelectionPadding` in Barometer or in the by-host global defaults.
Before constructing `StatusItemRegistry`, remove application-domain values left by older Barometer builds so AppKit
uses its normal spacing behavior. Never change another application's preferences. Do not compensate for system
spacing with renderer-specific padding or assumptions about widget order.
Never bring back a live-width slider. Show/hide controls are the deliberate exception to otherwise-live settings:
stage those choices until the user selects **Apply Changes**, persist the complete set once, and perform a controlled
application reopen. The reopen is required so automatic sizing is calculated from the final enabled-item count before
any status item becomes visible. Never resize an existing item as part of Apply.

Do not add a condensed/high-density rendering mode. It narrows ink inside immutable live frames, producing larger
apparent inter-item gaps and unreadable text. Density comes only from purpose-built renderers.

Text, icon, and graph sizing is automatic and follows the enabled-item count. Do not expose a manual size control. The
automatic tiers are 115 percent for 1–3 items, 100 for 4–6, 90 for 7–8, 85 for 9–11, 80 for 12–14, and 75 for
15 or more. Each enabled Sensors instance counts; Combined counts once and its hidden members do not count.

Every item has the common app owner `com.barometer.app`, while its autosave name, AX identifier, and static
accessibility label remain unique child keys. The bundle is the common source-app identity; the child keys keep each
item independently movable. Prepare exactly the enabled, non-Combined-hidden identities before any item becomes
visible, then set each `autosaveName` and AX identity synchronously before its first `isVisible` transition. Creating
disabled hidden AppKit items gives managers persistence slots with no AX children and corrupts their ordinal pairing.
Create a newly enabled identity once, attach its controller and menu, then make it visible in that order. Never delete
or rewrite AppKit's preferred-position or
restore-position defaults. Doing so recycles persistence slots and can make managers pair one Barometer child's
identity with another.

At launch, controller construction order is not allowed to control visibility. Render and attach the entire prepared
set while hidden, then activate it synchronously in the same canonical `ModuleID` order used by
`StatusItemRegistry`. Otherwise a manager can observe a partial AX list whose ordinal order disagrees with the
already-created autosave slots. The activation gate belongs to the shared controller lifecycle and applies to every
module, including Weather, Network, graphs, and later Sensors instances.

A manager catalog contaminated by an earlier broken build is external state. A Barometer relaunch can expose that
stale join again even when the new process reports a completely correct live identity set. Do not mutate, delete, or
special-case another application's catalog to make a local test pass. Verify the Barometer report first, then ask the
user to refresh or reset Barometer's entries through that manager's own interface. A manager launched after the
complete Barometer set is already present has repeatedly rebuilt the correct one-to-one joins.

AppKit's variable-length image presentation also introduced its standard eight-point image inset on each side. An
explicit status-item length equal to the rendered image width is what makes zero user spacing possible while keeping
each module independently movable.

Every renderer needs one mode-specific canvas for unavailable, initial, and live states. Reserve enough width for
normal formatted values, use monospaced digits, and promote units before rounding expands the digit count. Do not
reserve implausible extremes: oversized placeholders created visible empty space around GPU, Network, and Weather.
The vertical Weather mode must reserve its compact temperature width without reserving the widest possible weather
symbol. Stable geometry means the outer status item stays fixed; it does not mean every item should be wide.

## Diagnostics that proved useful

The packaged app writes `~/Library/Logs/Barometer/identity.json`. For every active item, verify:

- bundle path is `/Applications/Barometer.app`;
- bundle identifier and running-application identifier are `com.barometer.app`;
- autosave name, window title, and AX identifier are the same fixed `Barometer.*` value;
- AX label is the static module name;
- AX title and `button.title` are empty;
- image dimensions are nonzero and status-item length equals the intended fixed canvas;
- window and button frames have nonzero height.

`Tools/probes/windows.swift` is useful for inspecting the WindowServer view. The app's `identity` log category records
the same invariants. Command-line diagnostics may print constants and inspect sources, but must not create status
items. Read Bartender or Thaw state only when needed and never write it.

A menu bar manager's new-item policy is not an application failure. Bartender on the test machine intentionally
placed newly discovered items in its hidden section. First prove that a stable item exists, then have the user move
it according to their manager policy.

## Updater scrolling on macOS 27

Do not put the updater's release-note document inside `NSScrollView`. On the tested macOS 27 build, trackpad input
started AppKit's concurrent display-link scrolling workers even when the scroll view's wheel handler was overridden.
The workers caused sticky two-finger scrolling and CPU use that remained elevated after the visible content stopped.

`ReleaseNotesViewport` deliberately uses a plain `NSClipView`, a wrapping read-only label, and a standalone
`NSScroller`. Precise and momentum deltas from `NSEvent` move the clip view directly. Formatting and document height
are computed once per width, and neither wheel events nor scrolling may rebuild the attributed string or trigger
layout preparation. Keep the regression test that proves the updater contains no `NSScrollView` and exercises a
long stream of precise pixel deltas. A brief repaint spike while text moves is expected; CPU must return immediately
to the application's normal idle range when scrolling stops.

## Hardware-source findings on macOS 27

Private interfaces must each stay behind one wrapper in `SystemSources`, be runtime-checked, and degrade to
unavailable. Do not spread private declarations through the app or invent a value when a source is missing.

### IOHID temperatures

- The private IOHID event-system path still returns live thermal events without root.
- Cache and reuse the event-system client and matched service list.
- The M4 Pro exposed three same-named services per SoC die and six for the battery. Average duplicate product names
  and retain the contributing count; do not choose an arbitrary duplicate.
- Reject non-finite, nonpositive, and implausibly high readings. Negative PMU calibration values are not temperatures.
- Friendly names can describe verified PMU, battery, SSD, and die roles, but raw names must remain available for
  diagnostics.

### IOReport

- The 26.2 Command Line Tools SDK has no IOReport link stub, although `/usr/lib/libIOReport.dylib` exists in the dyld
  shared cache on macOS 27. Direct symbol references fail at link time.
- Open the system path dynamically and resolve every symbol behind null checks. Missing libraries or symbols make
  IOReport unavailable; they must not prevent application launch.
- Discover `Energy Model`, legacy `PMP`, `CPU Stats`, and `GPU Stats` channels at runtime. Use two snapshots over a
  monotonic interval and Apple's delta operation.
- Honor reported J, mJ, uJ, and nJ units. Strip the `INT64_MIN` unpopulated sentinel.
- Avoid double-counting per-core rails when an aggregate cluster rail is populated.
- Discover `pmgr` properties whose names begin with `voltage-states`. Normalize Hz, kHz, and MHz by magnitude, retain
  repeated states in order, and match tables to runtime state counts. Never hardcode model, core count, or property
  index.
- Exclude DOWN, IDLE, and OFF states from the weighted active frequency but include them in the active-percentage
  denominator.
- GPU power remained useful, but CPU energy rails sometimes became unpopulated even under load. Report CPU power as
  unavailable for those intervals, never as zero or a large negative sentinel-derived value.
- IOReport subscription handles triggered a Swift 6.2.3 optimized-build cycle when destruction was actor-isolated.
  The verified boundary uses immutable Sendable handles released by a nonisolated destructor.

### AppleSMC

- The standard `AppleSMC` user client supports read-only access without privileges on the tested system.
- Keep the C ABI limited to metadata, indexed key enumeration, and byte reads. Do not add a write command, fan target,
  or control path.
- The M4 Pro exposed 3,462 keys. Enumerate and cache keys at runtime instead of shipping a model table.
- Decode integer, float, fan fixed-point, signed/unsigned fixed-point, character, `iof`, and Apple Silicon `ioft`
  values. The `ioft` type is required for real thermal and GPU readings on this Mac.
- Preserve raw bytes and type metadata. Numeric decodability does not establish sensor meaning.
- Firmware identifiers resembling `Tp…`, `TPQD`, `PP…`, or `PPPP1` are not user-facing labels and do not have safe,
  universal semantics. Keep undocumented values behind the advanced firmware-sensors option unless a role is
  verified across hardware. Never present an unknown raw key as “CPU” merely because its value looks plausible.
- Discover fans from `FNum` and read current/minimum/maximum speed only. Fan control remains out of scope.
- Whole-system and charger power keys were present during testing, but their names and availability are runtime
  observations, not portable identifiers.

### GPU telemetry

- `IOAccelerator` services publish live `PerformanceStatistics` dictionaries on macOS 27. Enumerate services and
  validate keys for device, renderer, tiler, and memory metrics without assuming a vendor or model.
- IOReport may provide GPU frequency, activity, temperature, and power. Read-only SMC temperature is a fallback.
- Reject invalid utilization and temperature values independently so one missing field does not disable the module.

### Battery telemetry

- IOPS provides the best normalized percentage and power state, but does not expose all detailed health, electrical,
  thermal, cycle, condition, and adapter fields.
- `AppleSmartBattery` and `AppleSmartBatteryPack` IORegistry properties supply optional details, but fields vary by
  hardware and OS. Merge IOPS with IORegistry and degrade each field independently.
- Signed current may be published through an unsigned integer representation; normalize it before calculating power.
- On macOS 27, the public power-source summary did not publish its formerly documented health string even though the
  registry exposed design capacity, full-charge capacity, and a zero permanent-failure status. Prefer Apple's
  explicit condition/failure values, normalize Good/Fair/Poor, then use the 80% maximum-capacity service threshold.
- A Mac can be connected to AC without actively charging. Do not convert missing time remaining into zero minutes.
  Duration estimates proved unstable and were removed from Barometer's product UI.
- Do not blame AlDente or another battery utility without evidence. Unavailable telemetry must remain unavailable.

### Network and process ownership

- macOS's cumulative per-process external-network accounting can produce rates without root or a bundled helper.
- Process names often identify nested executables such as Discord Helper or Spotify Helper. Resolve the outermost
  owning `.app` bundle to obtain the human application name and color icon.
- CoreWLAN metadata and per-process accounting are substantially more expensive than interface byte counters. Cache
  metadata and refresh process details less often than the lightweight menu bar rate.

## Performance behavior

Private hardware sources are expensive enough to dominate Barometer when sampled every second. Preserve these
separations:

- headline CPU, memory, GPU utilization, and network counters may update quickly;
- CPU and memory process lists, Network process accounting, GPU detail, SMC, IOHID, IOReport, and Wi-Fi metadata use
  slower bounded refreshes or caches;
- Sensors enforce at least a five-second interval;
- availability is confirmed once per running scheduler rather than reprobed every cycle;
- disabled modules pause their schedulers;
- a module hidden because it belongs to Combined still samples if Combined needs it;
- display sleep pauses work and wake resumes only required schedulers.

After these changes, a warmed 15-sample run with CPU, GPU, Memory, Network, Sensors, and Weather enabled averaged
3.75% CPU on the test Mac, compared with an earlier 7–9% steady range. Treat this as a regression reference, not a
universal performance guarantee.

## Permissions, signing, and distribution

- Ad hoc development signatures can reset TCC grants. Location and Calendar paths must tolerate missing permission
  and saved-data fallback.
- Hardened-runtime builds must contain both `com.apple.security.personal-information.location` and
  `com.apple.security.personal-information.calendars`. `Scripts/make-app.sh` verifies the signed entitlements instead
  of trusting the source plist. Any later distribution re-sign must pass the entitlement file again and inspect the
  resulting application; a bare `codesign --force` strips the entitlements even though strict signature and
  Gatekeeper checks can still pass.
- A direct Location request must activate the LSUIElement application before calling
  `requestWhenInUseAuthorization()`. Keep current-location callbacks registered at launch when the saved setting is
  on, but never initiate an undetermined permission request until the user selects **Use current location** or
  **Allow Location**.
- CoreWLAN returning a nil SSID does not prove Location access is denied. Retain Barometer's shared
  `CLLocationManager` whenever Network is active, inspect its authorization state, and invalidate the cached Wi-Fi
  sample after authorization changes. Never display a permission-required message when Core Location already reports
  authorized; offer a retry and report the network name as unavailable instead.
- Never request a new TCC category during launch or background sampling. Permission requests must follow a direct
  user action and require project approval before implementation.
- `LSUIElement` keeps Barometer out of the Dock; it does not replace correct bundle identity or signing.
- `make app` and `make install` use `CODESIGN_IDENTITY` when supplied, otherwise the first valid Developer ID
  Application identity in the login keychain, and fall back to an ad-hoc signature only when neither exists.
- On macOS 26 and 27, repeated ad-hoc rebuilds can leave Barometer running while the Menu Bar privacy control
  suppresses every status item. A stable Developer ID team identity prevents the rebuilt app from appearing to be a
  different unsigned application. Strict signature verification alone does not detect this failure.
- Developer ID signing, hardened runtime, and timestamping are not notarization. The release workflow separately
  supports a signed DMG and optional notarization.
- GitHub release workflows are manual-dispatch only. Notarization remains off unless David explicitly enables it;
  do not submit a build merely because the workflow supports the path.

## Swift 6.4 toolchain and hardening rules

- `make` selects `/Applications/Xcode-beta.app/Contents/Developer` locally when `DEVELOPER_DIR` is not already set.
  GitHub uses the dedicated `xcode-27` runner and `/Applications/Xcode.app/Contents/Developer`.
- Continue to use SwiftPM only. The Xcode application supplies the Swift 6.4 command-line toolchain and SDK; it does
  not authorize an Xcode project or `xcodebuild`.
- Xcode bundles place `Testing.framework` under the macOS platform directory, while standalone Command Line Tools
  place it under the developer directory. `Package.swift` resolves both layouts; do not hard-code the obsolete path.
- SwiftUI's `@Entry` macro is not usable with the older standalone Command Line Tools installation because that
  bundle lacks the `SwiftUIMacros` plug-in. The manually declared `EnvironmentKey` remains intentional.
- SwiftUI environment values must not store closures. Inject one stable reference-type action object and keep its
  owner weak to avoid invalidation churn and retain cycles.
- The updater must derive the running Barometer process's designated requirement through the Security framework and
  evaluate it against an update, not merely accept any valid code signature. Never hard-code or record a certificate
  or signing-team identifier in source, tests, documentation, settings, logs, or release notes.
- `CSystemSources` retains the warning policy in `Package.swift`, and CI runs `make security-audit`. Do not suppress a
  diagnostic without a written, source-specific reason.
- C bounds safety remains deferred for the dynamic `dlopen` and `dlsym` bridge. Do not add unsafe pointer annotations
  solely to make `-fbounds-safety` compile.
- Always run both `make test` and `swift build -c release`; debug success has previously missed optimizer and macro
  plug-in failures.

## macOS update regression checklist

After every macOS 27 beta or Command Line Tools update:

1. Run `swift test` and `swift build -c release`, recording the silent-runner caveat if it remains.
2. Run `make app`, verify exactly one executable, and run strict `codesign` verification.
3. Run `make install`; never use the `dist/` copy for placement conclusions.
4. Inspect `~/Library/Logs/Barometer/identity.json` for fixed bundle, autosave, AX, image, length, and frame invariants.
5. Relaunch Barometer repeatedly and confirm the identity set does not change.
6. Ask David to restart Bartender or exercise Thaw. Confirm items retain independent positions without Barometer
   changing manager state.
7. Toggle modules and Combined membership. Confirm items hide rather than disappear and inactive visibility defaults
   do not collide with active identities.
8. Let live values cross digit, unit, condition-glyph, and unavailable/live boundaries. Confirm no neighbor moves.
9. Run the CPU, GPU, Sensors, Battery, Network, frequency, power, fan, and temperature probes. Record missing private
   sources as unavailable; never patch around an OS change with invented constants.
10. Take a short warmed CPU sample with the normal enabled-module set and compare it with the 3.75% reference.

## Scope boundary

Not every bug found while running macOS 27 is an operating-system behavior. For example, Open-Meteo's automatic
best-match current conditions were fresh but inaccurate at one location; the multi-model current consensus fixed a
weather-provider issue, not a MenuBarAgent cache. Diagnose the app, provider, operating system, and menu bar manager
as separate layers before assigning a cause.
