//
//  DeferralStore.swift
//  climyte
//

import Foundation

/// Remembers, per city, that a widget pass deferred its fetch so the next pass
/// knows to actually perform it.
///
/// Per city rather than one flag for everything. A single marker is shared by
/// every widget on the device: one widget deferring would push another's very
/// next pass down the blocking path, and that pass might be the one that had
/// to be fast. Two widgets showing two cities have nothing to say to each
/// other about when to fetch.
nonisolated struct DeferralStore {
    private static let key = "widget_deferred_fetches"

    private let defaults: UserDefaults
    private let window: TimeInterval

    /// - Parameter window: how long a deferral stays in force. Past it, a pass
    ///   that never got its follow-up falls back to fetching inline rather
    ///   than deferring for ever.
    init(defaults: UserDefaults? = nil, window: TimeInterval = 120) {
        self.defaults = defaults ?? AppGroup.defaults
        self.window = window

        // The single global marker this replaced. Removed once rather than
        // left to sit in shared defaults for ever — the same accumulation the
        // weather cache was just fixed for.
        if self.defaults.object(forKey: Self.legacyKey) != nil {
            self.defaults.removeObject(forKey: Self.legacyKey)
        }
    }

    private static let legacyKey = "widget_deferred_fetch_at"

    func lastDeferral(forCity cityKey: String, now: Date = Date()) -> Date? {
        guard let stamp = stored()[cityKey] else { return nil }
        let date = Date(timeIntervalSinceReferenceDate: stamp)
        return now.timeIntervalSince(date) < window ? date : nil
    }

    func record(forCity cityKey: String, at date: Date = Date()) {
        var all = stored()
        all[cityKey] = date.timeIntervalSinceReferenceDate
        write(pruned(all, now: date))
    }

    func clear(forCity cityKey: String) {
        var all = stored()
        guard all.removeValue(forKey: cityKey) != nil else { return }
        write(all)
    }

    // MARK: - Storage

    private func stored() -> [String: Double] {
        defaults.dictionary(forKey: Self.key) as? [String: Double] ?? [:]
    }

    private func write(_ all: [String: Double]) {
        if all.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else {
            defaults.set(all, forKey: Self.key)
        }
    }

    /// Drops entries far past the window, so cities the reader removed long
    /// ago cannot accumulate here the way they once did in the weather cache.
    private func pruned(_ all: [String: Double], now: Date) -> [String: Double] {
        all.filter { now.timeIntervalSinceReferenceDate - $0.value < window * 10 }
    }
}
