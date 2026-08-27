//
//  CurrentConditionsView.swift
//  climyte
//

import SwiftUI

struct CurrentConditionsView: View {
    let weather: CityWeather
    let theme: WeatherTheme
    let isUsingCurrentLocation: Bool

    @Environment(\.unitSystem) private var units

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            temperature
            summary
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 8) {
                if isUsingCurrentLocation {
                    Image(systemName: "location.fill")
                        .font(.system(size: 14))
                        .foregroundColor(theme.primaryText.opacity(0.8))
                        .accessibilityLabel("Current location")
                }

                Text(weather.city.name)
                    .font(.cityName)
                    .foregroundColor(theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            Spacer(minLength: 8)

            // Re-renders every minute so the city's local time stays honest.
            TimelineView(.everyMinute) { context in
                Text(Self.localTime(at: context.date, utcOffsetSeconds: weather.utcOffsetSeconds))
                    .font(.localTime)
                    .foregroundColor(theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
                    .accessibilityLabel("Local time in \(weather.city.name)")
            }
        }
    }

    private var temperature: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(units.temperature(weather.temperature))
                .font(.temperatureHero)
                .foregroundColor(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            // The day's range, set as a span rather than two labelled values.
            // Only the reading itself carries a degree sign; these inherit it.
            Text("\(units.temperatureValue(weather.minTemp))  ·  \(units.temperatureValue(weather.maxTemp))")
                .font(.temperatureRange)
                .foregroundColor(theme.secondaryText)
                .padding(.leading, 4)
        }
        .padding(.vertical, -10)
        .accessibilityElement(children: .combine)
        // Terse on screen, explicit to VoiceOver — the visual shorthand
        // shouldn't cost a screen-reader user the meaning.
        .accessibilityLabel(
            """
            \(units.temperatureValue(weather.temperature)) degrees, \
            low \(units.temperatureValue(weather.minTemp)), \
            high \(units.temperatureValue(weather.maxTemp))
            """
        )
    }

    private var summary: some View {
        Text("\(weather.condition.description) · feels like \(units.temperature(weather.feelsLike))")
            .font(.conditionSummary)
            .foregroundColor(theme.secondaryText)
    }

    // MARK: - Formatting

    /// Renders `date` in the city's timezone. `.shortened` picks up the
    /// reader's locale, so 12h/24h follows their device rather than a
    /// hardcoded format that dropped am/pm entirely.
    static func localTime(at date: Date, utcOffsetSeconds: Int) -> String {
        let timeZone = TimeZone(secondsFromGMT: utcOffsetSeconds) ?? .current
        return date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)
        )
    }
}
