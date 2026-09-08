//
//  SolarPositionTests.swift
//  climyteTests
//

import XCTest
@testable import climyte

/// The sun's position drives both the arc and the light on the background, so
/// an error here puts the light on the wrong side of the screen without
/// anything failing.
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

    func testElevationPeaksAtMiddayAndIsZeroAtTheHorizons() {
        XCTAssertEqual(SolarPosition.elevation(at: iso("2026-06-01T13:00"), in: days), 1, accuracy: 0.001)
        XCTAssertEqual(SolarPosition.elevation(at: iso("2026-06-01T06:00"), in: days), 0, accuracy: 0.001)
        XCTAssertEqual(SolarPosition.elevation(at: iso("2026-06-01T20:00"), in: days), 0, accuracy: 0.001)
    }

    func testElevationIsZeroAtNight() {
        XCTAssertEqual(SolarPosition.elevation(at: iso("2026-06-01T02:00"), in: days), 0)
    }

    func testRemainingDaylightCountsDownToSunset() {
        let left = SolarPosition.remainingDaylight(at: iso("2026-06-01T19:00"), in: days)
        XCTAssertEqual(left ?? 0, 3600, accuracy: 1)
        XCTAssertNil(SolarPosition.remainingDaylight(at: iso("2026-06-01T21:00"), in: days))
    }

    func testNoSunTimesIsHandledRatherThanCrashing() {
        XCTAssertNil(SolarPosition.daylightProgress(at: Date(), in: []))
        XCTAssertEqual(SolarPosition.elevation(at: Date(), in: []), 0)
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

/// The horizon keeps its light after the sun has gone. Without that the
/// screen would invert to dark and the light would vanish in the same
/// instant — the one moment the design exists for would never render.
@MainActor
final class HorizonLightTests: XCTestCase {

    private let days = [SolarDay(sunrise: iso2("2026-06-01T06:00"),
                                 sunset: iso2("2026-06-01T20:00"))]

    func testTheLightIsFullStrengthAndTracksTheSunByDay() {
        let noon = SolarPosition.horizonLight(at: iso2("2026-06-01T13:00"), in: days)
        XCTAssertEqual(noon?.intensity ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(noon?.position ?? -1, 0.5, accuracy: 0.001)
    }

    func testTheLightStaysInTheWestAndFadesAfterSunset() {
        let justAfter = SolarPosition.horizonLight(at: iso2("2026-06-01T20:08"), in: days)
        XCTAssertEqual(justAfter?.position ?? -1, 1, accuracy: 0.001, "It set in the west")
        XCTAssertEqual(justAfter?.intensity ?? 0, 0.75, accuracy: 0.02)

        let later = SolarPosition.horizonLight(at: iso2("2026-06-01T20:24"), in: days)
        XCTAssertLessThan(later?.intensity ?? 1, justAfter?.intensity ?? 0)
    }

    func testTheLightGathersInTheEastBeforeSunrise() {
        let beforeDawn = SolarPosition.horizonLight(at: iso2("2026-06-01T05:44"), in: days)
        XCTAssertEqual(beforeDawn?.position ?? -1, 0, accuracy: 0.001)
        XCTAssertGreaterThan(beforeDawn?.intensity ?? 0, 0)
    }

    func testThereIsNoLightInTheMiddleOfTheNight() {
        XCTAssertNil(SolarPosition.horizonLight(at: iso2("2026-06-01T02:00"), in: days))
        XCTAssertNil(SolarPosition.horizonLight(at: iso2("2026-06-01T21:30"), in: days))
    }

    func testNoSunTimesMeansNoLightRatherThanACrash() {
        XCTAssertNil(SolarPosition.horizonLight(at: Date(), in: []))
    }
}

private func iso2(_ string: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.calendar = Calendar(identifier: .gregorian)
    f.dateFormat = "yyyy-MM-dd'T'HH:mm"
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f.date(from: string)!
}
