# Climyte

A minimal iOS weather app. Monochrome, typography-led, and it inverts between a
light and dark treatment based on the real sunrise and sunset at the city you're
looking at — not the system appearance.

<!-- Screenshots: add light/dark captures here once you have a device build. -->

## What it does

- **Swipe between saved cities.** One page each; the theme follows the visible
  page, so swiping from a daytime city to a night-time one inverts the app. The
  page indicator is set in type rather than dots — it names what's either side
  of you, and you can tap a name to jump straight there.
- **Current location** is resolved on launch but never blocks the first render —
  saved cities paint immediately from cache. A newly located city goes first; one
  you had already saved keeps its place.
- **Works offline.** The last successful fetch for every saved city is cached,
  so a cold launch shows real data rather than a spinner, and a failed refresh
  says how old the readings on screen are.
- **Each city in its own units**, derived from the city's ISO country code: a
  US city shows Fahrenheit, miles per hour and miles; a UK city Celsius with
  miles per hour and miles; everywhere else metric. There is no global setting
  and no toggle.
- **Hourly and 7-day forecasts**, a sun arc, and a details section that shows
  only what is worth saying: rain when it is likely, UV in daylight above the
  protection threshold, visibility when it is actually poor, gusts when they
  exceed the average. A wet afternoon shows more rows than a still, clear night.
- **Rain, looking ahead.** The Rain row describes the next 24 hours, never rain
  that has already fallen — `92% · 3.7 mm from 7 am tomorrow`. A low chance
  still gets a mention when a millimetre or more is expected. When rain is due
  in the next two hours, a strip of quarter-hour bars sits beneath the row with
  when it starts and how much.
- **Widgets.** A small Home Screen widget, and circular, rectangular and inline
  Lock Screen widgets, each showing a saved city of your choice.
- **Large text reflows** rather than truncates: the header stacks, the city strip
  keeps a whole name in view, and the rain bars give way to a sentence.

## Weather data

Forecasts come from [Open-Meteo](https://open-meteo.com), which needs no API
key. Its data is licensed CC BY 4.0 and credited in the app; the free tier is
for non-commercial use. Coordinates are sent to fetch a forecast and nothing
else — see [`climyte/PrivacyInfo.xcprivacy`](climyte/PrivacyInfo.xcprivacy) and
[`climyteWidget/PrivacyInfo.xcprivacy`](climyteWidget/PrivacyInfo.xcprivacy).

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

CI runs the suite on every push and pull request, three times: in the default
region, under Thailand's Buddhist calendar (`-testRegion TH`) and under
Germany's decimal comma (`-testRegion DE`). Both have broken fixed-format
parsing or formatting before. It resolves a simulator at runtime via
[`Tools/pick-simulator.py`](Tools/pick-simulator.py) rather than pinning a model
name, because runner images swap their bundled simulators without notice.

To check a layout at a large text size in the simulator, pass
`-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`
as a launch argument. `simctl ui content_size` does not reach apps.

## Project layout

```
climyte/
  ContentView.swift        Paging shell, search overlay, theme selection
  WeatherViewModel.swift   Saved cities, per-city fetch state, search
  LocationManager.swift    Current location, resolved without blocking launch
  Views/                   One file per section of the screen
Shared/                    Compiled into both the app and the widget
  WeatherModel.swift       Domain models and Open-Meteo decoding
  WeatherService.swift     Networking and error mapping
  RainOutlook.swift        The next two hours and the next 24 hours of rain
  WeatherDetail.swift      Which detail rows to show, and what they say
  CityEntry.swift          Per-city state, and stable identity for a City
  SavedCities.swift        The saved list, shared with the widget
  WeatherCache.swift       On-disk cache of the last fetch per city
  FetchDecision.swift      When a widget timeline pass fetches or defers
  Design/                  Typography ramp and unit system
  Fonts/                   Manrope
climyteWidget/             Home Screen and Lock Screen widgets
climyteTests/              257 tests
Tools/
  RenderAppIcon.swift      Regenerates the app icon in its three appearances
  pick-simulator.py        Resolves a simulator destination for CI
```

### A few decisions worth knowing

- **`City.key`, not `City.id`.** `id` is a fresh UUID on every decode, so it
  can't key persistent state. Identity comes from coordinates, which is already
  what `City` equality means.
- **Per-city state is a value type** (`CityEntry`) held in an array on an
  `@Observable` view model, so a change to one city redraws that city's page
  without any manual plumbing.
- **Fetches are tokened per city**, and the write-back re-resolves its index
  after awaiting, because the array can be reordered or have a city removed
  while a request is in flight.
- **Units come from the city, not the device.** Each `City` stores an ISO
  country code and derives its own `UnitSystem`; the API is always asked for
  metric and conversion happens at display time. Cities saved before the code
  existed fall back to matching the country name.
- **Rain reads the next 24 hours, not the calendar day.** The day's own figures
  run midnight to midnight, so by the afternoon they described rain that had
  already fallen. The Rain row and the widgets read the hourly forecast instead.
- **The saved list is mirrored to a file** in the App Group container. The
  shared defaults domain was seen to lose the key between the app and the
  widget; the file is the widget's fallback.
- **The widget's city is a `String`, not an `AppEntity`.** An entity never
  round-tripped through the widget's configuration, so a chosen city was lost.
- **Font names are deliberately odd.** The bundled Manrope files report
  PostScript names like `ManropeExtraLight-Bold`; the type ramp in
  [`Shared/Design/Typography.swift`](Shared/Design/Typography.swift) matches the
  files, not the family. Re-downloading Manrope will break every lookup.

## Localization

User-facing strings live in two String Catalogs:
[`climyte/Localizable.xcstrings`](climyte/Localizable.xcstrings) and
[`climyteWidget/Localizable.xcstrings`](climyteWidget/Localizable.xcstrings).
Adding a language means adding it in Xcode's String Catalog editor and filling
in the translations — no code changes.

Only Xcode writes newly extracted strings back into a catalog, so after adding
strings from the command line, sync them with:

```bash
xcodebuild -exportLocalizations -project climyte.xcodeproj -localizationPath /tmp/loc -exportLanguage en
```

The plumbing was verified with a pseudolocale (every string bracketed and
accented) to confirm nothing bypasses the catalog. Numbers, times and weekday
names come from the formatters and follow the device locale on their own.

## Regenerating the app icon

```bash
swift Tools/RenderAppIcon.swift climyte/Assets.xcassets/AppIcon.appiconset
```

Writes all three appearances. Geometry and palettes are constants at the top of
the script.
