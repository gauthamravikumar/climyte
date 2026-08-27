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

// MARK: - App Domain Models
struct City: Identifiable, Codable, Equatable {
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

struct CityWeather: Identifiable {
    let id: UUID
    let city: City
    let temperature: Double
    let feelsLike: Double
    let condition: WeatherCondition
    let hourlyForecasts: [HourlyForecast]
    let utcOffsetSeconds: Int
    let isNight: Bool
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
    
    init(city: City, response: WeatherResponse) {
        self.id = UUID()
        self.city = city
        self.response = response
        self.temperature = response.current.temperature_2m
        self.feelsLike = response.current.apparent_temperature
        self.condition = WeatherCondition.from(wmoCode: response.current.weather_code)
        self.utcOffsetSeconds = response.utc_offset_seconds
        
        let cityTimeZone = TimeZone(secondsFromGMT: response.utc_offset_seconds) ?? TimeZone.current
        var cityCalendar = Calendar.current
        cityCalendar.timeZone = cityTimeZone
        
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        isoFormatter.timeZone = cityTimeZone
        
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"
        dayFormatter.timeZone = cityTimeZone
        
        let dateParser = DateFormatter()
        dateParser.dateFormat = "yyyy-MM-dd"
        dateParser.timeZone = cityTimeZone
        
        // The request asks for one past day so day length can be compared with
        // yesterday, which means index 0 is *yesterday*, not today. Find today
        // by date rather than assuming a position — that stays correct however
        // many past days are requested.
        let todayKey = dateParser.string(from: Date())
        let todayIndex = response.daily.time.firstIndex(of: todayKey) ?? 0

        var dailyList: [DailyForecast] = []
        let dailyCount = min(response.daily.time.count, response.daily.weather_code.count, response.daily.temperature_2m_max.count, response.daily.temperature_2m_min.count)
        
        for i in todayIndex..<dailyCount {
            let dateStr = response.daily.time[i]
            var dayLabel = dateStr
            if let date = dateParser.date(from: dateStr) {
                dayLabel = cityCalendar.isDateInToday(date)
                    ? String(localized: "Today", comment: "Row label for today in the weekly forecast")
                    : dayFormatter.string(from: date)
            }
            
            let forecast = DailyForecast(
                id: dateStr,
                day: dayLabel,
                condition: WeatherCondition.from(wmoCode: response.daily.weather_code[i]),
                minTemp: response.daily.temperature_2m_min[i],
                maxTemp: response.daily.temperature_2m_max[i]
            )
            dailyList.append(forecast)
        }
        self.dailyForecasts = dailyList
        self.maxTemp = response.daily.temperature_2m_max[safe: todayIndex] ?? response.current.temperature_2m
        self.minTemp = response.daily.temperature_2m_min[safe: todayIndex] ?? response.current.temperature_2m
        
        self.humidity = Int(response.current.relative_humidity_2m)
        self.dewPoint = response.current.dew_point_2m
        self.windGusts = response.current.wind_gusts_10m

        self.precipitationChance = response.daily.precipitation_probability_max[safe: todayIndex] ?? nil
        self.precipitationAmount = response.daily.precipitation_sum[safe: todayIndex] ?? nil
        self.precipitationHours = response.daily.precipitation_hours[safe: todayIndex] ?? nil

        let daylightToday = response.daily.daylight_duration[safe: todayIndex] ?? nil
        self.daylightSeconds = daylightToday
        if let daylightToday,
           todayIndex > 0,
           let yesterday = response.daily.daylight_duration[safe: todayIndex - 1] ?? nil {
            self.daylightChangeSeconds = daylightToday - yesterday
        } else {
            self.daylightChangeSeconds = nil
        }
        self.windSpeed = response.current.wind_speed_10m
        self.uvIndex = response.daily.uv_index_max[safe: todayIndex] ?? 0.0
        self.visibility = response.current.visibility / 1000.0
        
        let sunTimeFormatter = DateFormatter()
        sunTimeFormatter.dateFormat = "h:mm a"
        sunTimeFormatter.timeZone = cityTimeZone
        
        if let sunriseStr = response.daily.sunrise[safe: todayIndex],
           let sunriseDate = isoFormatter.date(from: sunriseStr) {
            self.sunriseFormatted = sunTimeFormatter.string(from: sunriseDate).lowercased()
        } else {
            self.sunriseFormatted = "--"
        }
        
        if let sunsetStr = response.daily.sunset[safe: todayIndex],
           let sunsetDate = isoFormatter.date(from: sunsetStr) {
            self.sunsetFormatted = sunTimeFormatter.string(from: sunsetDate).lowercased()
        } else {
            self.sunsetFormatted = "--"
        }
        
        let now = Date()
        if let sunriseStr = response.daily.sunrise[safe: todayIndex],
           let sunsetStr = response.daily.sunset[safe: todayIndex],
           let sunriseDate = isoFormatter.date(from: sunriseStr),
           let sunsetDate = isoFormatter.date(from: sunsetStr) {
            self.isNight = now < sunriseDate || now > sunsetDate
        } else {
            self.isNight = response.current.is_day == 0
        }
        
        let hourFormatter = DateFormatter()
        hourFormatter.dateFormat = "h a"
        hourFormatter.timeZone = cityTimeZone
        
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
                    let formattedHour = hourFormatter.string(from: date).lowercased()

                    let forecast = HourlyForecast(
                        id: timeString,
                        time: formattedHour,
                        condition: WeatherCondition.from(wmoCode: response.hourly.weather_code[i]),
                        temperature: response.hourly.temperature_2m[i]
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
struct GeocodingResponse: Decodable {
    let results: [GeocodingResult]?
}

struct GeocodingResult: Decodable, Identifiable, Equatable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let country_code: String?
    let admin1: String?
}

// MARK: - Open-Meteo Weather Decodable Structures
struct WeatherResponse: Codable {
    let latitude: Double
    let longitude: Double
    let utc_offset_seconds: Int
    let current: CurrentWeatherResponse
    let hourly: HourlyWeatherResponse
    let daily: DailyWeatherResponse
}

struct CurrentWeatherResponse: Codable {
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

struct HourlyWeatherResponse: Codable {
    let time: [String]
    let temperature_2m: [Double]
    let weather_code: [Int]
}

struct DailyWeatherResponse: Codable {
    let time: [String]
    let weather_code: [Int]
    let temperature_2m_max: [Double]
    let temperature_2m_min: [Double]
    let sunrise: [String]
    let sunset: [String]
    let uv_index_max: [Double]

    /// Open-Meteo returns null for these beyond its probability horizon, so
    /// the elements are optional; a non-optional array fails the whole decode.
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
    
    static func forIsNight(_ isNight: Bool) -> WeatherTheme {
        if isNight {
            return WeatherTheme(
                background: Color(hex: "0E0F13"),
                primaryText: Color(hex: "F2F2F0"),
                secondaryText: Color(hex: "727272"),
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
