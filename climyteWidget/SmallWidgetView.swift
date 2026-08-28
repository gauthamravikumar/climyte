//
//  SmallWidgetView.swift
//  climyteWidget
//

import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let entry: WeatherEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.city?.name ?? "Climyte")
                .font(.widgetCity)
                .foregroundStyle(entry.theme.primaryText)
                .lineLimit(1)

            Spacer(minLength: 2)

            Text(temperature)
                .font(.widgetTemperature)
                .foregroundStyle(entry.theme.primaryText)
                .lineLimit(1)
                // A three-digit Fahrenheit reading, or a large accessibility
                // text size, must shrink rather than truncate.
                .minimumScaleFactor(0.5)

            Spacer(minLength: 2)

            detail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var temperature: String {
        guard let weather = entry.weather else { return "--" }
        return entry.units.temperature(weather.temperature)
    }

    @ViewBuilder
    private var detail: some View {
        if let weather = entry.weather {
            VStack(alignment: .leading, spacing: 1) {
                Divider().overlay(entry.theme.dividerColor)
                    .padding(.bottom, 4)

                // Same rule as the app's details section: rain earns the line
                // when it is likely, otherwise the day's range does.
                if let chance = weather.precipitationChance,
                   chance >= WeatherDetails.Threshold.rainChance {
                    Text(rainLine(chance: chance, weather: weather))
                        .font(.widgetDetail)
                        .foregroundStyle(entry.theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("\(entry.units.temperatureValue(weather.minTemp)) · \(entry.units.temperatureValue(weather.maxTemp))")
                        .font(.widgetDetail)
                        .foregroundStyle(entry.theme.primaryText)
                        .lineLimit(1)
                }
            }
        } else {
            Text("No data yet")
                .font(.widgetCaption)
                .foregroundStyle(entry.theme.secondaryText)
        }
    }

    private func rainLine(chance: Int, weather: CityWeather) -> String {
        guard let amount = weather.precipitationAmount, amount > 0 else {
            return String(localized: "Rain \(chance)%")
        }
        return "\(String(localized: "Rain \(chance)%")) · \(entry.units.precipitation(amount))"
    }
}
