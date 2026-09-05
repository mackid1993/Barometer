# Barometer 1.0.2

1.0.2 ended up being a pretty big update. Weather got the biggest change, but there is also real CPU and GPU
history now, an updater, better sampling controls, and a long list of fixes for memory use, CPU use, dropdowns,
Calendar access, and menu bar managers.

## Weather

You can hover over any day in the 10-day forecast and get a full forecast for that day. It opens beside the main
Weather panel, it scrolls, and it goes away after you move off both the day and the detail panel. You do not have to
click anything.

The information most likely to affect your day is near the top. That includes the high and low, feels-like
temperatures, precipitation chance and amount, rain, snow, sunshine, humidity, dew point, wind, gusts, visibility,
pressure, and UV index.

There is a lot more detail farther down:

- Sunrise, sunset, and total daylight
- Moon phase, illumination, moonrise, and moonset
- Hour-by-hour temperature and precipitation charts
- Hourly cards that glow when you hover over them and show the full reading for that hour
- Cloud cover at different levels, wet-bulb temperature, freezing level, and CAPE
- Sunshine, solar radiation, direct radiation, diffuse radiation, and direct normal irradiance
- Snow depth, soil temperature, soil moisture at several depths, and evapotranspiration

The hourly section was condensed so it does not turn into one enormous vertical list. The cards scroll sideways,
and hovering over one updates the full hourly detail below it. The cards are not buttons and do nothing when clicked.

Weather Settings has an **All details** option and a **Custom** option. Custom lets you turn whole sections on or off,
including the extra groups inside the hourly view. Switching back to All details does not erase your custom setup.

Older cached forecasts still work. If Open-Meteo does not return a value, Barometer shows it as unavailable instead
of making one up.

## CPU and GPU history

CPU and GPU both have 1-minute, 5-minute, 30-minute, 3-hour, and 24-hour views now. The points keep their real place
in time. If Barometer has only been running for ten minutes, the 24-hour graph shows those ten minutes at the end of
the graph instead of stretching them across the whole day.

Barometer saves up to 24 hours of compact CPU and GPU graph data. That history survives normal restarts and app
updates. It only shows samples Barometer actually collected.

The CPU range controls work properly inside the panel now, and GPU has the same controls for consistency.

## Sampling controls

The default sampling interval for CPU, Memory, GPU, Network, and Disks is now three seconds. General Settings has a
global sampling override, and the individual module settings are still there. There is also a note explaining that
lower intervals use more CPU.

**Reduce sampling on battery** is still available. Sensors also limits hardware reads to the sensors used by visible
menu bar items and stacks. Opening the full Sensors panel temporarily enables the full sensor list, then it drops back
down after the panel closes.

CPU, Memory, and Network do not scan processes unless you have a related detail panel open. GPU and Network also skip
their more expensive extra details while their panels are closed.

## Updates

There is now a **Check for Updates…** button in About. Automatic checks happen quietly after launch, and you can turn
them off or back on from the same page.

When an update is available, you can install it, wait until later, or skip that version. Barometer downloads the DMG
from the project's GitHub release and checks GitHub's SHA-256 digest. It also checks the app identifier, executable,
symlinks, and code signature before replacing anything.

The updater stages the new copy in Applications, keeps a rollback copy while it swaps the app, and relaunches
Barometer when it is done.

## Bugs fixed

- **Allow Calendar Access** actually requests access now. This works from Settings and from the Time dropdown. The app
  bundle also has the Calendar entitlement and permission description it needs.
- The Network interface picker works again. You can choose Automatic, a physical interface, or a VPN interface from
  the picker inside the Network panel.
- Dropdowns stay open while your pointer is over the menu bar item or the dropdown itself. They close one second after
  you leave both. Clicking somewhere else still closes them immediately.
- Opening another Barometer dropdown closes the previous one. Old panels are not left around in the background.
- Weather day details close when you move to another part of the Weather panel.
- Fast scrolling through the forecast no longer opens random days just because they passed under the pointer.
- Scrolling inside a day detail no longer closes it.
- Popovers are kept inside the visible part of the correct display, including displays positioned to the left or below
  the main display.
- Weather no longer opens a draggable separate window or leaves a halo behind after closing.
- The CPU and GPU long-range graphs no longer show the same stretched line for every range.
- The little hourly Weather cards glow on hover but do not pretend to be clickable controls.

## Menu bar managers

Barometer keeps its status item identifiers and visibility stable while Thaw, Bartender, or another menu bar manager
is working with them. It also gives you enough time to move from a mirrored menu bar item into the real dropdown.

There was also a less obvious problem where a menu bar manager could inspect a closed Barometer menu through
Accessibility. AppKit made that look like a real menu open. Barometer would build hidden SwiftUI views and start
polling even though nothing was on screen. That inspection path is ignored now. A real menu click still opens as
usual.

## Memory and CPU use

A few different problems were contributing to the high memory reports:

- Graph history used to preallocate and retain much larger samples than the graphs needed. History now stores small
  graph-specific values and grows as samples arrive.
- SwiftUI Canvas graphs could leave more than 160 MiB of rendering data behind after a panel closed. The graphs now
  use shape paths while keeping the same lines, fills, markers, card shapes, and glow.
- Weather, Combined, Network, CPU, and Settings release their SwiftUI content after closing.
- Attached panels no longer run an unnecessary half-second redraw loop.
- Closed menus do not build hidden views when Accessibility tools inspect them.
- Process names, process icons, and date formatters use bounded caches.
- Network resolves interface names in one pass instead of repeatedly asking the system for the same list.
- Sensor, GPU, Network, and process details are collected only when something visible needs them.
- Numeric updates no longer trigger pointless implicit animations. Hover effects and the existing visual design are
  unchanged.

The compact history benchmark uses about 93% less memory than the old version and stops growing after its 24-hour
window is full. The final local build averaged 0.61% CPU over a settled 41-second run with every panel closed. After
opening and closing Sensors, it measured 24.0 MiB current and 37.2 MiB peak physical memory with no leaked blocks.
Those numbers will vary depending on your hardware, enabled items, sampling interval, and which panel is open.

## Testing and build changes

The test suite is up to 242 tests. It covers the system sources, graph history, updater, dropdown behavior, Weather
hovering and scrolling, Calendar packaging, and memory cleanup.

There are also screen tests for every changed popover at every display corner in light and dark mode. They check that
the panels stay on screen, scroll all the way to the bottom, and do not break the cards, gradients, graphs, or glow.
The repeated panel test currently peaks at 47.8 MiB and fails if it goes over 128 MiB.

Tests and the memory check run before GitHub is allowed to package, sign, notarize, or prepare a draft release. The
Build, Check, and Release workflows only run when somebody starts them manually. The Release workflow creates a draft
and never publishes it on its own.

The default branch is now `master`.

## Thanks

Thanks to [@diazdesandi](https://github.com/diazdesandi) for the memory investigation and the work in
[pull request #2](https://github.com/mackid1993/Barometer/pull/2). The application name cache and some of the UI memory
cleanup in this release came from that work.
