//
//  climyteApp.swift
//  climyte
//
//  Created by Gautham Ravikumar on 23/7/2026.
//

import SwiftUI

@main
struct climyteApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            // One clock for the whole app, ticking on the minute. The theme,
            // the sun arc, the header clock and the day-or-night words all read
            // this instant, so they turn together. Read separately, the page
            // could go dark at sunset while the arc still showed the sun up.
            TimelineView(.everyMinute) { context in
                ContentView()
                    .environment(\.now, context.date)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the foreground is both the last chance to spend a
            // coalescing window that assumed there would be a later moment,
            // and the moment the widget is about to be looked at.
            if phase != .active {
                WidgetReloader.shared.flush()
            }
        }
    }
}

private struct NowKey: EnvironmentKey {
    /// The real time wherever the app's clock isn't provided, as in previews.
    static var defaultValue: Date { Date() }
}

extension EnvironmentValues {
    /// The app's clock: the current minute, from the `TimelineView` in
    /// `climyteApp`. Views that decide day or night read this rather than
    /// `Date()`, so they all agree on which side of sunset it is.
    var now: Date {
        get { self[NowKey.self] }
        set { self[NowKey.self] = newValue }
    }
}
