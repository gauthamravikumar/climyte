//
//  WeatherCache.swift
//  climyte
//

import Foundation
import os

/// The last successful fetch for one city, kept so the app has something to
/// show before the network answers — or when it never does.
struct CachedWeather: Codable {
    let city: City
    let response: WeatherResponse
    let fetchedAt: Date
}

/// File-backed store for the most recent fetch of each saved city.
///
/// Lives in Caches rather than UserDefaults: the payload is tens of kilobytes
/// per city, which is more than UserDefaults is meant to hold, and the OS is
/// welcome to evict it — it's genuinely disposable.
struct WeatherCache {
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

    func save(city: City, response: WeatherResponse, at date: Date = Date()) {
        var all = loadAll()
        all.removeAll { $0.city.key == city.key }
        all.append(CachedWeather(city: city, response: response, fetchedAt: date))
        write(all)
    }

    func load(for city: City) -> CachedWeather? {
        loadAll().first { $0.city.key == city.key }
    }

    func loadAll() -> [CachedWeather] {
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([CachedWeather].self, from: data)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        } catch {
            Log.cache.error("Failed to read weather cache: \(error.localizedDescription)")
            return []
        }
    }

    /// Drops any cached city not in `cities`, so removing a city doesn't leave
    /// its payload on disk forever.
    func prune(keeping cities: [City]) {
        let keys = Set(cities.map(\.key))
        let kept = loadAll().filter { keys.contains($0.city.key) }
        write(kept)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func write(_ entries: [CachedWeather]) {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // A cache write failing is not worth surfacing to the user.
            Log.cache.error("Failed to write weather cache: \(error.localizedDescription)")
        }
    }
}
