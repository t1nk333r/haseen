# Plan 179: the weather icon shows when Open-Meteo refuses

## Status

- **Priority**: P2
- **Effort**: XS
- **Risk**: LOW. One condition in haseen.weather's service and a day/night
  test for wttr.in's icon. Open-Meteo's icon still wins whenever it answers.
- **Depends on**: 022 (the weather widget), 052 (its port of Omarchy's weather panel, with the Open-Meteo icon)
- **Category**: shell, bar
- **Planned at**: 2026-11-21, from the owner
- **State**: DONE 2026-11-21 (`tests/test-weather.sh` 81/81; luna's bar
  after the deploy is the owner's check)

## Problem

The owner, 2026-11-21: "where is weather on luna?". The widget was in luna's
bar (`center`, between `t1nk33r.tailscale` and `haseen.clock`), enabled,
valid and without errors (`haseen shell ipc shell plugins`), but drew
nothing. `Widget.qml` hides itself while the service's `label` is empty
(`visible: glyph !== ""`).

luna's `haseen.weather` settings hold coordinates (`location: "lat,lon"`).
With coordinates, only Open-Meteo's answer set the label: `acceptReport`
filled it from wttr.in only `if (!root.hasConfiguredCoordinates)`
(`share/haseen/shell/plugins/haseen.weather/Service.qml` on origin/main at
`7c1ab3f`). From luna, on 2026-11-21:

- the service's own Open-Meteo request (`Model.openMeteoUrl`: daily and
  current fields, `forecast_days=4`, `timezone=auto`) got `403 Forbidden`
  from nginx six times running, with exact, rounded and reordered
  coordinates alike;
- a short request (`current=temperature_2m`) got 200, and Open-Meteo's
  rate-limit headers showed 588 of 600 left in the minute. A quota overrun
  answers 429 with a JSON reason, so this looks like an address-level block
  on Open-Meteo's side, of unknown length;
- wttr.in answered the same coordinates at once (21 °C, code 113).

The service fetched wttr.in's report and used it for the panel's current
conditions (the `current` fallback), but not for the bar's icon. The bar
stayed empty for as long as Open-Meteo refused.

The condition existed because wttr.in has no day/night flag, so its icon
always drew the day glyph (`iconForCode(code, false)` in `currentIcon`). A
clear night would have shown a sun until Open-Meteo answered.

## Decision

- wttr.in's report sets the label whether or not coordinates are known,
  until Open-Meteo has given one. `labelFromOpenMeteo` records that Open-Meteo
  set it. After that, wttr.in no longer replaces it, until the location
  changes (`onLocationQueryChanged` resets it). Open-Meteo's answer sets the
  label only when it carries current conditions.
- wttr.in's icon is day/night aware. The World Weather Online symbol that
  wttr.in links for the current condition names the night ones
  (`wsymbol_0008_clear_sky_night.png`, seen in wttr.in's answer for luna's
  coordinates at 04:39 local time). `Model.wttrIsNight` reads that, and with
  no link the icon is day. `provisionalCurrentIcon`, which filled only an
  empty label, is gone.
- The panel needed nothing: its current conditions already fall back to
  wttr.in (`current` in `Service.qml`), and its days to wttr.in's forecast
  (`Model.buildForecastDays`).
- Manifest version 2.0.1.

## Rejected

- **A different forecast provider.** wttr.in is already fetched and
  answers. A third service is one more dependency, for an outage that may be
  temporary.
- **Splitting the Open-Meteo request into smaller ones**, because a short
  one went through. That would be guessing at a block whose rule is not
  published, and it would double the requests.
- **wttr.in's astronomy times for day and night.** For Riyadh, its answer
  gave sunrise 04:50 AM and sunset 06:34 PM, matching neither local nor UTC
  time. Its `observation_time` is UTC with no date, so the icon link is the
  only reliable signal.

## Verification

`tests/test-weather.sh` (81/81):

- Model units: wttr.in's icon is night for a `_night.png` symbol, day for a
  day symbol and day without one;
- the service in the real Quickshell engine, with saved coordinates and
  Open-Meteo refusing every request (`WEATHER_OM=refused` in the curl stub):
  Open-Meteo was asked, the label is wttr.in's night icon, not marked as
  Open-Meteo's, and the temperature is wttr.in's;
- the GeoClue scenario: Open-Meteo's night icon is kept, marked as
  Open-Meteo's, whichever answer arrives first.

Against the old `Service.qml`, the refused scenario produces no result (the
label never fills) and four of these checks fail.
