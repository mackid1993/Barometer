# Barometer 1.0.6

Barometer 1.0.6 fixes the Time calendar's missing and shifting rows, then adds navigation and daily event browsing.

## Fixed calendar rows

- Fixed the bug that could hide weekday headings or the first row of dates in some months.
- Every month now reserves six week rows, so the calendar and the content below it stay in place while browsing.
- The selected date and today's date remain visually distinct.

## Calendar navigation

- Use the left and right arrows to move between months.
- Select the month heading to choose from all 12 months in that year.
- Select the year heading to choose a year from the current decade.
- The same arrows move by year or decade while those views are open.
- A Today button returns to the current month and date.
- Trackpad and mouse-wheel gestures scroll the Time dropdown instead of unexpectedly changing the calendar month.

## Events for a selected date

- Select a date to display the Calendar events scheduled for that day.
- Upcoming events remain visible below the selected day's events.
- An event shown for the selected day is not repeated in the upcoming list.
- Event rows now include the weekday, date, and time. All-day events are labeled clearly.
- Selecting dates quickly cannot allow an older Calendar response to replace the latest selection.

## Thanks

Thank you to [@aj-salafee](https://github.com/aj-salafee) for reporting the missing calendar rows in
[issue #3](https://github.com/mackid1993/Barometer/issues/3).

Barometer 1.0.6 is a notarized, stapled DMG for Apple silicon Macs running macOS 26 or later.
