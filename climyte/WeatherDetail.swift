//
//  WeatherDetail.swift
//  climyte
//

import Foundation

/// One line in the details section.
///
/// The set is not fixed: a detail appears only when it has something to say,
/// so a still, clear night shows fewer lines than a wet and windy afternoon.
struct WeatherDetail: Identifiable, Equatable {
    enum Kind: String {
        case rain, visibility, uv, humidity, wind, sunrise, sunset, daylight
    }

    let kind: Kind
    let label: LocalizedStringResource
    let value: String
    var caption: String?

    var id: String { kind.rawValue }

    static func == (lhs: WeatherDetail, rhs: WeatherDetail) -> Bool {
        lhs.kind == rhs.kind && lhs.value == rhs.value && lhs.caption == rhs.caption
    }
}

enum WeatherDetails {

    /// Thresholds, named so the reasoning is visible at the call site.
    enum Threshold {
        /// Below this, a chance of rain is noise rather than news.
        static let rainChance = 20
        /// The WHO advises sun protection from UV 3.
        static let uvIndex = 3.0
        /// Visibility is only worth a line when it is actually reduced.
        static let poorVisibilityKilometres = 5.0
        /// Dew point, not relative humidity: 85% at 11°C is cool and damp,
        /// not muggy, while 51% at 33°C genuinely is oppressive.
        static let humidDewPointCelsius = 16.0
        static let dryDewPointCelsius = 2.0
        /// Gusts only earn a mention when they exceed the average enough to
        /// change how the day feels.
        static let gustExcessKilometresPerHour = 15.0
    }

    /// Builds the visible details, most notable first.
    ///
    /// Conditional entries lead because their presence is itself the signal;
    /// the always-present ones follow in a stable order so the section does
    /// not reshuffle on every refresh.
    static func build(for weather: CityWeather, units: UnitSystem) -> [WeatherDetail] {
        var details: [WeatherDetail] = []

        if let chance = weather.precipitationChance, chance >= Threshold.rainChance {
            details.append(WeatherDetail(
                kind: .rain,
                label: "Rain",
                value: "\(chance)%",
                caption: rainCaption(for: weather, units: units)
            ))
        }

        if weather.visibility < Threshold.poorVisibilityKilometres {
            details.append(WeatherDetail(
                kind: .visibility,
                label: "Visibility",
                value: units.visibility(weather.visibility)
            ))
        }

        if !weather.isNight && weather.uvIndex >= Threshold.uvIndex {
            details.append(WeatherDetail(
                kind: .uv,
                label: "UV",
                value: WeatherDetailsView.uvIndex(weather.uvIndex)
            ))
        }

        if weather.dewPoint >= Threshold.humidDewPointCelsius {
            details.append(WeatherDetail(
                kind: .humidity,
                label: "Humid",
                value: String(localized: "dew point \(units.temperature(weather.dewPoint))")
            ))
        } else if weather.dewPoint <= Threshold.dryDewPointCelsius {
            details.append(WeatherDetail(
                kind: .humidity,
                label: "Dry",
                value: String(localized: "dew point \(units.temperature(weather.dewPoint))")
            ))
        }

        details.append(WeatherDetail(
            kind: .wind,
            label: "Wind",
            value: units.windSpeed(weather.windSpeed),
            caption: weather.windGusts - weather.windSpeed >= Threshold.gustExcessKilometresPerHour
                ? String(localized: "gusts \(units.windSpeed(weather.windGusts))")
                : nil
        ))

        details.append(WeatherDetail(kind: .sunrise, label: "Sunrise", value: weather.sunriseFormatted))
        details.append(WeatherDetail(kind: .sunset, label: "Sunset", value: weather.sunsetFormatted))

        if let daylight = weather.daylightSeconds {
            details.append(WeatherDetail(
                kind: .daylight,
                label: "Daylight",
                value: duration(daylight),
                caption: weather.daylightChangeSeconds.flatMap(daylightChange)
            ))
        }

        return details
    }

    private static func rainCaption(for weather: CityWeather, units: UnitSystem) -> String? {
        guard let amount = weather.precipitationAmount, amount > 0 else { return nil }
        guard let hours = weather.precipitationHours, hours >= 1 else {
            return units.precipitation(amount)
        }
        return String(localized: "\(units.precipitation(amount)) over \(Int(hours))h")
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return "\(total / 3600)h \((total % 3600) / 60)m"
    }

    /// Under a minute either way is not worth reporting as a change.
    static func daylightChange(_ seconds: Double) -> String? {
        let minutes = Int((seconds / 60).rounded())
        guard minutes != 0 else { return nil }
        return minutes > 0
            ? String(localized: "\(minutes)m longer")
            : String(localized: "\(-minutes)m shorter")
    }
}
