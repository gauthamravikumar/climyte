//
//  WeatherModel.swift
//  climyte
//
//  Created by Antigravity on 23/7/2026.
//

import Foundation
import SwiftUI

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Weather Condition
enum WeatherCondition: String, Codable {
    case sunny
    case cloudy
    case foggy
    case rainy
    case snowy
    case stormy
    
    /// Shown to the user, so localized rather than the raw case name.
    var description: String {
        switch self {
        case .sunny: return String(localized: "Sunny", comment: "Weather condition")
        case .cloudy: return String(localized: "Cloudy", comment: "Weather condition")
        case .foggy: return String(localized: "Foggy", comment: "Weather condition")
        case .rainy: return String(localized: "Rainy", comment: "Weather condition")
        case .snowy: return String(localized: "Snowy", comment: "Weather condition")
        case .stormy: return String(localized: "Stormy", comment: "Weather condition")
        }
    }
    
    static func from(wmoCode: Int) -> WeatherCondition {
        switch wmoCode {
        case 0, 1:
            return .sunny
        case 2, 3:
            return .cloudy
        case 45, 48:
            return .foggy
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82:
            return .rainy
        case 71, 73, 75, 77, 85, 86:
            return .snowy
        case 95, 96, 99:
            return .stormy
        default:
            return .sunny
        }
    }
}

extension Array {
    /// Index access that returns nil rather than trapping. The daily arrays are
    /// parallel but the API does not guarantee they are the same length.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Array {
    /// Bounds-checked access to an array of optionals, flattening the double
    /// optional that `self[safe:]` would otherwise produce.
    func value<T>(at index: Int) -> T? where Element == T? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - App Domain Models
nonisolated struct City: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let country: String

    /// ISO 3166-1 alpha-2, used to pick the city's units. Optional because
    /// cities saved before this existed decode without one.
    var countryCode: String?

    let latitude: Double
    let longitude: Double
    
    static func == (lhs: City, rhs: City) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

/// Sunrise and sunset for one day, as instants rather than display strings.
nonisolated struct SolarDay {
    let sunrise: Date
    let sunset: Date
}

struct CityWeather: Identifiable {
    let id: UUID
    let city: City
    let temperature: Double
    let feelsLike: Double
    let condition: WeatherCondition
    let hourlyForecasts: [HourlyForecast]
    let utcOffsetSeconds: Int

    /// Sunrise and sunset for every day the response covers, in order.
    ///
    /// Kept as dates rather than the formatted strings alongside them, because
    /// the widget renders entries scheduled hours after the fetch that
    /// produced them and has to ask whether it is night *then*, not now.
    let solarDays: [SolarDay]
    let dailyForecasts: [DailyForecast]
    let maxTemp: Double
    let minTemp: Double
    let humidity: Int
    let windSpeed: Double
    let uvIndex: Double
    let sunriseFormatted: String
    let sunsetFormatted: String
    let visibility: Double

    let dewPoint: Double
    let windGusts: Double

    /// Chance of precipitation today, 0-100. Nil when the API has no
    /// probability for the day.
    let precipitationChance: Int?
    let precipitationAmount: Double?
    let precipitationHours: Double?

    let daylightSeconds: Double?
    /// Today's daylight minus yesterday's. Nil when yesterday is unavailable.
    let daylightChangeSeconds: Double?

    /// The response this was built from, retained so a successful fetch can be
    /// written to the cache and rebuilt later without a second parse.
    let response: WeatherResponse

    var theme: WeatherTheme {
        WeatherTheme.forIsNight(isNight)
    }

    /// Whether it is night in this city right now.
    var isNight: Bool { isNight(at: Date()) }

    /// Whether it is night in this city at `date`.
    ///
    /// Locates the day `date` actually falls in rather than assuming today's
    /// pair. Comparing a 5am entry against *today's* sunset would call every
    /// hour after this evening night, straight through tomorrow's morning.
    func isNight(at date: Date) -> Bool {
        guard !solarDays.isEmpty else {
            // No parseable sun times; the reading's own daylight flag is all
            // that is left, and it can only speak for when it was fetched.
            return response.current.is_day == 0
        }

        // The most recent sunrise on or before `date`. Nothing matching means
        // `date` precedes every sunrise the response covers, which is night.
        guard let day = solarDays.last(where: { $0.sunrise <= date }) else {
            return true
        }
        return date > day.sunset
    }
    
