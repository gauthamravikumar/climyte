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
            return saved
        }

        // The key that predates the list.
        if let data = defaults.data(forKey: legacySingleCityKey),
           let single = try? JSONDecoder().decode(City.self, from: data) {
            return [single]
        }

        return []
    }

    nonisolated static func save(_ cities: [City], to defaults: UserDefaults) {
        guard let encoded = try? JSONEncoder().encode(cities) else { return }
        defaults.set(encoded, forKey: key)
    }
}
