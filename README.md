# Climyte

A minimal iOS weather app. Monochrome, typography-led, and it inverts between a
light and dark treatment based on the real sunrise and sunset at the city you're
looking at — not the system appearance.

<!-- Screenshots: add light/dark captures here once you have a device build. -->

## What it does

- **Swipe between saved cities.** One page each; the theme follows the visible
  page, so swiping from a daytime city to a night-time one inverts the app.
- **Current location** is resolved on launch and pinned first, but never blocks
  the first render — saved cities paint immediately from cache.
- **Works offline.** The last successful fetch for every saved city is cached,
  so a cold launch shows real data rather than a spinner, and a failed refresh
  says how old the readings on screen are.
- **Metric or imperial.** Seeded from your region; tap the temperature to switch.
  Conversion happens at display time, so it's instant and works offline.
- **Hourly and 7-day forecasts**, plus sunrise/sunset, wind, humidity, UV and
  visibility.

Weather data comes from [Open-Meteo](https://open-meteo.com), which needs no API
key. Coordinates are sent to fetch a forecast and nothing else — see
[`PrivacyInfo.xcprivacy`](climyte/PrivacyInfo.xcprivacy).

## Requirements

- iOS 18.0+
- Xcode 26+

## Getting started

```bash
git clone https://github.com/gauthamravikumar/climyte.git
cd climyte
open climyte.xcodeproj
```

Then pick an iPhone simulator and run. There's no API key, no package manager
step, and no configuration.

## Running the tests

From Xcode, ⌘U. From the command line:

```bash
xcodebuild test -project climyte.xcodeproj -scheme climyte -destination 'platform=iOS Simulator,name=iPhone 17'
```

CI runs the same suite on every push and pull request. It resolves a simulator
at runtime via [`Tools/pick-simulator.py`](Tools/pick-simulator.py) rather than
pinning a model name, because runner images swap their bundled simulators
without notice.

## Project layout

```
climyte/
  ContentView.swift        Paging shell, search overlay, theme selection
  WeatherViewModel.swift   Saved cities, per-city fetch state, search
  WeatherModel.swift       Domain models and Open-Meteo decoding
  WeatherService.swift     Networking and error mapping
  WeatherCache.swift       On-disk cache of the last fetch per city
  CityEntry.swift          Per-city state, and stable identity for a City
  Design/                  Typography ramp, theme, unit system
  Views/                   One file per section of the screen
  Fonts/                   Manrope
Tools/
  RenderAppIcon.swift      Regenerates the app icon in its three appearances
  pick-simulator.py        Resolves a simulator destination for CI
```

### A few decisions worth knowing

- **`City.key`, not `City.id`.** `id` is a fresh UUID on every decode, so it
  can't key persistent state. Identity comes from coordinates, which is already
  what `City` equality means.
- **Per-city state is a value type** (`CityEntry`) inside a `@Published` array,
  rather than nested `ObservableObject`s — whose changes don't propagate through
  SwiftUI without manual plumbing.
- **Fetches are tokened per city**, and the write-back re-resolves its index
  after awaiting, because the array can be reordered or have a city removed
  while a request is in flight.
- **Units convert at display time.** Asking the API for different units would
  make switching a network round-trip and break it offline.
- **Font names are deliberately odd.** The bundled Manrope files report
  PostScript names like `ManropeExtraLight-Bold`; the type ramp in
  `Design/Typography.swift` matches the files, not the family. Re-downloading
  Manrope will break every lookup.

## Localization

User-facing strings live in
[`climyte/Localizable.xcstrings`](climyte/Localizable.xcstrings). Adding a
language means adding it in Xcode's String Catalog editor and filling in the
translations — no code changes.

The plumbing was verified with a pseudolocale (every string bracketed and
accented) to confirm nothing bypasses the catalog. Numbers, times and weekday
names come from `DateFormatter` and follow the device locale on their own.

## Regenerating the app icon

```bash
swift Tools/RenderAppIcon.swift climyte/Assets.xcassets/AppIcon.appiconset
```

Writes all three appearances. Geometry and palettes are constants at the top of
the script.