    /// A formatter for the API's own date strings.
    ///
    /// `en_US_POSIX` is the point. A bare DateFormatter inherits
    /// `Locale.current`, including its calendar — so on a device whose Region
    /// is Thailand, `string(from: Date())` yields the Buddhist year 2569 and
    /// `date(from: "2026-08-31T06:00")` reads 2026 as a Buddhist year and
    /// returns 1483. Neither then matches anything the API sent. This is a
    /// Region setting, not a language one: it fires for an English-speaking
    /// reader who has simply chosen a different region.
    private static func apiFormatter(_ format: String, in timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        formatter.timeZone = timeZone
        return formatter
    }

    init(city: City, response: WeatherResponse) {
        self.id = UUID()
        self.city = city
        self.response = response
        self.temperature = response.current.temperature_2m
        self.feelsLike = response.current.apparent_temperature
        self.condition = WeatherCondition.from(wmoCode: response.current.weather_code)
        self.utcOffsetSeconds = response.utc_offset_seconds
        
        let cityTimeZone = TimeZone(secondsFromGMT: response.utc_offset_seconds) ?? TimeZone.current

        // Gregorian explicitly, not Calendar.current. A reader whose Region is
        // Thailand or Saudi Arabia has a Buddhist or Hijri calendar, and every
        // date here is a Gregorian one the API sent us.
        var cityCalendar = Calendar(identifier: .gregorian)
        cityCalendar.timeZone = cityTimeZone

        let isoFormatter = Self.apiFormatter("yyyy-MM-dd'T'HH:mm", in: cityTimeZone)
        let dateParser = Self.apiFormatter("yyyy-MM-dd", in: cityTimeZone)

        // Day names are for reading, so this one follows the reader's locale.
        // Its calendar is still pinned: weekday names are the same either way,
        // but nothing here should depend on which calendar happens to be set.
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"
        dayFormatter.timeZone = cityTimeZone
        dayFormatter.calendar = cityCalendar
        
        // The request asks for one past day so day length can be compared with
        // yesterday, which means index 0 is *yesterday*, not today. Find today
        // by date rather than assuming a position — that stays correct however
        // many past days are requested.
        // Dates are yyyy-MM-dd so they compare lexicographically. If today is
        // not present, take the first day at or after it — falling back to
        // index 0 would silently render yesterday as today, which looks
        // entirely plausible and is wrong.
        let todayKey = dateParser.string(from: Date())
        let todayIndex = response.daily.time.firstIndex(of: todayKey)
            ?? response.daily.time.firstIndex { $0 >= todayKey }
            ?? max(response.daily.time.count - 1, 0)

        var dailyList: [DailyForecast] = []
        let dailyCount = min(response.daily.time.count, response.daily.weather_code.count, response.daily.temperature_2m_max.count, response.daily.temperature_2m_min.count)
        
        // Clamped: mismatched array lengths can put todayIndex past dailyCount,
        // and `todayIndex..<dailyCount` traps when the range is reversed.
        for i in min(todayIndex, dailyCount)..<dailyCount {
            let dateStr = response.daily.time[i]

            // Drop a day the API has no readings for rather than charting a
            // zero, which would put a false trough in the week's ribbon.
            guard let code: Int = response.daily.weather_code.value(at: i),
                  let low: Double = response.daily.temperature_2m_min.value(at: i),
                  let high: Double = response.daily.temperature_2m_max.value(at: i) else { continue }

            var dayLabel = dateStr
            if let date = dateParser.date(from: dateStr) {
                dayLabel = cityCalendar.isDateInToday(date)
                    ? String(localized: "Today", comment: "Row label for today in the weekly forecast")
                    : dayFormatter.string(from: date)
            }

            let forecast = DailyForecast(
                id: dateStr,
                day: dayLabel,
                condition: WeatherCondition.from(wmoCode: code),
                minTemp: low,
                maxTemp: high
            )
            dailyList.append(forecast)
        }
        self.dailyForecasts = dailyList
        self.maxTemp = response.daily.temperature_2m_max.value(at: todayIndex) ?? response.current.temperature_2m
        self.minTemp = response.daily.temperature_2m_min.value(at: todayIndex) ?? response.current.temperature_2m
        
        self.humidity = response.current.relative_humidity_2m.toInt(.towardZero)
        self.dewPoint = response.current.dew_point_2m
        self.windGusts = response.current.wind_gusts_10m

        self.precipitationChance = response.daily.precipitation_probability_max.value(at: todayIndex)
        self.precipitationAmount = response.daily.precipitation_sum.value(at: todayIndex)
        self.precipitationHours = response.daily.precipitation_hours.value(at: todayIndex)

        let daylightToday: Double? = response.daily.daylight_duration.value(at: todayIndex)
        self.daylightSeconds = daylightToday
        if let daylightToday,
           todayIndex > 0,
           let yesterday: Double = response.daily.daylight_duration.value(at: todayIndex - 1) {
            self.daylightChangeSeconds = daylightToday - yesterday
        } else {
            self.daylightChangeSeconds = nil
        }
        self.windSpeed = response.current.wind_speed_10m
        self.uvIndex = response.daily.uv_index_max.value(at: todayIndex) ?? 0.0
        self.visibility = response.current.visibility / 1000.0
        
        // `.shortened` rather than a hardcoded "h:mm a": the header clock in
        // CurrentConditionsView already honours the reader's 12/24-hour
        // setting, and a screen showing "4:13" beside "6:00 am" is showing two
        // different clocks.
        let sunTimeStyle = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: cityTimeZone)
        
