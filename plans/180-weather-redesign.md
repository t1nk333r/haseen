# Plan 180: the weather panel redesigned, with an hourly and a curve tab

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW. One plugin's panel, model and bar text. The service keeps
  its sources, timers and retries; one more Open-Meteo day is asked for.
- **Depends on**: 022 (the weather plugin), 052 (the Omarchy port), 109
  (Arabic and mirroring), 141 (type roles), 164 (the compact panel it
  replaces), 179 (wttr.in's icon as fallback)
- **Category**: shell
- **Planned at**: 2026-11-21, from the owner
- **State**: DONE 2026-11-21 (`tests/test-weather.sh` 112/112 after the
  review below; the real panel
  rendered from the live service at scale 1 and 1.25 and in Arabic;
  luna's and IO's panels are the owner's check)

## Problem and choices

The owner, 2026-11-21: "redisgn the weather pluginm". The panel was plan
164's compact card, which is still Omarchy's layout
(`/usr/share/omarchy/shell/plugins/panels/weather/Panel.qml`, Omarchy
4.5.0-3: hero, feels/wind/humidity, three days).

Asked to choose a design from text sketches, the owner answered "real
mockups not text ones" and, for the bar, "Icon + temperature". Three
designs were then rendered in Quickshell with haseen's `PanelSurface`,
the owner's theme and font, and live data for their city: A (glance,
hourly strip, five days with range bars), B (a 24-hour temperature curve,
three days) and C (a tidier compact card). The owner chose "A + B tabbed".
A rendered mockup of that, both tabs at 400 × 345 px, was answered "go".

## Decision

`share/haseen/shell/plugins/haseen.weather/`:

- **Hero.** The condition icon (accent) and the temperature at `display`
  (24 px; plan 164 had `iconLarge` and `heading`), the condition in words
  and today's high and low beside them, the location at the row's end in
  `caption`. Hovering the location shows where the data comes from and
  when it was fetched (`PanelToolTip`). This replaces plan 164's footer
  line.
- **Stats line.** Unchanged (feels, wind, humidity), and still the place of
  the city search while it is open. The tabs stay visible during a search,
  so the panel does not collapse.
- **Tabs.** A bordered segmented control, the selected segment filled
  with the accent: "Hourly · 5 days" and "Curve · 3 days" (plural forms,
  counting the days there are). Click, Tab and Shift+Tab, or the arrows
  (which point at the tab they select, also mirrored, and stop at the end;
  `tabForKey`) switch. The service
  keeps the last tab (`panelTab`) for as long as the shell runs. The body
  is as tall as the taller tab, so switching never resizes the panel.
  - Tab 1: "Now" (the current icon and temperature), then the next seven
    three-hourly forecasts. Then the five days as rows: name, icon, low, a
    range bar on the days' shared scale (`Model.daysScale`,
    `Model.rangeBar`), high.
  - Tab 2: the same eight points as a temperature curve (`Model.curve`:
    Catmull-Rom through slot centres, as cubic Béziers, drawn by a
    `Shape` with an accent stroke and a fading fill). Temperatures above,
    icons and hours below. Then three days in columns. The curve is a
    timeline and reads left to right in every language. Everything else
    mirrors.
  - Without hours to show (wttr.in failed while Open-Meteo answered, so
    only "Now" is there, or a temperature is missing), both tabs say "No
    hourly forecast" where the strip or the curve would be.
- **Model** (`Model.js`):
  - `hourlySlots`: wttr.in's hourly forecasts after this machine's clock,
    night icons from the hour's symbol (plan 179's `wttrIsNight`).
  - `todayRange`: Open-Meteo's first day when it is today, else wttr.in's.
  - `conditionForCode` and `currentCondition`: wttr.in codes in the icons'
    groups, with rain split into light and heavier, as eleven marked
    strings translated in the panel.
    Open-Meteo codes go through `wttrCodeForOpenMeteo`, which
    `iconForOpenMeteoCode` now uses too.
  - `FORECAST_DAYS = 5`: Open-Meteo is asked for `forecast_days=6` (today
    and five), and wttr.in's fallback lists its days up to five (it has
    two).
- **Service.** `hours`, `todayRange`, `condition` and `panelTab`. The
  condition comes from the same source as the icon (Open-Meteo once it
  gave the icon), so the words never contradict it. The first live render
  had a sun icon over "Partly cloudy" from wttr.in.
- **Bar pill.** The temperature beside the icon (`26°`), on by default,
  `settings.temperature: false` for the icon alone. Plan 164 had rejected
  this. The owner chose it here.
