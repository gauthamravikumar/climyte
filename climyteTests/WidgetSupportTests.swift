//
//  WidgetSupportTests.swift
//  climyteTests
//

import XCTest
@testable import climyte

/// Covers the pieces the widget renders from: whether it is night at a date
/// other than now, when a timeline should re-render, and when a reading has
/// aged out of being presentable as current.
nonisolated final class WidgetSupportTests: XCTestCase {

    // MARK: - Night at a given date

    @MainActor func testDaytimeBetweenSunriseAndSunset() {
        let weather = weatherWithSunTimes()
        XCTAssertFalse(weather.isNight(at: instant("2026-06-01T12:00")))
    }

    @MainActor func testNightAfterSunset() {
        let weather = weatherWithSunTimes()
        XCTAssertTrue(weather.isNight(at: instant("2026-06-01T21:00")))
    }

    @MainActor func testNightBeforeTheFirstSunriseCovered() {
        let weather = weatherWithSunTimes()
        XCTAssertTrue(weather.isNight(at: instant("2026-06-01T03:00")))
    }

    /// The reason this is evaluated per day rather than against a single pair.
    ///
    /// A widget timeline routinely spans midnight. Judged against the *first*
    /// day's sunset, every hour after that evening reads as night — including
    /// eight the next morning, which would leave the widget in the dark
    /// palette through breakfast.
    @MainActor func testMorningAfterMidnightIsDaytime() {
        let weather = weatherWithSunTimes()

        XCTAssertTrue(weather.isNight(at: instant("2026-06-01T22:00")),
                      "Still night before the following sunrise")
        XCTAssertFalse(weather.isNight(at: instant("2026-06-02T08:00")),
                       "Past the next day's sunrise, so daytime again")
    }

    @MainActor func testFallsBackToTheDaylightFlagWithoutSunTimes() {
        let night = weatherWithSunTimes(includeSunTimes: false, isDay: 0)
        let day = weatherWithSunTimes(includeSunTimes: false, isDay: 1)

        XCTAssertTrue(night.isNight(at: instant("2026-06-01T12:00")))
        XCTAssertFalse(day.isNight(at: instant("2026-06-01T23:00")))
    }

    // MARK: - Timeline planning

    @MainActor func testRenderDatesCoverTheWindowHourly() {
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

    @MainActor func testRenderDatesIncludeSunsetInsideTheWindow() {
        let start = instant("2026-06-01T18:00")
        let dates = TimelinePlan.renderDates(from: start,
                                             to: start.addingTimeInterval(3 * 3600),
                                             solarDays: solarDays())

        XCTAssertTrue(dates.contains(instant("2026-06-01T20:00")),
                      "Sunset should get its own entry so the palette flips on time")
        XCTAssertEqual(dates, dates.sorted(), "WidgetKit requires ascending entries")
    }

    @MainActor func testRenderDatesIgnoreSunTimesOutsideTheWindow() {
        let start = instant("2026-06-01T10:00")
        let dates = TimelinePlan.renderDates(from: start,
                                             to: start.addingTimeInterval(2 * 3600),
                                             solarDays: solarDays())

        XCTAssertEqual(dates.count, 2, "Neither sunrise nor sunset falls in 10:00-12:00")
    }

    @MainActor func testRenderDatesSurviveAnEmptyWindow() {
        let start = instant("2026-06-01T10:00")
        XCTAssertEqual(TimelinePlan.renderDates(from: start, to: start, solarDays: []), [start],
                       "A timeline must never be empty")
    }

    // MARK: - Reading age

    @MainActor func testFreshReadingHasNoAgeToShow() {
        XCTAssertNil(ReadingAge.short(0))
        XCTAssertNil(ReadingAge.short(90 * 60))
        XCTAssertNil(ReadingAge.short(nil))
    }

    @MainActor func testStaleReadingReportsHoursThenDays() {
        XCTAssertEqual(ReadingAge.short(ReadingAge.staleAfter), "3h")
        XCTAssertEqual(ReadingAge.short(7 * 3600), "7h")
        XCTAssertEqual(ReadingAge.short(23 * 3600), "23h")
        XCTAssertEqual(ReadingAge.short(25 * 3600), "1d")
        XCTAssertEqual(ReadingAge.short(50 * 3600), "2d")
    }

    // MARK: - Refetch policy

    @MainActor func testAReadingWithNoAgeAlwaysNeedsFetching() {
        XCTAssertTrue(ReadingAge.needsRefetch(nil))
    }

    /// The case that matters: the app caches a reading and immediately asks
    /// for a widget reload. Answering that with a fetch would have the app and
    /// every placed widget request the same city seconds apart.
    @MainActor func testAReadingTheAppJustCachedIsNotRefetched() {
        XCTAssertFalse(ReadingAge.needsRefetch(0))
        XCTAssertFalse(ReadingAge.needsRefetch(60))
        XCTAssertFalse(ReadingAge.needsRefetch(ReadingAge.refetchAfter - 1))
    }

    @MainActor func testTheWidgetsOwnScheduleStillFetches() {
        XCTAssertTrue(ReadingAge.needsRefetch(ReadingAge.refetchAfter))
        XCTAssertTrue(ReadingAge.needsRefetch(WeatherTimelineProviderSpan.timelineSpan),
                      "A reload at the end of a timeline run must fetch")
        XCTAssertTrue(ReadingAge.needsRefetch(8 * 3600))
    }

    /// A reading can be worth refetching long before it is worth apologising
    /// for; the two thresholds must not collapse into each other.
    @MainActor func testRefetchHappensWellBeforeAReadingLooksStale() {
        XCTAssertLessThan(ReadingAge.refetchAfter, ReadingAge.staleAfter)
        XCTAssertTrue(ReadingAge.needsRefetch(30 * 60))
        XCTAssertNil(ReadingAge.short(30 * 60), "30 minutes old is worth refreshing, not flagging")
    }

    // MARK: - Reload coalescing

    @MainActor func testBurstOfChangesCostsASingleReload() async {
        var count = 0
        let reloader = WidgetReloader(delay: .milliseconds(20)) { count += 1 }

        for _ in 0..<5 { reloader.reload() }
        try? await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(count, 1, "A cold launch refreshes every city; that is one reload")
    }

    @MainActor func testFlushReloadsWithoutWaiting() async {
        var count = 0
        let reloader = WidgetReloader(delay: .seconds(30)) { count += 1 }

        reloader.reload()
        reloader.flush()

        XCTAssertEqual(count, 1, "Backgrounding cannot wait out a 30s window")
    }

    // MARK: - Helpers

    @MainActor private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    @MainActor private func instant(_ string: String) -> Date {
        Self.parser.date(from: string)!
    }

    @MainActor private func solarDays() -> [SolarDay] {
        [
            SolarDay(sunrise: instant("2026-06-01T06:00"), sunset: instant("2026-06-01T20:00")),
            SolarDay(sunrise: instant("2026-06-02T06:00"), sunset: instant("2026-06-02T20:00"))
        ]
    }

    /// Two consecutive days with the sun up from 06:00 to 20:00, in UTC.
    @MainActor private func weatherWithSunTimes(includeSunTimes: Bool = true, isDay: Int = 1) -> CityWeather {
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
            hourly: HourlyWeatherResponse(time: [], temperature_2m: []),
            daily: DailyWeatherResponse(
                time: ["2026-06-01", "2026-06-02"],
                temperature_2m_max: [24, 24],
                temperature_2m_min: [12, 12],
                sunrise: sunrises,
                sunset: sunsets,
                uv_index_max: [4, 4],
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

/// The rule that keeps a reconfigured widget from going blank without also
/// stopping it refreshing. Both failure modes are silent, which is why this
/// is tested rather than left inline in the provider.
nonisolated final class FetchDecisionTests: XCTestCase {

    private let now = Date()

    @MainActor func testAFreshReadingNeedsNoFetch() {
        XCTAssertEqual(FetchDecision.decide(hasReading: true, age: 60,
                                            lastDeferral: nil, now: now), .useCache)
    }

    @MainActor func testNoReadingFetchesImmediately() {
        // Nothing to draw either way, so waiting costs nothing.
        XCTAssertEqual(FetchDecision.decide(hasReading: false, age: nil,
                                            lastDeferral: nil, now: now), .fetchNow)
    }

    /// The reconfiguration case: a fetch is due, but blocking would leave the
    /// slot empty for as long as the network takes.
    @MainActor func testAStaleReadingIsShownFirstAndTheFetchDeferred() {
        XCTAssertEqual(FetchDecision.decide(hasReading: true, age: 3600,
                                            lastDeferral: nil, now: now), .deferFetch)
    }

    /// The follow-up pass must actually fetch. If it deferred again the widget
    /// would show the same stale reading forever and never refresh — which is
    /// exactly what a first attempt at this did.
    @MainActor func testTheFollowUpPassFetchesRatherThanDeferringAgain() {
        XCTAssertEqual(FetchDecision.decide(hasReading: true, age: 3600,
                                            lastDeferral: now.addingTimeInterval(-10),
                                            now: now), .fetchNow)
    }

    /// A deferral that never got its follow-up must not suppress fetching for
    /// good; past the window the widget falls back to fetching inline.
    @MainActor func testAnExpiredDeferralDoesNotSuppressFetchingForever() {
        XCTAssertEqual(FetchDecision.decide(hasReading: true, age: 3600,
                                            lastDeferral: now.addingTimeInterval(-600),
                                            now: now, window: 120), .deferFetch)
    }

    /// Deferring only matters when there is something to show meanwhile.
    @MainActor func testNoReadingFetchesEvenWithADeferralRecorded() {
        XCTAssertEqual(FetchDecision.decide(hasReading: false, age: nil,
                                            lastDeferral: now, now: now), .fetchNow)
    }
}

/// The Daylight widget's picture is the city's day, midnight to midnight.
nonisolated final class LightClockTests: XCTestCase {

    /// Midnight UTC on 1 June 2026, plus hours.
    @MainActor private func at(_ hours: Double) -> Date {
        Date(timeIntervalSince1970: 1_780_272_000 + hours * 3_600)
    }

    @MainActor private var days: [SolarDay] {
        [SolarDay(sunrise: at(6), sunset: at(18)),
         SolarDay(sunrise: at(30), sunset: at(42))]
    }

    @MainActor func testTheDayIsPlacedAcrossMidnightToMidnight() throws {
        let day = try XCTUnwrap(LightClock.day(at: at(14), in: days, timeZone: TimeZone(secondsFromGMT: 0)!))

        XCTAssertEqual(day.sunriseFraction, 0.25, accuracy: 0.0001)
        XCTAssertEqual(day.sunsetFraction, 0.75, accuracy: 0.0001)
        XCTAssertEqual(day.nowFraction, 14.0 / 24, accuracy: 0.0001)
    }

    /// After midnight the picture is the new day, with its own sun times.
    @MainActor func testTheSmallHoursBelongToTheNewDay() throws {
        let day = try XCTUnwrap(LightClock.day(at: at(27), in: days, timeZone: TimeZone(secondsFromGMT: 0)!))

        XCTAssertEqual(day.sunrise, at(30))
        XCTAssertEqual(day.nowFraction, 3.0 / 24, accuracy: 0.0001)
    }

    /// The city's own midnight, not the device's: 2 pm in Melbourne is the
    /// same instant as 4 am in UTC.
    @MainActor func testFractionsAreOfTheCitysDay() throws {
        let melbourne = try XCTUnwrap(TimeZone(identifier: "Australia/Melbourne"))
        let local = [SolarDay(sunrise: at(-4), sunset: at(8))]   // 6 am and 6 pm in Melbourne (UTC+10)

        let day = try XCTUnwrap(LightClock.day(at: at(4), in: local, timeZone: melbourne))

        XCTAssertEqual(day.sunriseFraction, 0.25, accuracy: 0.0001)
        XCTAssertEqual(day.nowFraction, 14.0 / 24, accuracy: 0.0001)
    }

    @MainActor func testNoSunTimesForTheDayDrawsNoBand() {
        XCTAssertNil(LightClock.day(at: at(60), in: days, timeZone: TimeZone(secondsFromGMT: 0)!))
    }

    @MainActor func testTheMediumWidgetsRedrawEachQuarterHour() {
        let start = at(10)
        let dates = TimelinePlan.renderDates(from: start, to: start.addingTimeInterval(3_600),
                                             solarDays: [], step: 900)
        XCTAssertEqual(dates.count, 4)
        XCTAssertEqual(dates.last, start.addingTimeInterval(2_700))
    }
}

/// The link a widget carries survives a round trip, minus signs and all.
nonisolated final class CityLinkTests: XCTestCase {
    @MainActor func testALinkNamesItsCity() throws {
        let melbourne = City(id: UUID(), name: "Melbourne", country: "Australia",
                             countryCode: "AU", latitude: -37.8136, longitude: 144.9631)
        let url = try XCTUnwrap(CityLink.url(for: melbourne))

        XCTAssertEqual(url.scheme, "climyte")
        XCTAssertEqual(CityLink.cityKey(from: url), melbourne.key)
    }
}

/// Which city a widget shows, from the name its configuration stored. The
/// widget and its city picker must agree: the picker can only show what was
/// stored, so the widget must never quietly show another city in its place.
nonisolated final class WidgetCityTests: XCTestCase {
    @MainActor private func city(_ name: String, _ latitude: Double) -> City {
        City(id: UUID(), name: name, country: "", countryCode: nil, latitude: latitude, longitude: 0)
    }

    @MainActor func testAChosenCityThatIsStillSavedIsShown() {
        let saved = [city("Madurai", 9.9), city("Seattle", 47.6)]
        XCTAssertEqual(WidgetCity.resolve(name: "Seattle", saved: saved), .city(saved[1]))
    }

    @MainActor func testAChosenCitySinceRemovedIsNamedRatherThanSwappedForAnother() {
        let saved = [city("Madurai", 9.9), city("Seattle", 47.6)]
        XCTAssertEqual(WidgetCity.resolve(name: "New York", saved: saved), .removed(name: "New York"))
    }

    @MainActor func testAWidgetWithNoChoiceShowsTheFirstSavedCity() {
        let saved = [city("Madurai", 9.9), city("Seattle", 47.6)]
        XCTAssertEqual(WidgetCity.resolve(name: nil, saved: saved), .city(saved[0]))
    }

    @MainActor func testNothingSavedShowsNothing() {
        XCTAssertEqual(WidgetCity.resolve(name: nil, saved: []), .none)
    }
}