        if let sunriseStr: String = response.daily.sunrise.value(at: todayIndex),
           let sunriseDate = isoFormatter.date(from: sunriseStr) {
            self.sunriseFormatted = sunriseDate.formatted(sunTimeStyle).lowercased()
        } else {
            self.sunriseFormatted = "--"
        }
        
        if let sunsetStr: String = response.daily.sunset.value(at: todayIndex),
           let sunsetDate = isoFormatter.date(from: sunsetStr) {
            self.sunsetFormatted = sunsetDate.formatted(sunTimeStyle).lowercased()
        } else {
            self.sunsetFormatted = "--"
        }
        
        // Every day the response covers, not just today: an entry rendered
        // after midnight has to be judged against that day's own sunrise.
        self.solarDays = zip(response.daily.sunrise, response.daily.sunset)
            .compactMap { sunrise, sunset in
                guard let sunrise, let sunset,
                      let sunriseDate = isoFormatter.date(from: sunrise),
                      let sunsetDate = isoFormatter.date(from: sunset) else { return nil }
                return SolarDay(sunrise: sunriseDate, sunset: sunsetDate)
            }
        
        // Same reasoning: "2 pm" for a 12-hour reader, "14" for a 24-hour one.
        let hourStyle = Date.FormatStyle(timeZone: cityTimeZone)
            .hour(.defaultDigits(amPM: .abbreviated))
        
        var hourlyList: [HourlyForecast] = []
        let currentEpoch = Date().timeIntervalSince1970
        let hourCount = min(response.hourly.time.count, response.hourly.temperature_2m.count, response.hourly.weather_code.count)
        var parsedHours = 0
        
        for i in 0..<hourCount {
            guard parsedHours < 24 else { break }
            let timeString = response.hourly.time[i]
            
            if let date = isoFormatter.date(from: timeString) {
                // Keep only current and future hours (within a 24h window)
                // Subtract 3600s (1h) so the user gets context of the current ongoing hour
                if date.timeIntervalSince1970 >= currentEpoch - 3600 {
                    // A null hour is skipped, not fatal: the rest of the day
                    // is still worth showing.
                    guard let temperature: Double = response.hourly.temperature_2m.value(at: i),
                          let code: Int = response.hourly.weather_code.value(at: i) else { continue }

                    let forecast = HourlyForecast(
                        id: timeString,
                        time: date.formatted(hourStyle).lowercased(),
                        condition: WeatherCondition.from(wmoCode: code),
                        temperature: temperature
                    )
                    hourlyList.append(forecast)
                    parsedHours += 1
                }
            }
        }
        self.hourlyForecasts = hourlyList
    }
}

