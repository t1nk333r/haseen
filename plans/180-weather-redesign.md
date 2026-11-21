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
- **State**: DONE 2026-11-21 (`tests/test-weather.sh` 97/97; the real panel
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
  (which point at the tab they select, also mirrored) switch. The service
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
- **Model** (`Model.js`):
  - `hourlySlots`: wttr.in's hourly forecasts after this machine's clock,
    night icons from the hour's symbol (plan 179's `wttrIsNight`).
  - `todayRange`: Open-Meteo's first day when it is today, else wttr.in's.
  - `conditionForCode` and `currentCondition`: wttr.in codes grouped like
    the icons into eleven marked strings, translated in the panel.
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
- **Strings.** Seventeen new interface strings, with Arabic translations.
  The high and low line isolates each number with its degree sign
  (U+2066/U+2069) in Arabic, which otherwise put the sign on the wrong
  side.
- Manifest 2.1.0. `Panel.qml`'s `service` is a plain property with the
  same default binding, so a test can hand the panel a service.

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

## Verification

- `tests/test-weather.sh` (97/97):
  - 19 new Model units (hours across midnight and at the hour, night
    icons, today's range from either source, conditions, the scale and a
    bar, the curve's points and paths, five days, the URL);
  - the service, live in Quickshell: seven hours, the condition and
    Open-Meteo's high and low, and with Open-Meteo refused, wttr.in's;
  - the real `Panel.qml` created on that service: "Now" first, eight
    slots, eight curve points, the days' scale, the first tab, switching
    kept by the service and wrapping, and one height for both tabs;
  - the bar setting's default and the pill's binding.
- Rendered, not committed: a scratch Quickshell harness creates the real
  service (live data for the owner's city, Open-Meteo answering) and the
  real panel in a `PanelSurface`, offscreen on the software renderer, and
  grabs both tabs: 400 × 343 px at scale 1, 500 × 429 at
  `QT_SCALE_FACTOR=1.25` (IO's scale; the curve and bars correct), and
  mirrored with the interface in Arabic (every string translated, the
  hours and bars right to left, the curve left to right).
