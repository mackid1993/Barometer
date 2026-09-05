# Barometer 1.0.3

1.0.3 is a focused performance, security, and reliability update. It keeps the same settings, menu bar layout,
permissions, and macOS 26 minimum requirement as 1.0.2.

## Lower CPU use

Weather detail presentation no longer causes unnecessary view updates after its panel closes. Together with the
Swift 6.4 build, this reduces background work while Barometer is sitting in the menu bar.

On the test Mac, a settled 30-second run with every panel closed averaged 0.89% CPU, including brief sampling spikes.
Actual use varies with the enabled widgets, sampling interval, hardware sensors, and open panels.

## Safer updates

The built-in updater now matches a downloaded app against the signing identity of the Barometer copy that is already
running. A correctly formed signature from an unrelated app is no longer enough to pass installation checks.

Release download addresses are also checked component by component. Barometer requires HTTPS, the exact GitHub host,
and the expected project release path, and rejects altered addresses containing user information, unexpected ports,
queries, fragments, or lookalike paths.

These checks happen in addition to the existing SHA-256 digest, bundle identifier, executable, symbolic-link, disk
image, and strict signature checks.

## Build and reliability improvements

- Barometer now builds with Swift 6.4 and the macOS 27 SDK while continuing to support macOS 26.
- The C system bridge uses automatic stack initialization and a stricter compiler warning policy.
- Security diagnostics now run before the test suite and before a release can be packaged.
- The complete suite contains 252 tests covering system readings, menu bar stability, panels, Weather, permissions,
  settings, packaging, and the updater.
- Release builds remain warning-free, and the repeated panel benchmark stays below its memory limit.

## What has not changed

- No new permissions are requested.
- Existing settings and menu bar positions are preserved.
- Barometer remains one application with no helper process or privileged component.
- The release is still a notarized, stapled DMG for Apple silicon Macs running macOS 26 or later.
