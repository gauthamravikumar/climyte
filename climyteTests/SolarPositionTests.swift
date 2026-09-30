//
//  SolarPositionTests.swift
//  climyteTests
//

import XCTest
@testable import climyte

/// The sun's position drives the arc, so an error here puts the sun on the
/// wrong side of it without anything failing.
nonisolated final class SolarPositionTests: XCTestCase {

    @MainActor private var days: [SolarDay] {
        [SolarDay(sunrise: iso("2026-06-01T06:00"), sunset: iso("2026-06-01T20:00")),
         SolarDay(sunrise: iso("2026-06-02T06:00"), sunset: iso("2026-06-02T20:00"))]
    }

    @MainActor func testProgressRunsFromSunriseToSunset() {
        XCTAssertEqual(SolarPosition.daylightProgress(at: iso("2026-06-01T06:00"), in: days) ?? -1,
                       0, accuracy: 0.001)
        XCTAssertEqual(SolarPosition.daylightProgress(at: iso("2026-06-01T13:00"), in: days) ?? -1,
                       0.5, accuracy: 0.001)
        XCTAssertEqual(SolarPosition.daylightProgress(at: iso("2026-06-01T20:00"), in: days) ?? -1,
                       1, accuracy: 0.001)
    }

    @MainActor func testProgressIsNilWhileTheSunIsDown() {
        XCTAssertNil(SolarPosition.daylightProgress(at: iso("2026-06-01T03:00"), in: days))
        XCTAssertNil(SolarPosition.daylightProgress(at: iso("2026-06-01T22:00"), in: days))
    }

    /// The evening and the next morning are measured against their own days.
    @MainActor func testTheMorningAfterMidnightUsesItsOwnSunrise() {
        XCTAssertNil(SolarPosition.daylightProgress(at: iso("2026-06-01T23:00"), in: days))
        XCTAssertEqual(SolarPosition.daylightProgress(at: iso("2026-06-02T13:00"), in: days) ?? -1,
                       0.5, accuracy: 0.001, "Past the next sunrise it is the middle of that day")
    }

    @MainActor func testRemainingDaylightCountsDownToSunset() {
        let left = SolarPosition.remainingDaylight(at: iso("2026-06-01T19:00"), in: days)
        XCTAssertEqual(left ?? 0, 3600, accuracy: 1)
        XCTAssertNil(SolarPosition.remainingDaylight(at: iso("2026-06-01T21:00"), in: days))
    }

    @MainActor func testNoSunTimesIsHandledRatherThanCrashing() {
        XCTAssertNil(SolarPosition.daylightProgress(at: Date(), in: []))
        XCTAssertNil(SolarPosition.remainingDaylight(at: Date(), in: []))
    }
}

private func iso(_ string: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.calendar = Calendar(identifier: .gregorian)
    f.dateFormat = "yyyy-MM-dd'T'HH:mm"
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f.date(from: string)!
}

/// Whether the sun is up, from the sun itself. A forecast's sun times cover
/// only its own days, and a saved forecast old enough for all of them to have
/// passed left the page judging today against a sunset a week gone — dark all
/// day.
nonisolated final class SunUpTests: XCTestCase {

    @MainActor func testTheSunIsUpAtMiddayAndDownAtMidnight() {
        // Sydney is ten hours ahead of UTC in September.
        XCTAssertTrue(SolarPosition.isSunUp(at: iso("2026-09-13T02:00"), latitude: -33.87, longitude: 151.21))
        XCTAssertFalse(SolarPosition.isSunUp(at: iso("2026-09-13T14:00"), latitude: -33.87, longitude: 151.21))
    }

    /// London's sunset on 13 September, by Open-Meteo, was 18:19 UTC.
    @MainActor func testItSetsWithinMinutesOfTheForecastsOwnSunset() {
        XCTAssertTrue(SolarPosition.isSunUp(at: iso("2026-09-13T18:12"), latitude: 51.51, longitude: -0.13))
        XCTAssertFalse(SolarPosition.isSunUp(at: iso("2026-09-13T18:26"), latitude: 51.51, longitude: -0.13))
    }

    @MainActor func testTheMidnightSunAndThePolarNight() {
        // Longyearbyen, Svalbard: up at 1:30 am local in June, down at noon in December.
        XCTAssertTrue(SolarPosition.isSunUp(at: iso("2026-06-21T23:30"), latitude: 78.22, longitude: 15.65))
        XCTAssertFalse(SolarPosition.isSunUp(at: iso("2026-12-21T11:00"), latitude: 78.22, longitude: 15.65))
    }
}

/// Before dawn the arc looks ahead to sunrise; in the evening it does not.
nonisolated final class UntilSunriseTests: XCTestCase {

    /// Midnight UTC on 1 June 2026, plus hours.
    @MainActor private func at(_ hours: Double) -> Date {
        Date(timeIntervalSince1970: 1_780_272_000 + hours * 3_600)
    }

    /// Two days with the sun up from 06:00 to 20:00 UTC.
    @MainActor private var days: [SolarDay] {
        [SolarDay(sunrise: at(6), sunset: at(20)),
         SolarDay(sunrise: at(30), sunset: at(44))]
    }

    @MainActor private func untilSunrise(at hours: Double) -> TimeInterval? {
        SolarPosition.untilSunrise(at: at(hours), in: days, timeZone: TimeZone(secondsFromGMT: 0)!)
    }

    @MainActor func testTheSmallHoursCountDownToSunrise() {
        XCTAssertEqual(untilSunrise(at: 27), 3 * 3_600, "3 am on the second day, sunrise at 6")
        XCTAssertEqual(untilSunrise(at: 3), 3 * 3_600)
    }

    @MainActor func testTheEveningDoesNot() {
        XCTAssertNil(untilSunrise(at: 22), "Sunset has just gone; sunrise is tomorrow's business")
    }

    @MainActor func testNorDoesDaylight() {
        XCTAssertNil(untilSunrise(at: 12))
    }

    @MainActor func testNothingToCountToPastTheForecast() {
        XCTAssertNil(untilSunrise(at: 46), "No sunrise left in the data")
    }
}
