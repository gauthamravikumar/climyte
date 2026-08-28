//
//  WidgetBackground.swift
//  climyteWidget
//

import SwiftUI
import WidgetKit

/// The widget's surface: a flat fill that inverts with the city's own day and
/// night, so a widget for a city where it is 3am reads dark even in daylight.
///
/// Deliberately not a material. A widget's views are archived by the extension
/// and rendered later by the system, so there is no live wallpaper behind them
/// for a blur to sample — `Material` is not among the view types WidgetKit
/// supports, and a translucent surface here would not composite the way it
/// does inside the app.
///
/// Translucency is not lost, only relocated: when the reader picks a tinted or
/// clear Home Screen appearance, iOS discards this background entirely and
/// substitutes its own glass treatment. The system owns that look; this owns
/// the day/night one.
struct WidgetBackground: View {
    let theme: WeatherTheme

    var body: some View {
        theme.background
    }
}
