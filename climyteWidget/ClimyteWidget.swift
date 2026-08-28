//
//  ClimyteWidget.swift
//  climyteWidget
//

import WidgetKit
import SwiftUI

struct ClimyteWidget: Widget {
    let kind = "ClimyteWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: SelectCityIntent.self,
                               provider: WeatherTimelineProvider()) { entry in
            SmallWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackground(theme: entry.theme)
                }
        }
        .configurationDisplayName("Weather")
        .description("The current reading for a saved city.")
        .supportedFamilies([.systemSmall])
    }
}

struct ClimyteAccessoryWidget: Widget {
    let kind = "ClimyteAccessoryWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: SelectCityIntent.self,
                               provider: WeatherTimelineProvider()) { entry in
            AccessoryView(entry: entry)
                // EmptyView, not a colour: AccessoryWidgetBackground renders
                // invisible when a container background is declared over it.
                .containerBackground(for: .widget) { EmptyView() }
        }
        .configurationDisplayName("Climyte")
        .description("The current reading on your lock screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

/// One entry point per family, so each accessory can be laid out for the space
/// it actually gets rather than sharing a compromise.
private struct AccessoryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeatherEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            AccessoryCircularView(entry: entry)
        case .accessoryRectangular:
            AccessoryRectangularView(entry: entry)
        default:
            AccessoryInlineView(entry: entry)
        }
    }
}

@main
struct ClimyteWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClimyteWidget()
        ClimyteAccessoryWidget()
    }
}
