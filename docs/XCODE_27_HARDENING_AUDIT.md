# Xcode 27 hardening audit

Status: completed 2026-09-05 against Swift 6.4 and the macOS 27.0 SDK.

This audit applies Apple's Xcode 27 security and SwiftUI review guidance to Barometer's SwiftPM architecture. It
covers 160 Swift source files, the one-file C bridge, application packaging, CI, update installation, privacy
permissions, and the menu bar UI. Barometer intentionally has no Xcode project, helper, extension, or third-party
dependency, so project-only recommendations are recorded rather than imitated with undocumented flags.

## Resolved findings

### High: updates accepted any internally valid signer

The updater already required an exact DMG name, GitHub's SHA-256 digest, a bounded download, a safe bundle structure,
the `com.barometer.app` identifier, no symbolic links, and a strict code-signature check. A strict signature check by
itself only proves that the nested code is internally consistent; it does not prove that the code was signed by
Barometer's developer.

The installer now derives the current process's designated requirement through Apple's Security framework immediately
before scheduling an update. It then evaluates that requirement against both the mounted application and the copied
replacement. No certificate or team identifier is stored in source, tests, documentation, or settings. Tests preserve
a deliberately weaker identifier-only requirement for their ad hoc fixture while confirming that production obtains
its requirement from the running signed code.

### Medium: release URL trust used a textual prefix

The release pipeline no longer trusts an asset because its complete URL string starts with an expected phrase. It
now parses URL components and requires HTTPS, the exact `github.com` host, no user information, no explicit port, no
query or fragment, and the exact repository release path. Regression cases cover lookalike paths and malformed URLs.

### Medium: a SwiftUI environment value stored changing closures

Weather day rows previously received two closures through the SwiftUI environment. Function values cannot be
compared reliably during environment propagation, which can invalidate more of the view tree than the actual change
requires. One retained `MenuDetailActions` reference now carries both actions and weakly delegates to the dropdown
controller. The environment reference remains stable for the controller's lifetime and has a regression test.

### Medium: the C bridge lacked enforced diagnostic policy

`CSystemSources` now builds with stack variable zero initialization and Apple's relevant warning set, plus conversion,
enum-assignment, and signed-comparison diagnostics. `make security-audit` runs Clang's available security analyzers
against the bridge, and GitHub runs the audit before tests. The current bridge passes both build diagnostics and the
analyzer without suppressions.

### Medium: toolchain definitions had drifted

The package now requires Swift tools 6.4. Local Make targets select the installed Xcode 27 beta command-line toolchain,
while every GitHub build uses the dedicated `xcode-27` runner and its default `Xcode.app`. The Testing framework path
is selected correctly for both an Xcode bundle and the older standalone Command Line Tools layout. The deployment
target remains macOS 26.

## Existing controls confirmed

- Swift 6 language mode and complete strict concurrency are enabled for every Swift target.
- Every `@Observable` model is main-actor isolated, every audited `@State` property is private, and no legacy
  `ObservableObject` or `NavigationView` remains.
- Production code contains no force unwrap or `try!`. Each `@unchecked Sendable` declaration has a local ownership
  and immutability explanation.
- The app requests only Location and Calendar privacy categories. Both requests follow direct user action, both usage
  descriptions are packaged, and both entitlements are verified after every development and distribution signature.
- The hardened runtime, timestamped Developer ID signature, optional notarization, stapling, and Gatekeeper checks are
  distinct release stages. Notarization remains manual and opt-in.
- Network requests use HTTPS. Update redirects are limited to GitHub's release asset hosts and cannot downgrade to
  cleartext transport.
- The single-bundle status-item identity contract remains intact: one executable owns all items, with no helper or
  second bundle.
- Existing type erasure is concentrated at AppKit hosting boundaries rather than inside scrolling row collections.
  Dynamic rows generally use stable model identities.

## Swift 6.4 A/B comparison

The last committed source (`b84de25`) and this hardened worktree were each exported to a clean directory, built from
scratch with the same Xcode 27 Swift 6.4 compiler and macOS 27 SDK, and run through the same popover memory benchmark.

| Measurement | Baseline | Hardened | Result |
| --- | ---: | ---: | --- |
| Cold release build | 31.59 seconds | 31.57 seconds | No meaningful change |
| Compiler warnings | 0 | 0 | Clean in both builds |
| Release executable | 8,401,880 bytes | 8,383,624 bytes | 18,256 bytes smaller |
| Peak popover footprint | 50,234,400 bytes | 50,267,192 bytes | 0.07% higher; benchmark noise |

The pass is intentionally performance-neutral. Its improvements are enforceable trust boundaries and failure
detection: malformed update URLs are rejected, updates must carry Barometer's Developer ID, unsafe C changes fail the
build or analyzer, and Weather detail presentation no longer injects changing closures through the environment.

The installed Swift 6.4 build was also sampled once per second for 30 seconds after startup settled and all panels
were closed. Barometer averaged 0.887% CPU, reached a 0.0% minimum, and briefly peaked at 4.8% during sampling work.
This agrees with the lower idle average observed in Activity Monitor while preserving live readings.

## Deliberately deferred

### C bounds safety

Xcode 27's `-fbounds-safety` analysis reaches the C bridge but diagnoses the two unavoidable conversions returned by
`dlopen` and `dlsym`. Apple's adoption workflow depends on reviewed per-file rollout controls that SwiftPM does not
provide. Barometer also has no ordinary buffer arithmetic to protect: the bridge only loads an operating-system
library and resolves named functions. Do not add unsafe annotations merely to silence the compiler. Revisit this if
SwiftPM gains a supported incremental adoption mechanism or the private IOReport bridge is replaced.

### Enhanced Security and runtime restrictions

The Xcode Enhanced Security capability and its project build settings have no supported SwiftPM manifest equivalent.
Barometer also dynamically loads `/usr/lib/libIOReport.dylib` and uses read-only IOKit and Mach-backed system sources,
so enabling runtime restrictions without a dedicated compatibility exercise could disable core monitoring. Keep the
hardened runtime and minimal entitlements; evaluate additional restrictions separately on every supported OS.

### Memory Tagging Extension

The test Mac is an M4 Pro. Xcode's Memory Tagging Extension guidance targets supported M5-and-later hardware, so this
cannot be validated on the current machine and is not enabled in production.

### Remaining SwiftUI cleanup

`CombinedSettingsView` identifies metric editor rows by their array position because duplicate metrics are currently
valid. Those rows contain no local state, so reordering is correct today, but future stateful row controls should first
introduce a stable persisted row identity. Existing conditional card modifiers are static design decisions and should
not be mechanically rewritten during a hardening pass.

## Required regression gates

Run these before merging a security, toolchain, packaging, updater, or SwiftUI environment change:

```sh
make security-audit
python3 Scripts/check-source-invariants.py
make test
swift build -c release
python3 Scripts/benchmark-popover-memory.py
make app
codesign --verify --deep --strict dist/Barometer.app
```

After `make app`, confirm that `Contents/MacOS` contains only `Barometer`, the bundle identifier is
`com.barometer.app`, the signature uses the intended Developer ID identity when it is available, and the signed
Calendar and Location entitlements are both true. Never record the certificate or team identifier in the repository.
