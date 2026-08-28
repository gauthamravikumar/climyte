//
//  WeatherTimelineProvider.swift
//  climyteWidget
//

import WidgetKit
import SwiftUI

struct WeatherEntry: TimelineEntry {
    let date: Date
    let city: City?
    let weather: CityWeather?
    /// When the reading was fetched, which is not when this entry was made.
    let fetchedAt: Date?

    var units: UnitSystem { city?.unitSystem ?? .metric }

    var theme: WeatherTheme {
        WeatherTheme.forIsNight(weather?.isNight ?? false)
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

    /// The widget never fetches; it renders whatever the app last cached.
    ///
    /// WidgetKit grants roughly 40-70 reloads a day per widget instance, so a
    /// timeline holding a single entry and asking to be reloaded in half an
    /// hour would spend the entire budget by evening. Instead one reload
    /// returns several hours of entries: the reading does not change between
    /// them, but each entry re-renders the city's local clock and lets the
    /// day/night treatment flip at sunrise and sunset without spending
    /// anything. A reload is requested only at the end of that run.
    func timeline(for configuration: SelectCityIntent, in context: Context) async -> Timeline<WeatherEntry> {
        let base = entry(for: configuration)
        let calendar = Calendar.current

        let entries: [WeatherEntry] = (0..<6).compactMap { hour in
            guard let date = calendar.date(byAdding: .hour, value: hour, to: .now) else { return nil }
            return WeatherEntry(date: date, city: base.city,
                                weather: base.weather, fetchedAt: base.fetchedAt)
        }

        return Timeline(entries: entries, policy: .atEnd)
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
