//
//  SavedCities.swift
//  climyte
//

import Foundation

/// The saved city list, as stored.
///
/// One reader for both processes. The app and the widget decoding this
/// separately would let them drift — a widget offering a city the app no
/// longer has, or missing one it does.
nonisolated enum SavedCities {
    nonisolated static let key = "saved_cities"
    nonisolated static let legacySingleCityKey = "saved_active_city"

    nonisolated static func load(from defaults: UserDefaults) -> [City] {
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([City].self, from: data),
           !saved.isEmpty {
            return deduplicated(saved)
        }

        // The key that predates the list.
        if let data = defaults.data(forKey: legacySingleCityKey),
           let single = try? JSONDecoder().decode(City.self, from: data) {
            return [single]
        }

        return []
    }

    nonisolated static func save(_ cities: [City], to defaults: UserDefaults) {
        guard let encoded = try? JSONEncoder().encode(deduplicated(cities)) else { return }
        defaults.set(encoded, forKey: key)
    }

    /// Keeps the first of any cities sharing a key, in order.
    ///
    /// `CityEntry.id` is `city.key`, and the pager is a `ForEach` over those
    /// ids — duplicate identities there are undefined behaviour in SwiftUI,
    /// not merely a repeated row. Adding a city already checks for this, but
    /// the check cannot speak for what is already on disk: two search results
    /// under ~11m apart round to the same four-decimal key, and nothing
    /// validates the stored list on the way in.
    nonisolated static func deduplicated(_ cities: [City]) -> [City] {
        var seen = Set<String>()
        return cities.filter { seen.insert($0.key).inserted }
    }
}
