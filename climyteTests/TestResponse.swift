//
//  TestResponse.swift
//  climyteTests
//

import Foundation
@testable import climyte

/// Builds Open-Meteo responses for tests.
///
/// Everything is in UTC and the daily arrays carry yesterday at index 0 and
/// today at index 1, mirroring the real request's `past_days=1` — so tests
/// exercise the same index-finding the app does rather than a simpler shape.
enum TestResponse {

    static func make(
        temperature: Double = 20,
        apparent: Double = 20,
        isDay: Int = 1,
        weatherCode: Int = 0,
        humidity: Double = 60,
        dewPoint: Double = 10,
        windSpeed: Double = 10,
        windGusts: Double = 12,
        visibilityMetres: Double = 20_000,
        uvIndex: Double = 0,
        rainChance: Int? = 0,
        rainAmount: Double? = 0,
        rainHours: Double? = 0,
        daylightToday: Double? = 49_993,
        daylightYesterday: Double? = 50_233,
        maxTemp: Double = 26,
        minTemp: Double = 15,
        hourly: HourlyWeatherResponse? = nil
    ) -> WeatherResponse {
        let utc = TimeZone(secondsFromGMT: 0)!

        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.timeZone = utc

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd'T'HH:mm"
        stamp.timeZone = utc

        let now = Date()
        let yesterday = now.addingTimeInterval(-86_400)

        // Put the sun either side of now, or both behind it, so the derived
        // isNight matches what the caller asked for.
        let sunrise = now.addingTimeInterval(isDay == 1 ? -3_600 : -7_200)
        let sunset = now.addingTimeInterval(isDay == 1 ? 3_600 : -3_600)

        return WeatherResponse(
            latitude: 0,
            longitude: 0,
            utc_offset_seconds: 0,
            current: CurrentWeatherResponse(
                temperature_2m: temperature,
                apparent_temperature: apparent,
                is_day: isDay,
                weather_code: weatherCode,
                relative_humidity_2m: humidity,
                dew_point_2m: dewPoint,
                wind_speed_10m: windSpeed,
                wind_gusts_10m: windGusts,
                visibility: visibilityMetres
            ),
            hourly: hourly ?? HourlyWeatherResponse(time: [], temperature_2m: [], weather_code: []),
            daily: DailyWeatherResponse(
                time: [day.string(from: yesterday), day.string(from: now)],
                weather_code: [weatherCode, weatherCode],
                temperature_2m_max: [maxTemp, maxTemp],
                temperature_2m_min: [minTemp, minTemp],
                sunrise: [stamp.string(from: sunrise.addingTimeInterval(-86_400)), stamp.string(from: sunrise)],
                sunset: [stamp.string(from: sunset.addingTimeInterval(-86_400)), stamp.string(from: sunset)],
                uv_index_max: [uvIndex, uvIndex],
                precipitation_probability_max: [rainChance, rainChance],
                precipitation_sum: [rainAmount, rainAmount],
                precipitation_hours: [rainHours, rainHours],
                daylight_duration: [daylightYesterday, daylightToday]
            )
        )
    }
}
