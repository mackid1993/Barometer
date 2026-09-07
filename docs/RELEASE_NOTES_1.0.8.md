# Barometer 1.0.8

Barometer 1.0.8 lets its clock replace the macOS clock. It can remove the system clock from the menu bar, list the
notifications waiting in Notification Center inside the clock's dropdown, and open Notification Center from there.
Now Playing and Focus join the menu bar, the clock gets its own text size, and the dropdown can be arranged and
sized. Barometer is now GPL-3.0.

## The system clock can go

- **Hide the system clock** in Time and Notifications settings removes the macOS clock from the menu bar and gives
  its width back, so Barometer's clock takes its place. Control Center and everything inside it stay.
- It works the way Thaw does it. On a macOS build that cannot remove the clock, Barometer covers it instead and
  asks for Accessibility only then.
- The clock is a very particular item, so it now has its own **text size**, 9 to 14 pt, independent of the rest of
  the menu bar. It is staged with the other clock edits until Apply Changes.

## Notifications in the clock dropdown

- Turn on **Show notifications in the dropdown** and the notifications waiting in Notification Center appear under
  the calendar, grouped by app, with icons, text, and age. Banners keep arriving exactly as before.
- Apps whose notifications you turned off in System Settings stay hidden, matched to the exact setting macOS uses.
- Clicking a notification goes where Notification Center would send you: the notification's own link first, a
  finished download revealed in your file viewer, a link or file from the app's own data, the System Settings pane
  behind a system notification, and otherwise the app.
- The list is read-only. macOS gives no app a way to clear another app's notification, so an **Open Notification
  Center** button takes you to the real thing to act on or clear them. With the system clock hidden, that button
  works through a hot corner you assign to Notification Center; the settings pane has the three steps and a
  button into System Settings, and the dropdown sends you straight to them if none is assigned.
- Reading the list needs Full Disk Access, which Barometer asks for only when you turn the option on. Barometer
  never writes to Notification Center's data.

## Now Playing and Focus

- **Enable Now Playing** adds a menu bar item with the current track. Its panel shows the artwork, title, artist,
  and a progress bar, with previous, play or pause, and next, in the same style as the rest of Barometer. Long titles
  scroll. Choose When Playing or Always.
- **Enable Focus** adds a purple moon while a Focus mode is on, with a panel listing your modes.

## Arrange the clock dropdown

- Time and Notifications settings now lists the dropdown's sections, calendar, day events, notifications, world
  clocks, sun, upcoming events, with up and down buttons to put them in your order. A section with nothing to show
  stays out of the way.
- A **Height** slider sets how tall the dropdown opens, 400 to 1000 pt, never past the screen.

## Weather

- The 10-day forecast's temperature bars are now colored by the temperature itself, from violet and blue at
  cold through green and yellow to orange and red at heat, in Celsius or Fahrenheit. A mild day reads green into
  yellow and a hot one yellow into red, instead of every day getting the same cyan-to-orange sweep.

## Credits and license

- Barometer is now licensed under the GNU General Public License, version 3.
- The system clock work is adapted from Thaw, the open source menu bar manager, with the permission of its
  maintainers, Toni Förster and René (diazdesandi). Their work on macOS 27 menu bar internals also informed how
  Barometer keeps its items stable under menu bar managers. Thaw grew from Jordan Baird's Ice. Thank you.

## Notes

- Every new option is off by default. An existing installation looks the same as it did in 1.0.7 until you turn
  something on.
- Hide the system clock is meant for Barometer to own the clock. If a menu bar manager already hides it, leave
  Barometer's setting off; the Open Notification Center button works either way.

Barometer 1.0.8 is a notarized, stapled DMG for Apple silicon Macs running macOS 26 or later.
