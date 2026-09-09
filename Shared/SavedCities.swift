//
//  SavedCities.swift
//  climyte
//

import Foundation
import os

/// The saved city list, as stored.
///
/// One reader for both processes. The app and the widget decoding this
/// separately would let them drift — a widget offering a city the app no
/// longer has, or missing one it does.
nonisolated enum SavedCities {
    nonisolated static let key = "saved_cities"
    nonisolated static let legacySingleCityKey = "saved_active_city"

    /// Where a store we could not read is set aside. Nothing reads it back
    /// automatically; it exists so the bytes survive long enough to be
    /// recovered by hand or by a later migration.
    nonisolated static let unreadableKey = "saved_cities_unreadable"

    /// Bump when `City`'s stored shape changes in a way this decoder cannot
    /// absorb. Version 1 was a bare `[City]` with no envelope, which is why a
    /// shape change used to be indistinguishable from an empty store.
    nonisolated static let version = 2

    private struct Store: Codable {
        let version: Int
        let cities: [City]
    }

    nonisolated static func load(from defaults: UserDefaults) -> [City] {
        if let data = defaults.data(forKey: key) {
            switch decodeCities(data) {
            case .some(let cities) where !cities.isEmpty:
                return deduplicated(cities)
            case .some:
                // Readable and empty. Fall through to the legacy key rather
                // than treating it as a fault.
                break
            case .none:
                // Neither shape read. The caller will fall back to a default
                // city and save it, which would overwrite the only copy of a
                // list we merely failed to parse.
                quarantine(data, in: defaults)
            }
        }

        // The key that predates the list.
        if let data = defaults.data(forKey: legacySingleCityKey),
           let single = try? JSONDecoder().decode(City.self, from: data) {
            return [single]
        }

        return []
    }

    nonisolated static func save(_ cities: [City], to defaults: UserDefaults) {
        let store = Store(version: version, cities: deduplicated(cities))
        guard let encoded = try? JSONEncoder().encode(store) else { return }
        defaults.set(encoded, forKey: key)
    }

    /// `nil` means the bytes matched no shape this build knows. An empty array
    /// means the store was read and holds nothing — a different thing, and the
    /// distinction the bare-array format could not express.
    private nonisolated static func decodeCities(_ data: Data) -> [City]? {
        let decoder = JSONDecoder()

        if let store = try? decoder.decode(Store.self, from: data) {
            return store.cities
        }

        // Version 1: a bare array, no envelope.
        if let bare = try? decoder.decode([City].self, from: data) {
            return bare
        }

        return nil
    }

    private nonisolated static func quarantine(_ data: Data, in defaults: UserDefaults) {
        // Keep the first copy. A second failure is the same store failing
        // again, and overwriting would replace the original with whatever a
        // partial migration has since written.
        guard defaults.data(forKey: unreadableKey) == nil else { return }

        Log.cache.error("Saved cities could not be decoded; keeping the bytes under \(unreadableKey, privacy: .public)")
        defaults.set(data, forKey: unreadableKey)
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
