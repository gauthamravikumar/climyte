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

    /// Spoken forms, where the visible text is an abbreviation.
    ///
    /// On screen "UV 4 Mod" and "11h 15m" are exactly right — terse, scannable,
    /// and the section is built around that terseness. Read aloud they become
    /// "UV four mod" and "eleven h fifteen m". These carry the long form for
    /// VoiceOver without lengthening anything a sighted reader sees.
    var spokenValue: String?
    var spokenCaption: String?

    var id: String { kind.rawValue }

    /// The whole row as one sentence.
    var spokenLabel: String {
        let spoken = spokenValue ?? value
        guard let caption = spokenCaption ?? caption else {
            return "\(String(localized: label)), \(spoken)"
        }
        return "\(String(localized: label)), \(spoken), \(caption)"
    }

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
                value: WeatherDetails.uvIndex(weather.uvIndex),
                spokenValue: WeatherDetails.uvIndexSpoken(weather.uvIndex)
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
                caption: weather.daylightChangeSeconds.flatMap(daylightChange),
                spokenValue: durationSpoken(daylight),
                spokenCaption: weather.daylightChangeSeconds.flatMap(daylightChangeSpoken)
            ))
        }

        return details
    }

    private static func rainCaption(for weather: CityWeather, units: UnitSystem) -> String? {
        guard let amount = weather.precipitationAmount, amount > 0 else { return nil }
        guard let hours = weather.precipitationHours, hours >= 1 else {
            return units.precipitation(amount)
        }
        return String(localized: "\(units.precipitation(amount)) over \(hours.toInt(.towardZero))h")
    }

    // MARK: - Formatting
    //
    // These live with the logic rather than on the view that shows them, so
    // the widget can use them without importing the app's view layer.

    nonisolated static func uvIndex(_ value: Double) -> String {
        let category: String
        switch value {
        case ..<2.5: category = String(localized: "Low", comment: "UV index category")
        case ..<5.5: category = String(localized: "Mod", comment: "UV index category, abbreviated 'Moderate'")
        case ..<7.5: category = String(localized: "High", comment: "UV index category")
        case ..<10.5: category = String(localized: "Very High", comment: "UV index category")
        default: category = String(localized: "Extreme", comment: "UV index category")
        }
        return "\(value.toInt()) \(category)"
    }

    /// Beaufort-style description of the wind speed, in km/h.
    nonisolated static func windDescription(_ speed: Double) -> LocalizedStringResource {
        switch speed {
        case ..<5: return "Light air"
        case 5..<12: return "Light breeze"
        case 12..<20: return "Gentle breeze"
        case 20..<29: return "Moderate breeze"
        case 29..<39: return "Fresh breeze"
        case 39..<50: return "Strong breeze"
        default: return "High wind"
        }
    }

    /// "4, Moderate" rather than "4 Mod", which VoiceOver reads as "mod".
    nonisolated static func uvIndexSpoken(_ value: Double) -> String {
        let category: String
        switch value {
        case ..<2.5: category = String(localized: "Low", comment: "UV index category")
        case ..<5.5: category = String(localized: "Moderate", comment: "UV index category, spoken")
        case ..<7.5: category = String(localized: "High", comment: "UV index category")
        case ..<10.5: category = String(localized: "Very High", comment: "UV index category")
        default: category = String(localized: "Extreme", comment: "UV index category")
        }
        return "\(value.toInt()), \(category)"
    }

    /// "11 hours 15 minutes" rather than "11h 15m".
    nonisolated static func durationSpoken(_ seconds: Double) -> String {
        let total = seconds.toInt()
        let style = Duration.seconds(total).formatted(
            .units(allowed: [.hours, .minutes], width: .wide)
        )
        return style
    }

    /// "2 minutes shorter" rather than "2m shorter".
    nonisolated static func daylightChangeSpoken(_ seconds: Double) -> String? {
        let minutes = (seconds / 60).toInt()
        guard minutes != 0 else { return nil }

        let magnitude = Duration.seconds(abs(minutes) * 60)
            .formatted(.units(allowed: [.minutes], width: .wide))
        return minutes > 0
            ? String(localized: "\(magnitude) longer")
            : String(localized: "\(magnitude) shorter")
    }

    nonisolated static func duration(_ seconds: Double) -> String {
        let total = seconds.toInt()
        return "\(total / 3600)h \((total % 3600) / 60)m"
    }

    /// Under a minute either way is not worth reporting as a change.
    nonisolated static func daylightChange(_ seconds: Double) -> String? {
        let minutes = (seconds / 60).toInt()
        guard minutes != 0 else { return nil }
        return minutes > 0
            ? String(localized: "\(minutes)m longer")
            : String(localized: "\(-minutes)m shorter")
    }
}
