# Barometer 1.0.4

Barometer 1.0.4 makes the built-in updater faster, clearer, and more reliable.

## A better update experience

- Release notes now appear with formatted headings, paragraphs, lists, links, emphasis, and code.
- Two-finger scrolling remains responsive and returns to normal CPU use immediately after scrolling stops.
- The update window now follows Barometer's visual design and keeps its content clear at every supported window size.
- A new **View Release on GitHub** button opens the release page, where the update and its downloads can be inspected
  directly.
- The window clearly explains that automatic updates are downloaded from GitHub, verified, installed in Applications,
  and reopened.

## Reliable version information

- Release builds receive their version directly from the requested GitHub Actions release.
- Packaging stops if the application version and disk-image version do not match.
- GitHub Actions verifies the finished application's version before creating the disk image.
- Weather requests identify the installed Barometer version instead of using an old development version.

## Compatibility

- Existing settings, permissions, and menu bar positions are preserved.
- Barometer remains a single application with no helper or privileged process.
- Barometer 1.0.4 is distributed as a notarized, stapled DMG for Apple silicon Macs running macOS 26 or later.
