# Notification and system-control test build

This is an experimental build for David's installed-app check. The latest changes have been release-built;
David requested no repeat test suite or memory verification. Earlier test results do not validate these changes.

Current limits: exact native notification actions require an exposed individual row in the open macOS Notification
Center. Automatic opening and end-to-end clearing remain unresolved. Now Playing metadata reads return an explicit
permission error on this macOS build. This is not yet a complete Notification Center replacement.

## Install and enable

Quit the installed Barometer, replace `/Applications/Barometer.app` with the signed app from the test archive, then
launch that installed copy. Keep the existing application identity and installation path for macOS permissions and
menu bar placement. Do not test menu bar behavior from the repository's `dist` directory.

In Time and Notifications settings, turn on the notifications list. Barometer needs Full Disk Access to read it and existing
Accessibility access to attempt the native actions. Enable Focus and Enable Now Playing are separate switches,
off by default; select Apply Changes after changing them. They do not change the Hide the system clock setting.
Focus appears only while the reported system Focus state is active. Now Playing defaults to When Playing;
select Always to retain it during pauses or unavailable playback information. These choices do not repair denied
system API access. Notification settings now shows the Accessibility grant and offers an explicit Allow
Accessibility button. Full Disk Access reads the list; Accessibility permits native action attempts.

## Check notifications

1. Compare the notifications in macOS and Barometer. Expand Barometer's app groups to inspect their complete lists.
   The former 100-record and 30-row caps are gone. Notifications hidden locally by earlier builds reappear because
   the system's delivered list is now authoritative.
2. Use disposable notifications from at least two applications. Click one in Barometer and compare its destination
   with the normal Notification Center action. Include a Vivaldi download and a notification with an app-specific
   destination such as a conversation or document.
3. Clear one disposable notification in Barometer and verify it disappears from macOS. Check an app-group clear
   and Clear All when the remaining listed notifications are disposable.
4. Clear a notification in macOS and verify Barometer updates while open, and after closing and reopening its
   dropdown. New notifications arriving after a clear begins must remain.

Native actions use an exact notification UUID and an action advertised by its live Accessibility element. They
cannot yet be assumed to work while Notification Center is closed, or on a build that does not expose those
identifiers. The bridge refuses missing, ambiguous, incomplete, and timed-out matches. An unavailable click can
fall back to a known link, Downloads item, system destination, or app; a failed native attempt does not retry via
another destination. A failed clear keeps the notification and reports an error. There is no local-hide fallback
and no direct database deletion.

The follow-up reader accepts empty SQL NULL application lists and retains rows with unreadable previews. Failed
reads keep the last usable records and retry while open. macOS-disabled applications remain excluded from retained
rows too. If visibility preferences cannot be checked, cached records stay in memory but are withheld from display
until exclusions can be checked again. A successful complete read reconciles removals. The live database confirmed 24 SQL NULL application lists; these are now accepted as empty lists.

Report the application, expected destination, actual destination, and any visible error. No notification text or
private message content is needed.

## Check the replacements and credits

- Enable Focus, apply, and compare with Control Center. The icon is a purple moon only while any Focus mode is on;
  there is no Focus popup. Change modes through Control Center. The read-only database parser was checked against
  actual inactive and active assertion schemas and enumerates custom mode configurations across all partitions.
- Enable Now Playing and select Always to inspect the enlarged icon. When Playing hides the icon when playback
  cannot be established. Local MediaRemote requests explicitly returned Operation not permitted, so metadata and
  transport behavior are not claimed working. No Spotify-specific integration or permission bypass was added.
- Enable Show seconds in dropdown clock and check the colorful header; menu bar seconds remain independent.
- Open About and confirm the Thaw contributors wrap without truncation.
- If a menu bar manager hides the system clock, leave Barometer's Hide the system clock off, as the settings note says.

These changes do not modify Thaw or Claude's clock-hiding implementation.
