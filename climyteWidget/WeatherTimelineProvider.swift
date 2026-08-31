//
//  WeatherTimelineProvider.swift
//  climyteWidget
//

import WidgetKit
import os
import SwiftUI

struct WeatherEntry: TimelineEntry {
    let date: Date
    let city: City?
    let weather: CityWeather?
    /// When the reading was fetched, which is not when this entry was made.
    let fetchedAt: Date?

    var units: UnitSystem { city?.unitSystem ?? .metric }

    /// How old the reading is at the moment this entry is shown, or nil when
    /// there is no reading.
    var age: TimeInterval? {
        guard let fetchedAt else { return nil }
        return max(0, date.timeIntervalSince(fetchedAt))
    }

    /// The reading's age, shown only once it is old enough to matter.
    ///
    /// A widget that fetches for itself is normally current, so a value here
    /// is the failure case: the network has been unreachable across several
    /// runs, and the number on screen is not the weather outside.
    var shortAge: String? { ReadingAge.short(age) }

    /// Night is judged at the entry's own date, not at the moment the
    /// timeline was built. The two are hours apart by design.
    var theme: WeatherTheme {
        WeatherTheme.forIsNight(weather?.isNight(at: date) ?? false)
    }
}

struct WeatherTimelineProvider: AppIntentTimelineProvider {

    /// Shown while the real entry loads, and in the widget gallery. Uses the
    /// first saved city's cached reading when there is one so the gallery
    /// preview looks like the user's own data rather than invented weather.
    func placeholder(in context: Context) -> WeatherEntry {
        entry(for: SelectCityIntent())
    }

    func snapshot(for configuration: SelectCityIntent, in context: Context) async -> WeatherEntry {
        entry(for: configuration)
    }

    /// One reload: fetch if we can, then plan the next couple of hours.
    ///
    /// WidgetKit grants roughly 40-70 reloads a day per widget instance. A
    /// two-hour span spends about twelve of them, which leaves the reading at
    /// most two hours behind while staying well inside the budget even with
    /// several widgets placed.
    ///
    /// Within a run the reading is fixed, but the entries are not redundant:
    /// the day/night treatment flips at the city's own sunrise and sunset
    /// without spending a reload to do it.
    func timeline(for configuration: SelectCityIntent, in context: Context) async -> Timeline<WeatherEntry> {
        let base = await refreshed(entry(for: configuration))
        let now = Date()
        let horizon = now.addingTimeInterval(Self.timelineSpan)

        let dates = TimelinePlan.renderDates(from: now, to: horizon,
                                             solarDays: base.weather?.solarDays ?? [])
        let entries = dates.map {
            WeatherEntry(date: $0, city: base.city,
                         weather: base.weather, fetchedAt: base.fetchedAt)
        }

        return Timeline(entries: entries, policy: .atEnd)
    }

    /// How far ahead one reload plans, and so how often a fetch is attempted.
    static let timelineSpan: TimeInterval = 2 * 3600

    /// Fetches the entry's city, returning the cached entry unchanged if that
    /// fails for any reason.
    ///
    /// The widget has its own network rather than waiting for the app to be
    /// opened. Without it the cache is only ever as fresh as the last time
    /// someone launched Climyte, which for a weather app people check from the
    /// Home Screen is routinely most of a day.
    ///
    /// A success is written back to the shared cache, so opening the app finds
    /// the reading the widget already has instead of fetching it a second time.
    private func refreshed(_ cached: WeatherEntry) async -> WeatherEntry {
        guard let city = cached.city else { return cached }

        do {
            let weather = try await WeatherService.widget.fetchWeather(for: city)
            WeatherCache().save(city: city, response: weather.response)
            return WeatherEntry(date: .now, city: city, weather: weather, fetchedAt: .now)
        } catch {
            // Nothing to surface: the cached reading is already on screen and
            // `isStale` says how much to trust it.
            Log.widget.error("Widget fetch failed for \(city.name, privacy: .public): \(error.localizedDescription)")
            return cached
        }
    }

    private func entry(for configuration: SelectCityIntent) -> WeatherEntry {
        let saved = SavedCityQuery.savedCities()
        // Fall back to the first saved city so a freshly placed widget shows
        // something real before the user has configured it.
        let city = configuration.city?.city ?? saved.first

        guard let city, let cached = WeatherCache().load(for: city) else {
            return WeatherEntry(date: .now, city: city, weather: nil, fetchedAt: nil)
        }

        return WeatherEntry(
            date: .now,
            city: cached.city,
            weather: CityWeather(city: cached.city, response: cached.response),
            fetchedAt: cached.fetchedAt
        )
    }
}
