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
            ContentView()
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
