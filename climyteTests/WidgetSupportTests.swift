//
//  WidgetSupportTests.swift
//  climyteTests
//

import XCTest
@testable import climyte

/// Covers the pieces the widget renders from: whether it is night at a date
/// other than now, when a timeline should re-render, and when a reading has
/// aged out of being presentable as current.
@MainActor
final class WidgetSupportTests: XCTestCase {

    // MARK: - Night at a given date

    func testDaytimeBetweenSunriseAndSunset() {
        let weather = weatherWithSunTimes()
        XCTAssertFalse(weather.isNight(at: instant("2026-06-01T12:00")))
    }

    func testNightAfterSunset() {
        let weather = weatherWithSunTimes()
        XCTAssertTrue(weather.isNight(at: instant("2026-06-01T21:00")))
    }

    func testNightBeforeTheFirstSunriseCovered() {
        let weather = weatherWithSunTimes()
        XCTAssertTrue(weather.isNight(at: instant("2026-06-01T03:00")))
    }

    /// The reason this is evaluated per day rather than against a single pair.
    ///
    /// A widget timeline routinely spans midnight. Judged against the *first*
    /// day's sunset, every hour after that evening reads as night — including
    /// eight the next morning, which would leave the widget in the dark
    /// palette through breakfast.
    func testMorningAfterMidnightIsDaytime() {
        let weather = weatherWithSunTimes()

        XCTAssertTrue(weather.isNight(at: instant("2026-06-01T22:00")),
                      "Still night before the following sunrise")
        XCTAssertFalse(weather.isNight(at: instant("2026-06-02T08:00")),
                       "Past the next day's sunrise, so daytime again")
    }

    func testFallsBackToTheDaylightFlagWithoutSunTimes() {
        let night = weatherWithSunTimes(includeSunTimes: false, isDay: 0)
        let day = weatherWithSunTimes(includeSunTimes: false, isDay: 1)

        XCTAssertTrue(night.isNight(at: instant("2026-06-01T12:00")))
        XCTAssertFalse(day.isNight(at: instant("2026-06-01T23:00")))
    }

    // MARK: - Timeline planning

    func testRenderDatesCoverTheWindowHourly() {
        let start = instant("2026-06-01T10:00")
        let dates = TimelinePlan.renderDates(from: start,
                                             to: start.addingTimeInterval(3 * 3600),
                                             solarDays: [])

        XCTAssertEqual(dates, [
            instant("2026-06-01T10:00"),
            instant("2026-06-01T11:00"),
            instant("2026-06-01T12:00")
        ])
    }

    func testRenderDatesIncludeSunsetInsideTheWindow() {
        let start = instant("2026-06-01T18:00")
        let dates = TimelinePlan.renderDates(from: start,
                                             to: start.addingTimeInterval(3 * 3600),
                                             solarDays: solarDays())

        XCTAssertTrue(dates.contains(instant("2026-06-01T20:00")),
                      "Sunset should get its own entry so the palette flips on time")
        XCTAssertEqual(dates, dates.sorted(), "WidgetKit requires ascending entries")
    }

    func testRenderDatesIgnoreSunTimesOutsideTheWindow() {
        let start = instant("2026-06-01T10:00")
        let dates = TimelinePlan.renderDates(from: start,
                                             to: start.addingTimeInterval(2 * 3600),
                                             solarDays: solarDays())

        XCTAssertEqual(dates.count, 2, "Neither sunrise nor sunset falls in 10:00-12:00")
    }

    func testRenderDatesSurviveAnEmptyWindow() {
        let start = instant("2026-06-01T10:00")
        XCTAssertEqual(TimelinePlan.renderDates(from: start, to: start, solarDays: []), [start],
                       "A timeline must never be empty")
    }

    // MARK: - Reading age

    func testFreshReadingHasNoAgeToShow() {
        XCTAssertNil(ReadingAge.short(0))
        XCTAssertNil(ReadingAge.short(90 * 60))
        XCTAssertNil(ReadingAge.short(nil))
    }

    func testStaleReadingReportsHoursThenDays() {
        XCTAssertEqual(ReadingAge.short(ReadingAge.staleAfter), "3h")
        XCTAssertEqual(ReadingAge.short(7 * 3600), "7h")
        XCTAssertEqual(ReadingAge.short(23 * 3600), "23h")
        XCTAssertEqual(ReadingAge.short(25 * 3600), "1d")
        XCTAssertEqual(ReadingAge.short(50 * 3600), "2d")
    }

    // MARK: - Refetch policy

