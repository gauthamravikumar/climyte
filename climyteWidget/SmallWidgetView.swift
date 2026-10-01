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
                .font(.widgetHeroSmall)
                .tracking(-3.6)
                // Trimmed on the glyph: the line box at this size is deeper
                // than the tile has room for.
                .padding(.vertical, -12)
                .foregroundStyle(primary)
                // The reading is what a glance is for, so it leads the accent
                // group when the system recolours the widget.
                .widgetAccentable()
                .lineLimit(1)
                // A three-digit Fahrenheit reading, or a large accessibility
                // text size, must shrink rather than truncate.
                .minimumScaleFactor(0.5)

            Spacer(minLength: 2)

            // Room for the chip first: the reading above it can shrink, and
            // the chip's second line, at large text sizes, cannot.
            detail
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(showsBackground ? 0 : 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenLabel)
        .widgetURL(entry.city.flatMap(CityLink.url))
    }

    /// The tile is deliberately terse; VoiceOver should not be.
    private var spokenLabel: String {
        let name = entry.city?.name ?? "Climyte"
        guard let weather = entry.weather else {
            return String(localized: "\(name), no reading yet")
        }
        let temperature = entry.units.temperatureValue(weather.temperature)
        let reading: String
        if let low = weather.minTemp, let high = weather.maxTemp {
            reading = String(localized: """
                \(name), \(temperature) degrees, \
                low \(entry.units.temperatureValue(low)), \
                high \(entry.units.temperatureValue(high))
                """)
        } else {
            reading = String(localized: "\(name), \(temperature) degrees")
        }

        // The visible "4h" is a duration with no noun attached; spoken, it
        // needs the noun or it is just a number in the middle of a sentence.
        guard let age = entry.shortAge else { return reading }
        return String(localized: "\(reading), from \(age) ago")
    }

    private var temperature: String {
        guard let weather = entry.weather else { return "--" }
        return entry.units.temperature(weather.temperature)
    }

    /// The last line, on a pane of glass. The app's own rule decides whether
    /// rain is worth mentioning, so the widget and the Rain row never
    /// disagree; otherwise the condition and the day's range take it.
    @ViewBuilder
    private var detail: some View {
        if let weather = entry.weather {
            GlassChip(isNight: entry.isNight, isAccented: isAccented) {
                Text(rainLine(weather) ?? summary(weather))
                    .font(.widgetDetail)
                    .foregroundStyle(primary)
                    // A second line rather than an ellipsis: at the largest
                    // text sizes "Rain 100% · 30.2 mm" does not fit on one,
                    // and the amount is the part that was cut.
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        } else {
            Text("Open Climyte")
                .font(.widgetCaption)
                .foregroundStyle(secondary)
        }
    }

    private func summary(_ weather: CityWeather) -> String {
        let condition = weather.conditionDescription(at: entry.date)
        guard let low = weather.minTemp, let high = weather.maxTemp else { return condition }
        return "\(condition) · \(entry.units.temperatureValue(low)) · \(entry.units.temperatureValue(high))"
    }

    private func rainLine(_ weather: CityWeather) -> String? {
        switch WeatherDetails.rainRowLead(weather) {
        case .chance:
            let chance = String(localized: "Rain \(WeatherDetails.percentage(weather.precipitationChance ?? 0))")
            guard let amount = weather.precipitationAmount, amount > 0 else { return chance }
            return "\(chance) · \(entry.units.precipitation(amount))"
        case .amountAhead:
            return String(localized: "Rain \(entry.units.precipitation(weather.precipitationAmount ?? 0))")
        case .nextTwoHours, nil:
            return nil
        }
    }
}
