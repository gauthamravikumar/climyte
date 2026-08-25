//
//  WeatherCache.swift
//  climyte
//

import Foundation
import os

/// The last successful fetch, kept so the app has something to show before the
/// network answers — or when it never does.
struct CachedWeather: Codable {
    let city: City
    let response: WeatherResponse
    let fetchedAt: Date
}

/// File-backed store for the most recent fetch.
///
/// Lives in Caches rather than UserDefaults: the payload is tens of kilobytes,
/// which is more than UserDefaults is meant to hold, and the OS is welcome to
/// evict it under pressure — it's genuinely disposable.
struct WeatherCache {
    private let fileURL: URL

    init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.fileURL = base.appendingPathComponent("last-weather.json")
    }

    func save(city: City, response: WeatherResponse, at date: Date = Date()) {
        let cached = CachedWeather(city: city, response: response, fetchedAt: date)
        do {
            let data = try JSONEncoder().encode(cached)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // A cache write failing is not worth surfacing to the user.
            Log.cache.error("Failed to write weather cache: \(error.localizedDescription)")
        }
    }

    func load() -> CachedWeather? {
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(CachedWeather.self, from: data)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            Log.cache.error("Failed to read weather cache: \(error.localizedDescription)")
            return nil
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
