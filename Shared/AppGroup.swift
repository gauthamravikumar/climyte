//
//  AppGroup.swift
//  climyte
//

import Foundation

/// Storage shared between the app and its widget extension.
///
/// A widget runs in a separate process with its own container, so anything it
/// needs to read has to live in an App Group rather than in the app's private
/// Documents, Caches or standard defaults.
nonisolated enum AppGroup {
    static let identifier = "group.com.gauthamravikumar.climyte"

    /// Defaults the widget can read. Falls back to `.standard` when the group
    /// is unavailable — an unprovisioned entitlement should degrade to an app
    /// that still works on its own, not one that loses its cities.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    /// The shared container, or nil when the entitlement is missing.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Whether shared storage is actually available. False in a build without
    /// the entitlement, which is worth knowing rather than silently ignoring.
    static var isAvailable: Bool { containerURL != nil }
}
