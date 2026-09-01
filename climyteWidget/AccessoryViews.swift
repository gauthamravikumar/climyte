//
//  AccessoryViews.swift
//  climyteWidget
//

import SwiftUI
import WidgetKit

/// Lock screen accessories.
///
/// These render in the system's vibrant monochrome mode, so the app's day and
/// night palette does not apply — colour is the system's to decide. What
/// carries across is the typography and the same editing-down of content.

struct AccessoryCircularView: View {
    let entry: WeatherEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            // Only the reading fits legibly at this size. A city abbreviation
            // was tried and rejected: any rule for shortening a name is wrong
            // often enough to mislead, and position already distinguishes two
            // circular widgets.
            Text(temperature)
                .font(.accessoryValue)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(4)
        }
        .widgetAccessibilityLabel(entry, detail: false)
    }

    private var temperature: String {
        guard let weather = entry.weather else { return "--" }
        return entry.units.temperature(weather.temperature)
    }
}

struct AccessoryRectangularView: View {
    let entry: WeatherEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(entry.city?.name ?? "Climyte")
                    .font(.accessoryLabel)
                    .widgetAccentable()
                    .lineLimit(1)

                if let age = entry.shortAge {
                    Text(age)
                        .font(.accessoryLabel)
                        .lineLimit(1)
                }
            }

            if let weather = entry.weather {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(entry.units.temperature(weather.temperature))
                        .font(.accessoryValue)
                    Text("\(entry.units.temperatureValue(weather.minTemp)) · \(entry.units.temperatureValue(weather.maxTemp))")
                        .font(.accessoryLabel)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)

                Text(secondLine(weather))
                    .font(.accessoryLabel)
                    .lineLimit(1)
            } else {
                Text("No data yet").font(.accessoryLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetAccessibilityLabel(entry, detail: true)
    }

    private func secondLine(_ weather: CityWeather) -> String {
        if let chance = weather.precipitationChance,
           chance >= WeatherDetails.Threshold.rainChance {
            return String(localized: "Rain \(WeatherDetails.percentage(chance))")
        }
        return weather.condition.description
    }
}

struct AccessoryInlineView: View {
    let entry: WeatherEntry

    /// The system draws this line in its own font and colour — styling it is
    /// pointless. What is ours to control is length, and the space available
    /// varies by device and by what else sits beside the clock. Offering
    /// progressively shorter forms lets the longest that actually fits win,
    /// rather than shipping one string that truncates mid-word on smaller
    /// screens.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(full)
            Text(medium)
            Text(short)
        }
        // Without a label, VoiceOver reads whichever variant the layout
        // happened to pick — so on a narrow lock screen a blind reader hears
        // "6°" while the person beside them reads "Reykjavik 6° · Sunny".
        // What is spoken should not depend on how much room the clock left.
        .accessibilityLabel(spokenLabel)
    }

    private var spokenLabel: String {
        let name = entry.city?.name ?? "Climyte"
        guard let weather = entry.weather else {
            return String(localized: "\(name), no reading yet")
        }

        let reading = entry.units.temperatureValue(weather.temperature)
        let base = String(localized: "\(name), \(reading) degrees, \(weather.condition.description)")
        guard let age = entry.shortAge else { return base }
        return String(localized: "\(base), from \(age) ago")
    }

    private var full: String {
        guard let weather = entry.weather, let city = entry.city else { return short }
        return "\(city.name) \(entry.units.temperature(weather.temperature)) · \(weather.condition.description)"
    }

    private var medium: String {
        guard let weather = entry.weather, let city = entry.city else { return short }
        return "\(city.name) \(entry.units.temperature(weather.temperature))"
    }

    private var short: String {
        guard let weather = entry.weather else { return "Climyte" }
        return entry.units.temperature(weather.temperature)
    }
}

private extension View {
    /// Accessory text is terse by necessity; VoiceOver should not be.
    func widgetAccessibilityLabel(_ entry: WeatherEntry, detail: Bool) -> some View {
        let name = entry.city?.name ?? "Climyte"

        guard let weather = entry.weather else {
            return self.accessibilityLabel(Text("\(name), no data yet"))
        }

        let reading = entry.units.temperatureValue(weather.temperature)

        // The circular accessory has no room to show its age, which makes
        // saying it here the only way a VoiceOver user learns the reading is
        // not current.
        let age = entry.shortAge.map { String(localized: ", from \($0) ago") } ?? ""

        guard detail else {
            return self.accessibilityLabel(Text("\(name), \(reading) degrees\(age)"))
        }

        let low = entry.units.temperatureValue(weather.minTemp)
        let high = entry.units.temperatureValue(weather.maxTemp)
        return self.accessibilityLabel(
            Text("\(name), \(reading) degrees, low \(low), high \(high), \(weather.condition.description)\(age)")
        )
    }
}
