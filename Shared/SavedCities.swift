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

    /// A plain file beside the weather cache holding the same list.
    ///
    /// UserDefaults is served by cfprefsd, and its view of this App Group
    /// domain has been seen to diverge from the domain's own backing file:
    /// `saved_cities` read as absent in both the app and the widget while
    /// that file still held it, and a key written moments earlier round
    /// tripped fine. A list this important should not be reachable only
    /// through something that can do that. Nothing serves this file.
    nonisolated static var mirrorURL: URL? {
        AppGroup.containerURL?.appendingPathComponent("saved-cities.json")
    }

    /// Where a store keeps its copies. Explicit rather than global: a
    /// recovery source that does not belong to the store being read will
    /// happily answer for it, which under test meant the real app's cities
    /// turning up inside isolated suites.
    nonisolated struct Sources {
        var mirror: URL?
        var backingFile: URL?

        /// The App Group's own two copies.
        static var appGroup: Sources {
            Sources(mirror: mirrorURL,
                    backingFile: AppGroup.containerURL?
                        .appendingPathComponent("Library/Preferences/\(AppGroup.identifier).plist"))
        }

        /// For a store that has none — an isolated suite under test.
        static let none = Sources(mirror: nil, backingFile: nil)
    }

    /// `nil` means no source could be read, which is not the same as a reader
    /// who has no cities and must never be treated as one — pruning the
    /// weather cache on the strength of a failed read is how three cities'
    /// readings were destroyed at launch.
    /// `sources` has no default on purpose. It reaches shared, on-disk state,
    /// and a default sent two separate test suites reading and writing the
    /// real app's store before this comment existed.
    nonisolated static func loadIfReadable(from defaults: UserDefaults,
                                           sources: Sources) -> [City]? {
        if let data = defaults.data(forKey: key) {
            if let cities = decodeCities(data), !cities.isEmpty {
                return deduplicated(cities)
            }
            if decodeCities(data) == nil {
                quarantine(data, in: defaults)
                return nil
            }
        }

        // cfprefsd had nothing. Ask the copies it cannot lose.
        if let recovered = cities(at: sources.mirror) ?? citiesInBackingFile(sources.backingFile),
           !recovered.isEmpty {
            Log.cache.error("Saved cities recovered from disk after UserDefaults returned nothing")
            save(recovered, to: defaults, sources: sources)
            return deduplicated(recovered)
        }

        // The key that predates the list.
        if let data = defaults.data(forKey: legacySingleCityKey),
           let single = try? JSONDecoder().decode(City.self, from: data) {
            return [single]
        }

        return []
    }

    nonisolated static func load(from defaults: UserDefaults,
                                 sources: Sources) -> [City] {
        loadIfReadable(from: defaults, sources: sources) ?? []
    }

    private nonisolated static func cities(at url: URL?) -> [City]? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return decodeCities(data)
    }

    /// The preference domain's own backing store, read as a file rather than
    /// through UserDefaults. Only reached when UserDefaults has already said
    /// there is nothing — at which point this is the difference between
    /// recovering the reader's cities and losing them.
    private nonisolated static func citiesInBackingFile(_ url: URL?) -> [City]? {
        guard let url,
              let contents = NSDictionary(contentsOf: url) as? [String: Any],
              let data = contents[key] as? Data else { return nil }

        return decodeCities(data)
    }

    nonisolated static func save(_ cities: [City], to defaults: UserDefaults,
                                 sources: Sources) {
        let store = Store(version: version, cities: deduplicated(cities))
        guard let encoded = try? JSONEncoder().encode(store) else { return }

        defaults.set(encoded, forKey: key)
        if let mirror = sources.mirror {
            try? encoded.write(to: mirror, options: .atomic)
        }
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