    func testAReadingWithNoAgeAlwaysNeedsFetching() {
        XCTAssertTrue(ReadingAge.needsRefetch(nil))
    }

    /// The case that matters: the app caches a reading and immediately asks
    /// for a widget reload. Answering that with a fetch would have the app and
    /// every placed widget request the same city seconds apart.
    func testAReadingTheAppJustCachedIsNotRefetched() {
        XCTAssertFalse(ReadingAge.needsRefetch(0))
        XCTAssertFalse(ReadingAge.needsRefetch(60))
        XCTAssertFalse(ReadingAge.needsRefetch(ReadingAge.refetchAfter - 1))
    }

    func testTheWidgetsOwnScheduleStillFetches() {
        XCTAssertTrue(ReadingAge.needsRefetch(ReadingAge.refetchAfter))
        XCTAssertTrue(ReadingAge.needsRefetch(WeatherTimelineProviderSpan.timelineSpan),
                      "A reload at the end of a timeline run must fetch")
        XCTAssertTrue(ReadingAge.needsRefetch(8 * 3600))
    }

    /// A reading can be worth refetching long before it is worth apologising
    /// for; the two thresholds must not collapse into each other.
    func testRefetchHappensWellBeforeAReadingLooksStale() {
        XCTAssertLessThan(ReadingAge.refetchAfter, ReadingAge.staleAfter)
        XCTAssertTrue(ReadingAge.needsRefetch(30 * 60))
        XCTAssertNil(ReadingAge.short(30 * 60), "30 minutes old is worth refreshing, not flagging")
    }

    // MARK: - Reload coalescing

    func testBurstOfChangesCostsASingleReload() async {
        var count = 0
        let reloader = WidgetReloader(delay: .milliseconds(20)) { count += 1 }

        for _ in 0..<5 { reloader.reload() }
        try? await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(count, 1, "A cold launch refreshes every city; that is one reload")
    }

    func testFlushReloadsWithoutWaiting() async {
        var count = 0
        let reloader = WidgetReloader(delay: .seconds(30)) { count += 1 }

        reloader.reload()
        reloader.flush()

        XCTAssertEqual(count, 1, "Backgrounding cannot wait out a 30s window")
    }

    // MARK: - Helpers

    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private func instant(_ string: String) -> Date {
        Self.parser.date(from: string)!
    }

    private func solarDays() -> [SolarDay] {
        [
            SolarDay(sunrise: instant("2026-06-01T06:00"), sunset: instant("2026-06-01T20:00")),
            SolarDay(sunrise: instant("2026-06-02T06:00"), sunset: instant("2026-06-02T20:00"))
        ]
    }

    /// Two consecutive days with the sun up from 06:00 to 20:00, in UTC.
    private func weatherWithSunTimes(includeSunTimes: Bool = true, isDay: Int = 1) -> CityWeather {
        let sunrises = includeSunTimes ? ["2026-06-01T06:00", "2026-06-02T06:00"] : [nil, nil]
        let sunsets = includeSunTimes ? ["2026-06-01T20:00", "2026-06-02T20:00"] : [nil, nil]

        let response = WeatherResponse(
            latitude: 0,
            longitude: 0,
            utc_offset_seconds: 0,
            current: CurrentWeatherResponse(
                temperature_2m: 18, apparent_temperature: 18, is_day: isDay,
                weather_code: 0, relative_humidity_2m: 60, dew_point_2m: 10,
                wind_speed_10m: 10, wind_gusts_10m: 12, visibility: 20_000
            ),
            hourly: HourlyWeatherResponse(time: [], temperature_2m: [], weather_code: []),
            daily: DailyWeatherResponse(
                time: ["2026-06-01", "2026-06-02"],
                weather_code: [0, 0],
                temperature_2m_max: [24, 24],
                temperature_2m_min: [12, 12],
                sunrise: sunrises,
                sunset: sunsets,
                uv_index_max: [4, 4],
                precipitation_probability_max: [0, 0],
                precipitation_sum: [0, 0],
                precipitation_hours: [0, 0],
                daylight_duration: [50_400, 50_400]
            )
        )

        let city = City(id: UUID(), name: "Testville", country: "Nowhere",
                        countryCode: "AU", latitude: 0, longitude: 0)
        return CityWeather(city: city, response: response)
    }
}

/// The widget extension is not part of this test bundle, so its timeline span
/// is restated here. If the two ever disagree the refetch test above stops
/// describing the real schedule — keep them equal.
private enum WeatherTimelineProviderSpan {
    static let timelineSpan: TimeInterval = 2 * 3600
}
