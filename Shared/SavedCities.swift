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

        /// Increments on every save. Two copies of the list can disagree —
        /// one is served by cfprefsd and the other is a file — and without a
        /// revision there is no way to tell which is the newer, so recovery
        /// picked whichever it looked at first. That resurrected cities the
        /// reader had deleted.
        var revision: Int?
    }

    /// A copy of the list and how new it is. `revision` is nil for the
    /// unversioned shape that shipped first, which is therefore the oldest
    /// anything can be.
    private struct Copy {
        let cities: [City]
        let revision: Int
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
        let stored = defaults.data(forKey: key)

        if let stored, decode(stored) == nil {
            // Bytes are there and match no shape we know. Keep them: the
            // caller falls back to a default city and saves it.
            quarantine(stored, in: defaults)
            return nil
        }

        // Every copy, newest first. The stores can disagree — cfprefsd loses a
        // key, or a write reaches one and not the other — and taking whichever
        // answered first is how a deleted city came back.
        let copies = [stored, data(at: sources.mirror), backingFileData(sources.backingFile)]
            .compactMap { $0.flatMap(decode) }

        // Strictly greater, so a tie keeps the earlier source. Copies written
        // before revisions existed are all revision 0, and there the order
        // above is the answer: what cfprefsd holds, then the mirror, then the
        // backing file, which is the stalest of the three by nature.
        var newest: Copy?
        for copy in copies where newest == nil || copy.revision > newest!.revision {
            newest = copy
        }

        if let newest, !newest.cities.isEmpty {
            if copies.count > 1 || stored == nil {
                Log.cache.error("Saved cities taken from the newest of \(copies.count, privacy: .public) copies")
                save(newest.cities, to: defaults, sources: sources, revision: newest.revision)
            }
            return deduplicated(newest.cities)
        }

        // Readable everywhere and empty, or nothing anywhere. Try the key that
        // predates the list before concluding there is nothing.
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

    nonisolated static func save(_ cities: [City], to defaults: UserDefaults,
                                 sources: Sources, revision: Int? = nil) {
        let next = revision ?? (highestRevision(defaults: defaults, sources: sources) + 1)
        let store = Store(version: version, cities: deduplicated(cities), revision: next)
        guard let encoded = try? JSONEncoder().encode(store) else { return }

        defaults.set(encoded, forKey: key)
        if let mirror = sources.mirror {
            try? encoded.write(to: mirror, options: .atomic)
        }
    }

    private nonisolated static func highestRevision(defaults: UserDefaults, sources: Sources) -> Int {
        [defaults.data(forKey: key), data(at: sources.mirror), backingFileData(sources.backingFile)]
            .compactMap { $0.flatMap(decode)?.revision }
            .max() ?? 0
    }

    private nonisolated static func data(at url: URL?) -> Data? {
        guard let url else { return nil }
        return try? Data(contentsOf: url)
    }

    private nonisolated static func backingFileData(_ url: URL?) -> Data? {
        guard let url,
              let contents = NSDictionary(contentsOf: url) as? [String: Any] else { return nil }
        return contents[key] as? Data
    }

    /// A copy, with how new it is. The unversioned shape that shipped first
    /// has no revision, so it loses to anything that does.
    private nonisolated static func decode(_ data: Data) -> Copy? {
        let decoder = JSONDecoder()

        if let store = try? decoder.decode(Store.self, from: data) {
            return Copy(cities: store.cities, revision: store.revision ?? 0)
        }
        if let bare = try? decoder.decode([City].self, from: data) {
            return Copy(cities: bare, revision: 0)
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
