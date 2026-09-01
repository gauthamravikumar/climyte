//
//  SmallWidgetView.swift
//  climyteWidget
//

import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let entry: WeatherEntry

    /// Tinted and clear Home Screens render widgets in accented mode, where
    /// the system removes the background and tints content by alpha rather
    /// than luminance — every opaque region collapses to the same flat white.
    /// The day/night fill cannot survive that, so in accented mode the view
    /// stops asserting colour and lets the system own it.
    @Environment(\.widgetRenderingMode) private var renderingMode

    /// False in StandBy and on the iPad Lock Screen, where the container
    /// background is stripped and the content should fill the space.
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    private var isAccented: Bool { renderingMode == .accented }

    private var primary: Color { isAccented ? .primary : entry.theme.primaryText }
    private var secondary: Color { isAccented ? .secondary : entry.theme.secondaryText }
    private var divider: Color { isAccented ? .secondary.opacity(0.4) : entry.theme.dividerColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(entry.city?.name ?? "Climyte")
                    .font(.widgetCity)
                    .foregroundStyle(primary)
                    .lineLimit(1)

                // Only present when the reading is old, and then only as a
                // duration: the tile has no room to explain itself, but
                // showing a stale number with nothing to mark it as stale is
                // worse than the small amount of clutter this costs.
                if let age = entry.shortAge {
                    Spacer(minLength: 2)
                    Text(age)
                        .font(.widgetCaption)
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 2)

            Text(temperature)
                .font(.widgetTemperature)
                .foregroundStyle(primary)
                // The reading is what a glance is for, so it leads the accent
                // group when the system recolours the widget.
                .widgetAccentable()
                .lineLimit(1)
                // A three-digit Fahrenheit reading, or a large accessibility
                // text size, must shrink rather than truncate.
                .minimumScaleFactor(0.5)

            Spacer(minLength: 2)

            detail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(showsBackground ? 0 : 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenLabel)
    }

    /// The tile is deliberately terse; VoiceOver should not be.
    private var spokenLabel: String {
        let name = entry.city?.name ?? "Climyte"
        guard let weather = entry.weather else {
            return String(localized: "\(name), no reading yet")
        }
        let reading = String(localized: """
            \(name), \(entry.units.temperatureValue(weather.temperature)) degrees, \
            low \(entry.units.temperatureValue(weather.minTemp)), \
            high \(entry.units.temperatureValue(weather.maxTemp))
            """)

        // The visible "4h" is a duration with no noun attached; spoken, it
        // needs the noun or it is just a number in the middle of a sentence.
        guard let age = entry.shortAge else { return reading }
        return String(localized: "\(reading), from \(age) ago")
    }

    private var temperature: String {
        guard let weather = entry.weather else { return "--" }
        return entry.units.temperature(weather.temperature)
    }

    @ViewBuilder
    private var detail: some View {
        if let weather = entry.weather {
            VStack(alignment: .leading, spacing: 1) {
                Divider().overlay(divider)
                    .padding(.bottom, 4)

                // Same rule as the app's details section: rain earns the line
                // when it is likely, otherwise the day's range does.
                if let chance = weather.precipitationChance,
                   chance >= WeatherDetails.Threshold.rainChance {
                    Text(rainLine(chance: chance, weather: weather))
                        .font(.widgetDetail)
                        .foregroundStyle(primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("\(entry.units.temperatureValue(weather.minTemp)) · \(entry.units.temperatureValue(weather.maxTemp))")
                        .font(.widgetDetail)
                        .foregroundStyle(primary)
                        .lineLimit(1)
                }
            }
        } else {
            Text("Open Climyte")
                .font(.widgetCaption)
                .foregroundStyle(secondary)
        }
    }

    private func rainLine(chance: Int, weather: CityWeather) -> String {
        guard let amount = weather.precipitationAmount, amount > 0 else {
            return String(localized: "Rain \(WeatherDetails.percentage(chance))")
        }
        return "\(String(localized: "Rain \(WeatherDetails.percentage(chance))")) · \(entry.units.precipitation(amount))"
    }
}
