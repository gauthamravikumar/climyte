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
        let saved = SavedCityQuery.savedCities()
        let cached = entry(for: configuration, saved: saved)

        // Anything we can already draw goes back immediately, and the fetch
        // happens afterwards.
        //
        // Changing the widget's city throws away the timeline built for the
        // old one, and WidgetKit has nothing to put on screen until this
        // function returns — so awaiting a request here is a blank widget for
        // exactly as long as the network takes, about a second and a half.
        // During an ordinary scheduled reload that wait is invisible, because
        // the previous timeline stays on screen while this runs; a
        // reconfiguration is the one case with nothing behind it. That is why
        // it took a real device and someone changing a city to notice.
        // Keyed by city: what one widget deferred says nothing about what
        // another, showing somewhere else, should do next.
        let cityKey = cached.city?.key
        let deferrals = DeferralStore()

        switch FetchDecision.decide(hasReading: cached.weather != nil,
                                    age: cached.age,
                                    lastDeferral: cityKey.flatMap { deferrals.lastDeferral(forCity: $0) }) {
        case .useCache:
            if let cityKey { deferrals.clear(forCity: cityKey) }
            return plan(from: cached)

        case .deferFetch:
            // Show the cached reading now and come straight back for the
            // fetch — by then there is something on screen to keep showing
            // while we wait.
            if let cityKey { deferrals.record(forCity: cityKey) }
            return plan(from: cached, reloadAfter: Self.deferredFetchDelay)

        case .fetchNow:
            if let cityKey { deferrals.clear(forCity: cityKey) }
            return plan(from: await refreshed(cached, saved: saved))
        }
    }

    /// How long to wait before coming back for the fetch that was deferred.
    private static let deferredFetchDelay: TimeInterval = 10


    private func plan(from base: WeatherEntry,
                     reloadAfter delay: TimeInterval? = nil) -> Timeline<WeatherEntry> {
        let now = Date()
        let dates = TimelinePlan.renderDates(from: now,
                                             to: now.addingTimeInterval(Self.timelineSpan),
                                             solarDays: base.weather?.solarDays ?? [])
        let entries = dates.map {
            WeatherEntry(date: $0, city: base.city,
                         weather: base.weather, fetchedAt: base.fetchedAt)
        }

        guard let delay else { return Timeline(entries: entries, policy: .atEnd) }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(delay)))
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
    private func refreshed(_ cached: WeatherEntry, saved: [City]) async -> WeatherEntry {
        guard let city = cached.city else { return cached }

        // Most reloads arrive moments after the app cached this very reading.
        guard ReadingAge.needsRefetch(cached.age) else { return cached }

        do {
            let weather = try await WeatherService.widget.fetchWeather(for: city)

            // Only cities the app still lists belong in its cache. A widget
            // can outlive the city it was configured for — removing a city
            // prunes its payload, and writing this one back unconditionally
            // would restore it and then keep it refreshed forever, with
            // nothing left to ever prune it again.
            if saved.contains(where: { $0.key == city.key }) {
                WeatherCache().save(city: city, response: weather.response)
            }

            return WeatherEntry(date: .now, city: city, weather: weather, fetchedAt: .now)
        } catch {
            // Nothing to surface: the cached reading is already on screen and
            // `isStale` says how much to trust it.
            Log.widget.error("Widget fetch failed for \(city.name, privacy: .public): \(error.localizedDescription)")
            return cached
        }
    }

    private func entry(for configuration: SelectCityIntent,
                       saved: [City] = SavedCityQuery.savedCities()) -> WeatherEntry {
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