/// `id` is the raw API timestamp rather than a fresh UUID, so the same hour
/// keeps its identity across refreshes and SwiftUI animates the value change
/// instead of rebuilding every row.
struct HourlyForecast: Identifiable {
    let id: String   // e.g. "2026-07-25T23:00"
    let time: String // e.g. "11 pm"
    let condition: WeatherCondition
    let temperature: Double
}

struct DailyForecast: Identifiable {
    let id: String  // e.g. "2026-07-25"
    let day: String // e.g. "Today", "Wed"
    let condition: WeatherCondition
    let minTemp: Double
    let maxTemp: Double
}

// MARK: - Open-Meteo Geocoding Decodable Structures
nonisolated struct GeocodingResponse: Decodable {
    let results: [GeocodingResult]?
}

nonisolated struct GeocodingResult: Decodable, Identifiable, Equatable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let country_code: String?
    let admin1: String?
}

// MARK: - Open-Meteo Weather Decodable Structures
nonisolated struct WeatherResponse: Codable {
    let latitude: Double
    let longitude: Double
    let utc_offset_seconds: Int
    let current: CurrentWeatherResponse
    let hourly: HourlyWeatherResponse
    let daily: DailyWeatherResponse
}

nonisolated struct CurrentWeatherResponse: Codable {
    let temperature_2m: Double
    let apparent_temperature: Double
    let is_day: Int
    let weather_code: Int
    let relative_humidity_2m: Double
    let dew_point_2m: Double
    let wind_speed_10m: Double
    let wind_gusts_10m: Double
    let visibility: Double
}

nonisolated struct HourlyWeatherResponse: Codable {
    let time: [String]

    /// Optional for the same reason the daily arrays are: Open-Meteo sends
    /// null past the horizon of the model backing a field, and one null in a
    /// non-optional array fails the whole decode. That asymmetry meant a
    /// single missing hour cost the reader the entire city — temperature,
    /// forecast and all — reported as "Couldn't read the weather data".
    let temperature_2m: [Double?]
    let weather_code: [Int?]
}

nonisolated struct DailyWeatherResponse: Codable {
    let time: [String]

    /// Every value here is optional because Open-Meteo sends null past the
    /// horizon of the model backing it, and a single null in a non-optional
    /// array fails the entire decode — blanking the city rather than the one
    /// day that is missing.
    let weather_code: [Int?]
    let temperature_2m_max: [Double?]
    let temperature_2m_min: [Double?]
    let sunrise: [String?]
    let sunset: [String?]
    let uv_index_max: [Double?]
    let precipitation_probability_max: [Int?]
    let precipitation_sum: [Double?]
    let precipitation_hours: [Double?]
    let daylight_duration: [Double?]
}

struct WeatherTheme {
    let background: Color
    let primaryText: Color
    let secondaryText: Color
    let dividerColor: Color
    
    /// Secondary text is a different grey in each theme, on purpose.
    ///
    /// One value cannot serve both: #727272 was picked against white, where it
    /// measures 4.81:1, and reused unchanged when the palette inverted, where
    /// it measures 3.98:1 — under the 4.5:1 that normal text needs, and 11 of
    /// the 13 styles using it are normal-sized. #808080 restores the contrast
    /// night should always have had, at 4.85:1, without lightening it so far
    /// that the supporting text competes with the reading it supports.
    static func forIsNight(_ isNight: Bool) -> WeatherTheme {
        if isNight {
            return WeatherTheme(
                background: Color(hex: "0E0F13"),
                primaryText: Color(hex: "F2F2F0"),
                secondaryText: Color(hex: "808080"),
                dividerColor: Color(hex: "F2F2F0").opacity(0.12)
            )
        } else {
            return WeatherTheme(
                background: Color(hex: "FFFFFF"),
                primaryText: Color(hex: "1A1A1A"),
                secondaryText: Color(hex: "727272"),
                dividerColor: Color(hex: "1A1A1A").opacity(0.12)
            )
        }
    }
}