- **Strings.** Eighteen new interface strings, with Arabic translations.
  The high and low line isolates each number with its degree sign
  (U+2066/U+2069) in Arabic, which otherwise put the sign on the wrong
  side.
- Manifest 2.1.0. `service` in `Panel.qml` and `Widget.qml` is a plain
  property with the same default binding, so a test can hand them a
  service.

## Rejected

- **Designs B or C alone**, and **text sketches** (the owner's answers
  above).
- **Omarchy's `ButtonGroup` chips** (`qs.Ui`) for the tabs: separate
  bordered buttons, not the joined control in the approved mockup.
- **Open-Meteo's hourly data** for the hours: the extra fields would grow
  the request that luna is refused (plan 179). wttr.in's three-hourly
  forecast is already fetched.
- **Keeping the tab across shell restarts**: a config write for every tab
  click. The service keeps it while the shell runs.
- **Wind and humidity per hour**: more columns than 28 em holds at
  `caption`.

## Limitations

- wttr.in gives each day's hours in the forecast place's time. They are
  compared with this machine's clock, so a location in another time zone
  starts its hours at the wrong slot.
- Without Open-Meteo, the first tab lists wttr.in's two future days, and
  its label says so ("Hourly · 2 days").
- Without wttr.in there are no hours, only the note, and the label still
  counts the days.

## Review

A Sonnet subagent reviewed `f08d735` (the owner, 2026-11-21: "sonnet
reviewer over deepseek"): REQUEST_CHANGES, one blocker. Every finding was
taken:

1. **Blocker:** with saved coordinates and wttr.in failing, the curve tab
   was blank and "Now" spanned the hourly strip. Now `hasHours` gates both,
   with the note above. A scenario with wttr.in refused checks it (only
   "Now", no curve, Open-Meteo's three days).
2. The "same height" check compared one fixed height with itself and
   passed whichever tab set it (the reviewer's mutation). Now it checks
   that the body is at least as tall as each tab (`bodyHeight`,
   `hoursTabHeight`, `curveTabHeight`).
3. Keys, mirroring and units were untested (three mutations at once still
   passed). Key handling moved into `tabForKey` and is checked on both
   tabs, mirrored and not. A forecast slot's unit is checked in Celsius
   and in Fahrenheit.
4. The pill was tested by grepping its source. Now the real `Widget.qml`
   is built on the service: `19°` (`66°` in Fahrenheit), no text with
   `temperature: false` (the icon stays), nothing without a service.
5. Code 179 ("patchy snow possible") read "Sleet" beside a snow icon. It
   is "Snow", and the plan no longer says the words follow the icons
   exactly.
6. The arrows wrapped from the last tab to the first. They stop at the end.
7. A short range near the scale's end could overhang the track. Its width
   is clamped to the track.
8. A missing temperature dropped one point and shifted every label off
   its slot. `Model.curve` now returns no curve unless every value is a
   number.
9. The warmest label sat above the item at a small `Theme.gap`, and the
   curve's control points could overshoot its band. The label room is
   `caption × 1.4 + 6` px, independent of the gap, and the control points
   are clamped to the band.
10. This section and the Limitations line above.

The reviewer's four escaped mutations (body height from one tab, imperial
slots swapped, Tab a no-op, mirrored arrows inverted) now fail 1, 2, 2 and
4 checks.

## Verification

- `tests/test-weather.sh` (112/112):
  - 21 new Model units (hours across midnight and at the hour, night
    icons, today's range from either source, conditions, the scale and a
    bar, the curve's points and paths, no curve with a missing value,
    control points inside the band, five days, the URL);
  - the service, live in Quickshell: seven hours, the condition and
    Open-Meteo's high and low, and with Open-Meteo refused, wttr.in's;
  - the real `Panel.qml` created on that service: "Now" first, eight
    slots, eight curve points, the days' scale, the first tab, the body at
    least as tall as each tab, the slots' unit, the keys (above), and
    without wttr.in only "Now" and no curve;
  - the real `Widget.qml`: the temperature, the setting and no service.
- Rendered, not committed: a scratch Quickshell harness creates the real
  service (live data for the owner's city, Open-Meteo answering) and the
  real panel in a `PanelSurface`, offscreen on the software renderer, and
  grabs both tabs: 400 × 343 px at scale 1, 500 × 429 at
  `QT_SCALE_FACTOR=1.25` (IO's scale; the curve and bars correct), and
  mirrored with the interface in Arabic (every string translated, the
  hours and bars right to left, the curve left to right).
