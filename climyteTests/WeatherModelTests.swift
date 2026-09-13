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

        // The hour label follows the reader's 12/24-hour setting, so assert the
        // shape rather than one convention: "2 pm" for a 12-hour reader, "14"
        // for a 24-hour one. Pinning this to am/pm would have made the app
        // wrong for most of the world in order to keep the test green.
        let first = try XCTUnwrap(weather.hourlyForecasts.first)
        let usesTwelveHourClock = first.time.hasSuffix("am") || first.time.hasSuffix("pm")
        let usesTwentyFourHourClock = Int(first.time.trimmingCharacters(in: .whitespaces)) != nil

        XCTAssertTrue(usesTwelveHourClock || usesTwentyFourHourClock,
                      "Hour label should be '2 pm' or '14', got \(first.time)")
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

    /// No daily figures means no today: the range is unknown, not the
    /// current temperature standing in for a high and a low it isn't.
    func testEmptyDailyArraysLeaveTodaysRangeUnknown() {
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
        XCTAssertNil(weather.maxTemp)
        XCTAssertNil(weather.minTemp)
        XCTAssertFalse(weather.coversToday)
        XCTAssertEqual(weather.sunriseFormatted, "--")
        XCTAssertEqual(weather.sunsetFormatted, "--")
        XCTAssertEqual(weather.uvIndex, 0.0)
    }

    // MARK: - Robustness of the daily arrays

    /// Open-Meteo sends null past the horizon of the model backing a field.
    /// One null must cost that one day, not the whole city.
    func testANullDayIsSkippedRatherThanFailingTheWholeResponse() {
        let base = makeResponse(hourOffsets: 0..<3)
        let response = withDaily(base, days: [
            ("today", 20, 26), ("null", nil, nil), ("later", 15, 21),
        ])

        let weather = CityWeather(city: sydney, response: response)

        XCTAssertEqual(weather.dailyForecasts.count, 2, "The null day is dropped, the others survive")
        XCTAssertFalse(weather.dailyForecasts.contains { $0.minTemp == 0 },
                       "A missing day must not chart as zero")
    }

    /// Falling back to index 0 would render yesterday as today — plausible
    /// looking and wrong. When today is absent the week starts at the next
    /// day forward, and no other day's figures are passed off as today's.
    func testMissingTodayStartsTheWeekTomorrowAndClaimsNoRange() {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.calendar = Calendar(identifier: .gregorian)
        day.dateFormat = "yyyy-MM-dd"
        day.timeZone = TimeZone(secondsFromGMT: 36000)

        let yesterday = day.string(from: Date().addingTimeInterval(-86_400))
        let tomorrow = day.string(from: Date().addingTimeInterval(86_400))

        let base = makeResponse(hourOffsets: 0..<3)
        let response = withDailyTimes(base, times: [yesterday, tomorrow],
                                      maxTemps: [99, 21], minTemps: [98, 15])

        let weather = CityWeather(city: sydney, response: response)

        XCTAssertEqual(weather.dailyForecasts.first?.maxTemp, 21, "The week starts tomorrow, not with yesterday's 99")
        XCTAssertNil(weather.maxTemp, "Tomorrow's high is not today's")
        XCTAssertFalse(weather.coversToday)
    }

    /// Mismatched parallel array lengths can put today past the end of the
    /// shortest array; the range must not be built reversed.
    func testTodayIndexBeyondTheShortestArrayDoesNotTrap() {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.calendar = Calendar(identifier: .gregorian)
        day.dateFormat = "yyyy-MM-dd"
        day.timeZone = TimeZone(secondsFromGMT: 36000)

        var times = (0..<8).map { day.string(from: Date().addingTimeInterval(Double($0 - 5) * 86_400)) }
        times[5] = day.string(from: Date())

        let base = makeResponse(hourOffsets: 0..<3)
        let response = withDailyTimes(base, times: times, maxTemps: [25, 24], minTemps: [15, 14])

        let weather = CityWeather(city: sydney, response: response)

        XCTAssertTrue(weather.dailyForecasts.isEmpty, "No usable days, but no crash either")
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

    // MARK: - A clear sky by day and by night

    /// A clear sky after dark is not sunny. The words follow the city's own
    /// sunrise and sunset — the same clock that turns the page dark — so the
    /// line under the reading never contradicts the page it sits on.
    func testAClearSkyAfterDarkReadsClearNotSunny() {
        let response = makeResponse(hourOffsets: 0..<3, sunriseOffsetHours: -12,
                                    sunsetOffsetHours: -1, isDay: 1)
        let weather = CityWeather(city: sydney, response: response)
        XCTAssertEqual(weather.condition, .sunny, "The fixture is a clear sky")

        XCTAssertEqual(weather.conditionDescription(), "Clear")
    }

    func testAClearSkyByDayStillReadsSunny() {
        let response = makeResponse(hourOffsets: 0..<3, sunriseOffsetHours: -2,
                                    sunsetOffsetHours: 6, isDay: 0)
        let weather = CityWeather(city: sydney, response: response)

        XCTAssertEqual(weather.conditionDescription(), "Sunny")
    }

    /// A widget draws entries for moments still to come, so one reading can be
    /// shown by day and again after sunset. The words are for the moment
    /// drawn, not the moment fetched.
    func testTheWordsFollowTheMomentTheyAreShownFor() {
        let response = makeResponse(hourOffsets: 0..<3, sunriseOffsetHours: -2,
                                    sunsetOffsetHours: 6, isDay: 1)
        let weather = CityWeather(city: sydney, response: response)

        XCTAssertEqual(weather.conditionDescription(at: Date()), "Sunny")
        XCTAssertEqual(weather.conditionDescription(at: Date().addingTimeInterval(7 * 3_600)), "Clear")
    }

    func testOnlyAClearSkyChangesItsWordsAtNight() {
        XCTAssertEqual(WeatherCondition.sunny.description(isNight: false), "Sunny")
        XCTAssertEqual(WeatherCondition.sunny.description(isNight: true), "Clear")
        XCTAssertEqual(WeatherCondition.cloudy.description(isNight: true), "Cloudy")
        XCTAssertEqual(WeatherCondition.rainy.description(isNight: true), "Rainy")
    }

    // MARK: - A saved forecast whose days have passed

    /// A forecast saved ten days ago and shown before a new one arrives — or
    /// for as long as there is no connection. Its last day used to stand in
    /// for the whole week and for today's high, UV and daylight.
    func testAForecastWhoseDaysHaveAllPassedClaimsNothingAboutToday() {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.calendar = Calendar(identifier: .gregorian)
        day.dateFormat = "yyyy-MM-dd"
        day.timeZone = TimeZone(secondsFromGMT: 36000)
        let times = [11, 10].map { day.string(from: Date().addingTimeInterval(Double(-$0) * 86_400)) }

        let base = makeResponse(hourOffsets: -270 ..< -240)
        let response = withDailyTimes(base, times: times, maxTemps: [21, 22], minTemps: [6, 7])
        let weather = CityWeather(city: sydney, response: response)

        XCTAssertTrue(weather.dailyForecasts.isEmpty, "Days that are over are not a forecast")
        XCTAssertTrue(weather.hourlyForecasts.isEmpty, "Nor are hours that are over")
        XCTAssertNil(weather.maxTemp)
        XCTAssertNil(weather.minTemp)
        XCTAssertNil(weather.daylightSeconds)
        XCTAssertEqual(weather.uvIndex, 0, "No UV row from a day long gone")
        XCTAssertFalse(weather.coversToday)
    }

    func testAForecastThatIncludesTodayCoversIt() {
        let weather = CityWeather(city: sydney, response: TestResponse.make())
        XCTAssertTrue(weather.coversToday)
        XCTAssertEqual(weather.maxTemp, 26)
    }

    /// The page's theme follows the sun. When every day in a saved forecast has
    /// passed, its sun times can't say whether it is day now: judged against a
    /// sunset a week gone, the page stayed dark all day. The sun itself answers
    /// instead.
    func testAForecastWhoseDaysHavePassedStillKnowsDayFromNight() {
        let base = TestResponse.make()
        let response = WeatherResponse(
            latitude: sydney.latitude, longitude: sydney.longitude, utc_offset_seconds: 36_000,
            current: base.current, hourly: base.hourly,
            daily: DailyWeatherResponse(
                time: ["2026-09-01", "2026-09-02"],
                weather_code: [0, 0],
                temperature_2m_max: [20, 21],
                temperature_2m_min: [10, 11],
                sunrise: ["2026-09-01T06:10", "2026-09-02T06:09"],
                sunset: ["2026-09-01T17:40", "2026-09-02T17:41"],
                uv_index_max: [nil, nil],
                precipitation_probability_max: [nil, nil],
                precipitation_sum: [nil, nil],
                precipitation_hours: [nil, nil],
                daylight_duration: [nil, nil]
            )
        )
        let weather = CityWeather(city: sydney, response: response)
        XCTAssertFalse(weather.solarDays.isEmpty, "The fixture has sun times, just old ones")

        let utc = ISO8601DateFormatter()
        XCTAssertFalse(weather.isNight(at: utc.date(from: "2026-09-13T02:00:00Z")!), "Midday in Sydney")
        XCTAssertTrue(weather.isNight(at: utc.date(from: "2026-09-13T14:00:00Z")!), "Midnight in Sydney")
    }

    // MARK: - Fixtures

    private func withDaily(_ base: WeatherResponse,
                           days: [(String, Double?, Double?)]) -> WeatherResponse {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.calendar = Calendar(identifier: .gregorian)
        day.dateFormat = "yyyy-MM-dd"
        day.timeZone = TimeZone(secondsFromGMT: 36000)
        let times = days.indices.map { day.string(from: Date().addingTimeInterval(Double($0) * 86_400)) }

        return withDailyTimes(base, times: times,
                              maxTemps: days.map(\.2), minTemps: days.map(\.1),
                              codes: days.map { $0.1 == nil ? nil : 0 })
    }

    private func withDailyTimes(_ base: WeatherResponse,
                                times: [String],
                                maxTemps: [Double?],
                                minTemps: [Double?],
                                codes: [Int?]? = nil) -> WeatherResponse {
        WeatherResponse(
            latitude: base.latitude,
            longitude: base.longitude,
            utc_offset_seconds: base.utc_offset_seconds,
            current: base.current,
            hourly: base.hourly,
            daily: DailyWeatherResponse(
                time: times,
                weather_code: codes ?? Array(repeating: 0, count: times.count),
                temperature_2m_max: maxTemps,
                temperature_2m_min: minTemps,
                sunrise: Array(repeating: nil, count: times.count),
                sunset: Array(repeating: nil, count: times.count),
                uv_index_max: Array(repeating: nil, count: times.count),
                precipitation_probability_max: Array(repeating: nil, count: times.count),
                precipitation_sum: Array(repeating: nil, count: times.count),
                precipitation_hours: Array(repeating: nil, count: times.count),
                daylight_duration: Array(repeating: nil, count: times.count)
            )
        )
    }

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
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")
        isoFormatter.calendar = Calendar(identifier: .gregorian)
        isoFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        isoFormatter.timeZone = timeZone

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = Calendar(identifier: .gregorian)
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
