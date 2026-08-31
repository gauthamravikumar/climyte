//
//  WeatherCache.swift
//  climyte
//

import Foundation
import os

/// The last successful fetch for one city, kept so the app has something to
/// show before the network answers — or when it never does.
nonisolated struct CachedWeather: Codable {
    let city: City
    let response: WeatherResponse
    let fetchedAt: Date
}

/// File-backed store for the most recent fetch of each saved city.
///
/// Lives in Caches rather than UserDefaults: the payload is tens of kilobytes
/// per city, which is more than UserDefaults is meant to hold, and the OS is
/// welcome to evict it — it's genuinely disposable.
///
/// Two processes write here. The app caches what it fetches, and so does the
/// widget extension, which has its own network and runs on a schedule the app
/// knows nothing about. Every mutation is therefore a read-modify-write of the
/// whole file taken under file coordination: without it, the app and the widget
/// can each read the same two cities, each update a different one, and each
/// write back a file missing the other's change. Nothing is corrupted by that —
/// the write itself is atomic — but an update is silently lost.
nonisolated struct WeatherCache {
    private let fileURL: URL

    init(directory: URL? = nil) {
        // The App Group container first, so the widget can read the same file.
        // Caches remains the fallback: without the entitlement the app should
        // still cache for itself rather than lose the feature entirely.
        let base = directory
            ?? AppGroup.containerURL
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.fileURL = base.appendingPathComponent("cached-weather.json")
    }

    // MARK: - Reading

    func load(for city: City) -> CachedWeather? {
        loadAll().first { $0.city.key == city.key }
    }

    func loadAll() -> [CachedWeather] {
        var result: [CachedWeather] = []
        coordinate(writing: false) { url in
            result = decode(at: url)
        }
        return result
    }

    // MARK: - Writing

    func save(city: City, response: WeatherResponse, at date: Date = Date()) {
        mutate { all in
            all.removeAll { $0.city.key == city.key }
            all.append(CachedWeather(city: city, response: response, fetchedAt: date))
        }
    }

    /// Drops any cached city not in `cities`, so removing a city doesn't leave
    /// its payload on disk forever.
    func prune(keeping cities: [City]) {
        let keys = Set(cities.map(\.key))
        mutate { all in
            all.removeAll { !keys.contains($0.city.key) }
        }
    }

    func clear() {
        coordinate(writing: true) { url in
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Reads, transforms and writes the whole file as one coordinated unit.
    private func mutate(_ transform: (inout [CachedWeather]) -> Void) {
        coordinate(writing: true) { url in
            var all = decode(at: url)
            transform(&all)
            encode(all, to: url)
        }
    }

    // MARK: - Coordination

    /// Runs `body` while holding coordinated access to the cache file.
    ///
    /// `body` must use the URL it is handed rather than `fileURL`: coordination
    /// may present the file at a different location. It must also not call back
    /// into the coordinated methods above — nesting coordination on one file
    /// from the same process deadlocks, which is why the primitives below are
    /// separate from the API.
    private func coordinate(writing: Bool, _ body: (URL) -> Void) {
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator()

        if writing {
            coordinator.coordinate(writingItemAt: fileURL, options: [],
                                   error: &coordinationError, byAccessor: body)
        } else {
            coordinator.coordinate(readingItemAt: fileURL, options: [],
                                   error: &coordinationError, byAccessor: body)
        }

        if let coordinationError {
            // Losing coordination means falling back to no cache for this call,
            // which is survivable; the reading is refetched.
            Log.cache.error("File coordination failed: \(coordinationError.localizedDescription)")
        }
    }

    // MARK: - Uncoordinated primitives
    //
    // Only ever called from inside `coordinate`.

    private func decode(at url: URL) -> [CachedWeather] {
        do {
            return try JSONDecoder().decode([CachedWeather].self, from: Data(contentsOf: url))
        } catch CocoaError.fileReadNoSuchFile {
            return []
        } catch {
            Log.cache.error("Failed to read weather cache: \(error.localizedDescription)")
            return []
        }
    }

    private func encode(_ entries: [CachedWeather], to url: URL) {
        do {
            try JSONEncoder().encode(entries).write(to: url, options: .atomic)
        } catch {
            // A cache write failing is not worth surfacing to the user.
            Log.cache.error("Failed to write weather cache: \(error.localizedDescription)")
        }
    }
}
