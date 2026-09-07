# Notification and system-control test build

This is an experimental build for David's installed-app check. Automated tests cover the application behavior;
native notification dispatch, Focus service access, and active media control are not yet verified end to end.
The shell probes were denied Accessibility and Notification Center database access. David chose to test Barometer
instead of granting Codex those permissions, then authorized building and replacing the installed application.

## Install and enable

Quit the installed Barometer, replace `/Applications/Barometer.app` with the signed app from the test archive, then
launch that installed copy. Keep the existing application identity and installation path for macOS permissions and
menu bar placement. Do not test menu bar behavior from the repository's `dist` directory.

In Time settings, turn on the notifications list. Barometer needs Full Disk Access to read it and existing
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
until exclusions can be checked again. A successful complete read reconciles removals. The installed failure log
identified delivered-list validation, but the live NULL/type hypothesis still needs this corrected build's result.

Report the application, expected destination, actual destination, and any visible error. No notification text or
private message content is needed.

## Check the replacements and credits

- Toggle Focus and Now Playing independently, apply, and confirm each pill appears or disappears while the clock
  setting stays unchanged. Verify placement survives a relaunch.
- Compare Focus with Control Center, select another mode, then turn it off. The private Focus service rejected
  unsigned shell probes; the installed app may also report unavailable. Public Focus status only supplies generic
  on/off when already authorized, and does not grant mode control.
- Start known playback, open Now Playing, and try previous, play/pause, and next. Check track, artist, and player
  identity. Try Spotify and another application that appears in Apple's Now Playing controls: the implementation
  uses Apple's system-wide MediaRemote API and has no Spotify-specific integration. Standalone probes returned nil
  metadata and no player. Native MediaRemote calls have been reported to return empty data to third-party callers
  since macOS 15.4, including during playback; this implementation may remain unavailable on macOS 27. An empty
  response is reported as unavailable information, never as proof that nothing is playing. The public Now Playing
  framework publishes a caller's sessions and does not provide a replacement for reading another app's session.
- Open About and confirm the Thaw contributors wrap without truncation.

These changes do not modify Thaw or Claude's clock-hiding implementation.

Media access references: [native caller investigation](https://github.com/kernoeb/mac-now-playing/blob/main/Sources/MacNowPlaying/NowPlaying.swift)
and [Apple's Now Playing framework](https://developer.apple.com/documentation/nowplaying).
