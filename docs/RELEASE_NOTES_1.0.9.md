# Barometer 1.0.9

Barometer 1.0.9 is about honesty. The weather mark can be the system's symbol again, and Barometer's own set now
covers every condition the system's does. Notification Center's corner can be assigned from inside Barometer.
The About pane explains every permission Barometer can ask for, shows where each one stands, and can hand them
back. And a sweep of the panels fixed a dozen things that were drawn wrong, one of which made a chip's label
almost invisible in Light Mode.

## Choose your weather icon

- **Weather icon** in Weather settings offers **Barometer's own** or **System symbols**. The system symbol sits
  beside the temperature the way Barometer showed it at launch; Barometer's own mark draws the condition around
  the digits and takes less room in the bar.
- Barometer's marks now cover **fourteen conditions** rather than eight, matching the system symbols one for one:
  partly cloudy at night, drizzle, heavy rain, sleet, thunder without rain, and an unknown mark join the set. One
  switch decides which condition a reading is, so the two styles can never disagree.
- The settings preview shows **every** condition in whichever style is selected, so the two can be compared one
  to one before you commit. The preview strip scrolls rather than stretching the window.
- The two styles are different widths, so the choice is staged and applies when Barometer reopens, the same as
  the clock's format and the menu bar text size.
- **Color weather icons** now appears only under Barometer's own mark. System symbols follow the menu bar's own
  color, so the option meant nothing there.
- With no forecast yet, the system style draws the dash and degree sign alone. It used to draw a sun, which was a
  reading the weather never gave.

## Notification Center without the trip to System Settings

- Time and Notifications settings now has a **corner picker** listing all four corners, top right first. Choose
  the one you want, press the button, and Barometer assigns it. The Dock restarts once, which the button, the
  text beside it, and the confirmation all say before it happens.
- A corner opens Notification Center whenever the pointer reaches it. macOS stores a modifier alongside a
  corner's action but does not act on it, so there is no way to make a corner answer only to Barometer — pick
  one your pointer does not travel to.
- Barometer never takes a corner you are already using, and **Give the Corner Back** restores exactly what was
  there.
- Clicking a notification now opens Notification Center instead of following the notification's own link. Those
  links did not lead where the notification said — a chat message opened the app rather than the conversation —
  so Barometer's list is a preview of what is waiting, and the panel is where you act.
- The dropdown's button says **No Hot Corner Assigned** when there is none, instead of offering to open a panel
  it cannot open, and takes you to the setting that fixes it.

## Every permission, explained

- The About pane now lists **Full Disk Access, Accessibility, Calendars, and Location**, what each one buys, and
  where it stands. Nothing is requested at launch: a permission is asked for by the feature that needs it.
- Each row has its own button, and it says what it will do. macOS only prompts for a permission it has never
  asked about, so a permission you have already refused opens the right list instead of pretending to ask again.
- **Reset All Permissions** hands them back. It names any macOS refused, and it does not claim to reset
  Location: macOS keeps that one in Location Services, where only you can switch it off, so Location has its own
  button to that list whether it is granted or not.
- A note says plainly that Full Disk Access and Calendars only show a change after Barometer is reopened, and
  that Accessibility and Location update as they are changed. **Quit and Reopen Barometer** is offered rather
  than described.
- Barometer no longer reads Notification Center's interface. It used to walk that window on every refresh to
  keep hold of each row's controls; nothing used them once clearing was removed, so it is gone. Accessibility is
  now used for two things only, both when you press a button.

## Every pane previews its own item

- GPU, Battery, Sensors, and Time had no live preview at all. All four have one now, drawn by the same renderer
  the real menu bar item uses, so it follows the mode and the options you pick rather than being a fixed
  picture.
- A custom graph or fill color now shows in the preview. Every pane was drawing graphs in the normal color.

## Drawn properly

- The **Memory** breakdown bar no longer runs past its card. Cached memory sits inside free memory, so drawing
  both made the bar a fifth wider than the space it had; the tail is now the memory free beyond the file cache,
  and the used part ends exactly at the percentage above it.
- Every card sat slightly left of centre wherever macOS reserves room for a scroll bar. They are centred now.
- A chip with a symbol drew its label in the chip's own color on a wash of that same color, which in Light Mode
  was as faint as 1.28 against 1. Labels now use the text color; the chip keeps its color.
- A module icon's glyph takes white or near-black by the color it sits on. On the neon theme it was invisible.
- Monochrome previews were drawn in the window's own ink, which in Light Mode meant black on the preview's dark
  strip. They are drawn for the strip they sit on now.
- Per-process network rates no longer stay dimmed, notification ages no longer vanish under the pointer, volume
  and interface pickers no longer go blank when the selection is hidden, the fixed graph maximum follows the rate
  unit you chose, a long calendar name gives way to the event title, interface byte counts shorten instead of
  pushing chips out of the card, a stack's module tabs scroll instead of wrapping, Now Playing is tall enough for
  its failure line, and the update window's main button no longer shrinks before the link beside it.
