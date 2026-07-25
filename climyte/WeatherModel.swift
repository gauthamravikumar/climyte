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
    
    var description: String {
        switch self {
        case .sunny: return "Sunny"
        case .cloudy: return "Cloudy"
        case .foggy: return "Foggy"
        case .rainy: return "Rainy"
        case .snowy: return "Snowy"
        case .stormy: return "Stormy"
        }
    }
    
    var iconName: String {
        switch self {
        case .sunny: return "sun.max.fill"
        case .cloudy: return "cloud.sun.fill"
        case .foggy: return "cloud.fog.fill"
        case .rainy: return "cloud.rain.fill"
        case .snowy: return "snowflake"
        case .stormy: return "cloud.bolt.rain.fill"
        }
    }
    
    var backgroundColors: [Color] {
        switch self {
        case .sunny:
            return [Color(hex: "2980B9"), Color(hex: "6DD5FA")] // Bright day gradient
        case .cloudy:
            return [Color(hex: "5C258D"), Color(hex: "4389A2")] // Deep dusk gradient
        case .foggy:
            return [Color(hex: "3A6073"), Color(hex: "3A6073").opacity(0.8)] // Moody mist
        case .rainy:
            return [Color(hex: "1F1C2C"), Color(hex: "928DAB")] // Stormy clouds
        case .snowy:
            return [Color(hex: "757F9A"), Color(hex: "D7DDE8")] // Soft wintry sky
        case .stormy:
            return [Color(hex: "0F2027"), Color(hex: "203A43"), Color(hex: "2C5364")] // Midnight storm
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

// MARK: - App Domain Models
struct City: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let country: String
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
    let isDay: Bool
    let hourlyForecasts: [HourlyForecast]
    
    init(city: City, response: WeatherResponse) {
        self.id = UUID()
        self.city = city
        self.temperature = response.current.temperature_2m
        self.feelsLike = response.current.apparent_temperature
        self.condition = WeatherCondition.from(wmoCode: response.current.weather_code)
        self.isDay = response.current.is_day == 1
        
        let cityTimeZone = TimeZone(secondsFromGMT: response.utc_offset_seconds) ?? TimeZone.current
        var cityCalendar = Calendar.current
        cityCalendar.timeZone = cityTimeZone
        
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        isoFormatter.timeZone = cityTimeZone
        
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
                if date.timeIntervalSince1970 >= currentEpoch - 3600 {
                    let formattedHour = hourFormatter.string(from: date).lowercased()
                    let isTomorrowHour = !cityCalendar.isDateInToday(date)
                    
                    let forecast = HourlyForecast(
                        time: formattedHour,
                        isTomorrow: isTomorrowHour,
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

struct HourlyForecast: Identifiable {
    let id = UUID()
    let time: String // e.g. "11 pm"
    let isTomorrow: Bool
    let condition: WeatherCondition
    let temperature: Double
}

// MARK: - Open-Meteo Geocoding Decodable Structures
struct GeocodingResponse: Decodable {
    let results: [GeocodingResult]?
}

struct GeocodingResult: Decodable, Identifiable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let admin1: String?
}

// MARK: - Open-Meteo Weather Decodable Structures
struct WeatherResponse: Decodable {
    let latitude: Double
    let longitude: Double
    let utc_offset_seconds: Int
    let current: CurrentWeatherResponse
    let hourly: HourlyWeatherResponse
}

struct CurrentWeatherResponse: Decodable {
    let temperature_2m: Double
    let relative_humidity_2m: Double
    let apparent_temperature: Double
    let is_day: Int
    let wind_speed_10m: Double
    let weather_code: Int
}

struct HourlyWeatherResponse: Decodable {
    let time: [String]
    let temperature_2m: [Double]
    let weather_code: [Int]
}
