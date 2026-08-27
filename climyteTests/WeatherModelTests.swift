//
//  WeatherModelTests.swift
//  climyteTests
//

import XCTest
@testable import climyte

final class WeatherModelTests: XCTestCase {

    private let sydney = City(
        id: UUID(),
        name: "Sydney",
        country: "Australia",
        latitude: -33.8688,
        longitude: 151.2093
    )

    // MARK: - Decoding

    func testWeatherResponseDecoding() throws {
        let json = """
        {
            "latitude": -33.8688,
            "longitude": 151.2093,
            "utc_offset_seconds": 36000,
            "current": {
                "temperature_2m": 22.5,
                "apparent_temperature": 21.0,
                "is_day": 1,
                "weather_code": 0,
                "relative_humidity_2m": 60.0,
                "dew_point_2m": 12.0,
                "wind_speed_10m": 12.0,
                "wind_gusts_10m": 18.0,
                "visibility": 10000.0
            },
            "hourly": {
                "time": ["2026-07-25T10:00", "2026-07-25T11:00", "2026-07-25T12:00"],
                "temperature_2m": [20.0, 21.5, 23.0],
                "weather_code": [0, 2, 61]
            },
            "daily": {
                "time": ["2026-07-25"],
                "weather_code": [0],
                "temperature_2m_max": [25.0],
                "temperature_2m_min": [15.0],
                "uv_index_max": [2.0],
                "precipitation_probability_max": [null],
                "precipitation_sum": [0.0],
                "precipitation_hours": [0.0],
                "daylight_duration": [49993.0],
                "sunrise": ["2026-07-25T06:00"],
                "sunset": ["2026-07-25T18:00"]
            }
        }
        """

        let response = try JSONDecoder().decode(
            WeatherResponse.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(response.hourly.time.count, 3)
        XCTAssertEqual(response.hourly.temperature_2m, [20.0, 21.5, 23.0])
        XCTAssertEqual(response.hourly.weather_code, [0, 2, 61])
        XCTAssertEqual(response.utc_offset_seconds, 36000)
        XCTAssertEqual(response.current.visibility, 10000.0)
        XCTAssertEqual(response.current.wind_gusts_10m, 18.0)
        XCTAssertEqual(response.daily.precipitation_probability_max, [nil],
                       "A null probability must decode rather than fail the whole response")
    }

    // MARK: - Hourly parsing

    func testHourlyForecastKeepsCurrentAndFutureHoursCappedAt24() throws {
        let response = makeResponse(hourOffsets: -2...25)
        let weather = CityWeather(city: sydney, response: response)

        XCTAssertFalse(weather.hourlyForecasts.isEmpty)
        XCTAssertLessThanOrEqual(weather.hourlyForecasts.count, 24)

        let first = try XCTUnwrap(weather.hourlyForecasts.first)
        XCTAssertTrue(
            first.time.hasSuffix("am") || first.time.hasSuffix("pm"),
            "Formatted hour should end with am/pm, got \(first.time)"
        )
    }

    /// Open-Meteo can return parallel arrays of differing lengths; indexing past
    /// the shortest one would trap.
    func testMismatchedHourlyArrayLengthsAreClampedToShortestArray() {
        var response = makeResponse(hourOffsets: 0..<10)
        response = WeatherResponse(
            latitude: response.latitude,
            longitude: response.longitude,
            utc_offset_seconds: response.utc_offset_seconds,
            current: response.current,
            hourly: HourlyWeatherResponse(
                time: response.hourly.time,                      // 10
                temperature_2m: [20.0, 21.0, 22.0, 23.0, 24.0],  // 5
                weather_code: [0, 1, 2, 3, 45, 51, 61]           // 7
            ),
            daily: response.daily
        )

        let weather = CityWeather(city: sydney, response: response)

        XCTAssertEqual(
            weather.hourlyForecasts.count, 5,
            "Hourly count should be capped by the shortest parallel array"
        )
    }

    func testEmptyDailyArraysFallBackToCurrentTemperature() {
        var response = makeResponse(hourOffsets: 0..<3)
        response = WeatherResponse(
            latitude: response.latitude,
            longitude: response.longitude,
            utc_offset_seconds: response.utc_offset_seconds,
            current: response.current,
            hourly: response.hourly,
            daily: DailyWeatherResponse(
                time: [], weather_code: [], temperature_2m_max: [],
                temperature_2m_min: [], sunrise: [], sunset: [], uv_index_max: [],
                precipitation_probability_max: [], precipitation_sum: [],
                precipitation_hours: [], daylight_duration: []
            )
        )

        let weather = CityWeather(city: sydney, response: response)

        XCTAssertTrue(weather.dailyForecasts.isEmpty)
        XCTAssertEqual(weather.maxTemp, response.current.temperature_2m)
        XCTAssertEqual(weather.minTemp, response.current.temperature_2m)
        XCTAssertEqual(weather.sunriseFormatted, "--")
        XCTAssertEqual(weather.sunsetFormatted, "--")
        XCTAssertEqual(weather.uvIndex, 0.0)
    }

    // MARK: - Derived values

    func testVisibilityIsConvertedFromMetresToKilometres() {
        let weather = CityWeather(city: sydney, response: makeResponse(hourOffsets: 0..<3))
        XCTAssertEqual(weather.visibility, 10.0, accuracy: 0.001)
    }

    func testWeatherConditionMapsWMOCodes() {
        XCTAssertEqual(WeatherCondition.from(wmoCode: 0), .sunny)
        XCTAssertEqual(WeatherCondition.from(wmoCode: 3), .cloudy)
        XCTAssertEqual(WeatherCondition.from(wmoCode: 45), .foggy)
        XCTAssertEqual(WeatherCondition.from(wmoCode: 65), .rainy)
        XCTAssertEqual(WeatherCondition.from(wmoCode: 75), .snowy)
        XCTAssertEqual(WeatherCondition.from(wmoCode: 95), .stormy)
        XCTAssertEqual(WeatherCondition.from(wmoCode: 12345), .sunny, "Unknown codes fall back to sunny")
    }

    func testNightIsDerivedFromSunriseAndSunsetRatherThanIsDayFlag() {
        // Sun set an hour ago in the city's timezone, but the API still says is_day = 1.
        let response = makeResponse(
            hourOffsets: 0..<3,
            sunriseOffsetHours: -12,
            sunsetOffsetHours: -1,
            isDay: 1
        )

        let weather = CityWeather(city: sydney, response: response)

        XCTAssertTrue(weather.isNight, "Past sunset should read as night regardless of is_day")
    }

    func testDaytimeIsDerivedFromSunriseAndSunsetWindow() {
        let response = makeResponse(
            hourOffsets: 0..<3,
            sunriseOffsetHours: -2,
            sunsetOffsetHours: 6,
            isDay: 0
        )

        let weather = CityWeather(city: sydney, response: response)

        XCTAssertFalse(weather.isNight, "Between sunrise and sunset should read as day")
    }

    // MARK: - Fixtures

    /// Builds a response whose hourly/daily timestamps are relative to now, so
    /// the "current and future hours" filter has something realistic to chew on.
    private func makeResponse<S: Sequence>(
        hourOffsets: S,
        sunriseOffsetHours: Int = -6,
        sunsetOffsetHours: Int = 6,
        isDay: Int = 1
    ) -> WeatherResponse where S.Element == Int {
        let utcOffsetSeconds = 36000
        let timeZone = TimeZone(secondsFromGMT: utcOffsetSeconds)!

        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        isoFormatter.timeZone = timeZone

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = timeZone

        var calendar = Calendar.current
        calendar.timeZone = timeZone

        let now = Date()
        var times: [String] = []
        var temps: [Double] = []
        var codes: [Int] = []

        for offset in hourOffsets {
            guard let date = calendar.date(byAdding: .hour, value: offset, to: now) else { continue }
            times.append(isoFormatter.string(from: date))
            temps.append(20.0 + Double(offset))
            codes.append(offset % 2 == 0 ? 0 : 61)
        }

        let sunrise = calendar.date(byAdding: .hour, value: sunriseOffsetHours, to: now)!
        let sunset = calendar.date(byAdding: .hour, value: sunsetOffsetHours, to: now)!

        return WeatherResponse(
            latitude: -33.8688,
            longitude: 151.2093,
            utc_offset_seconds: utcOffsetSeconds,
            current: CurrentWeatherResponse(
                temperature_2m: 22.5,
                apparent_temperature: 21.0,
                is_day: isDay,
                weather_code: 0,
                relative_humidity_2m: 60.0,
                dew_point_2m: 10.0,
                wind_speed_10m: 12.0,
                wind_gusts_10m: 14.0,
                visibility: 10000.0
            ),
            hourly: HourlyWeatherResponse(
                time: times,
                temperature_2m: temps,
                weather_code: codes
            ),
            daily: DailyWeatherResponse(
                time: [dateFormatter.string(from: now)],
                weather_code: [0],
                temperature_2m_max: [25.0],
                temperature_2m_min: [15.0],
                sunrise: [isoFormatter.string(from: sunrise)],
                sunset: [isoFormatter.string(from: sunset)],
                uv_index_max: [2.0],
                precipitation_probability_max: [0],
                precipitation_sum: [0],
                precipitation_hours: [0],
                daylight_duration: [49993]
            )
        )
    }
}
