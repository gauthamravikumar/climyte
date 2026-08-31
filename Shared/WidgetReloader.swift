//
//  WidgetReloader.swift
//  climyte
//

import Foundation
import os
import WidgetKit

/// Seam for telling WidgetKit that the data behind the widget has changed.
///
/// A protocol rather than a direct call so the view model can be tested
/// without a widget host: `WidgetCenter` in a unit test does nothing
/// observable, which would leave the reload call sites unverifiable.
protocol WidgetReloading {
    func reload()
}

/// Asks WidgetKit to rebuild every timeline, coalescing bursts into one call.
///
/// The widget renders whatever the app last wrote to the App Group and has no
/// network of its own, so without this it keeps showing the previous reading
/// until its own timeline runs out — up to six hours after the app already
/// knew better.
///
/// Coalesced because the requests arrive in clusters: a cold launch refreshes
/// every saved city, and each success would otherwise ask for its own reload.
/// One reload rebuilds all of them anyway.
final class WidgetReloader: WidgetReloading {
    static let shared = WidgetReloader()

    private var pending: Task<Void, Never>?
    private let delay: Duration
    private let reloadAll: () -> Void

    init(delay: Duration = .milliseconds(500),
         reloadAll: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.delay = delay
        self.reloadAll = reloadAll
    }

    func reload() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self.reloadAll()
            Log.widget.debug("Requested a widget timeline reload")
        }
    }

    /// Reloads now, dropping any coalescing window still in progress.
    ///
    /// Used when the app is leaving the foreground: the debounce assumes there
    /// is a later moment to fire in, and backgrounding is exactly the moment
    /// that stops being true — while also being when the widget is about to
    /// be looked at.
    func flush() {
        pending?.cancel()
        pending = nil
        reloadAll()
    }
}
