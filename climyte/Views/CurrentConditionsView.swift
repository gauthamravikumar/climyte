//
//  CurrentConditionsView.swift
//  climyte
//

import SwiftUI

struct CurrentConditionsView: View {
    let weather: CityWeather
    let theme: WeatherTheme
    let isUsingCurrentLocation: Bool

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
        HStack(alignment: .center, spacing: 16) {
            Text(Self.degrees(weather.temperature))
                .font(.temperatureHero)
                .foregroundColor(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityLabel("\(Int(weather.temperature.rounded())) degrees")

            VStack(alignment: .leading, spacing: 4) {
                Text("H:\(Self.degrees(weather.maxTemp))")
                Text("L:\(Self.degrees(weather.minTemp))")
            }
            .font(.highLow)
            .foregroundColor(theme.secondaryText)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "High \(Int(weather.maxTemp.rounded())), low \(Int(weather.minTemp.rounded())) degrees"
            )
        }
        .padding(.vertical, -10)
    }

    private var summary: some View {
        Text("\(weather.condition.description) · feels like \(Self.degrees(weather.feelsLike))")
            .font(.conditionSummary)
            .foregroundColor(theme.secondaryText)
    }

    // MARK: - Formatting

    static func degrees(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }

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
