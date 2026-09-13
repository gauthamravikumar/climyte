//
//  SolarPositionTests.swift
//  climyteTests
//

import XCTest
@testable import climyte

/// The sun's position drives the arc, so an error here puts the sun on the
/// wrong side of it without anything failing.
@MainActor
final class SolarPositionTests: XCTestCase {

    private let days = [
        SolarDay(sunrise: iso("2026-06-01T06:00"), sunset: iso("2026-06-01T20:00")),
        SolarDay(sunrise: iso("2026-06-02T06:00"), sunset: iso("2026-06-02T20:00"))
    ]

    func testProgressRunsFromSunriseToSunset() {
        XCTAssertEqual(SolarPosition.daylightProgress(at: iso("2026-06-01T06:00"), in: days) ?? -1,
                       0, accuracy: 0.001)
        XCTAssertEqual(SolarPosition.daylightProgress(at: iso("2026-06-01T13:00"), in: days) ?? -1,
                       0.5, accuracy: 0.001)
        XCTAssertEqual(SolarPosition.daylightProgress(at: iso("2026-06-01T20:00"), in: days) ?? -1,
                       1, accuracy: 0.001)
    }

    func testProgressIsNilWhileTheSunIsDown() {
        XCTAssertNil(SolarPosition.daylightProgress(at: iso("2026-06-01T03:00"), in: days))
        XCTAssertNil(SolarPosition.daylightProgress(at: iso("2026-06-01T22:00"), in: days))
    }

    /// The evening and the next morning are measured against their own days.
    func testTheMorningAfterMidnightUsesItsOwnSunrise() {
        XCTAssertNil(SolarPosition.daylightProgress(at: iso("2026-06-01T23:00"), in: days))
        XCTAssertEqual(SolarPosition.daylightProgress(at: iso("2026-06-02T13:00"), in: days) ?? -1,
                       0.5, accuracy: 0.001, "Past the next sunrise it is the middle of that day")
    }

    func testRemainingDaylightCountsDownToSunset() {
        let left = SolarPosition.remainingDaylight(at: iso("2026-06-01T19:00"), in: days)
        XCTAssertEqual(left ?? 0, 3600, accuracy: 1)
        XCTAssertNil(SolarPosition.remainingDaylight(at: iso("2026-06-01T21:00"), in: days))
    }

    func testNoSunTimesIsHandledRatherThanCrashing() {
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
@MainActor
final class SunUpTests: XCTestCase {

    func testTheSunIsUpAtMiddayAndDownAtMidnight() {
        // Sydney is ten hours ahead of UTC in September.
        XCTAssertTrue(SolarPosition.isSunUp(at: iso("2026-09-13T02:00"), latitude: -33.87, longitude: 151.21))
        XCTAssertFalse(SolarPosition.isSunUp(at: iso("2026-09-13T14:00"), latitude: -33.87, longitude: 151.21))
    }

    /// London's sunset on 13 September, by Open-Meteo, was 18:19 UTC.
    func testItSetsWithinMinutesOfTheForecastsOwnSunset() {
        XCTAssertTrue(SolarPosition.isSunUp(at: iso("2026-09-13T18:12"), latitude: 51.51, longitude: -0.13))
        XCTAssertFalse(SolarPosition.isSunUp(at: iso("2026-09-13T18:26"), latitude: 51.51, longitude: -0.13))
    }

    func testTheMidnightSunAndThePolarNight() {
        // Longyearbyen, Svalbard: up at 1:30 am local in June, down at noon in December.
        XCTAssertTrue(SolarPosition.isSunUp(at: iso("2026-06-21T23:30"), latitude: 78.22, longitude: 15.65))
        XCTAssertFalse(SolarPosition.isSunUp(at: iso("2026-12-21T11:00"), latitude: 78.22, longitude: 15.65))
    }
}
