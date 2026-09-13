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

    /// Forty degrees north, where dusk in early June runs about 32 minutes —
    /// the fixed window these cases were written against.
    private static let latitude = 40.0

    func testTheLightIsFullStrengthAndTracksTheSunByDay() {
        let noon = SolarPosition.horizonLight(at: iso2("2026-06-01T13:00"), in: days, latitude: Self.latitude)
        XCTAssertEqual(noon?.intensity ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(noon?.position ?? -1, 0.5, accuracy: 0.001)
    }

    func testTheLightStaysInTheWestAndFadesAfterSunset() {
        let justAfter = SolarPosition.horizonLight(at: iso2("2026-06-01T20:08"), in: days, latitude: Self.latitude)
        XCTAssertEqual(justAfter?.position ?? -1, 1, accuracy: 0.001, "It set in the west")
        XCTAssertEqual(justAfter?.intensity ?? 0, 0.75, accuracy: 0.02)

        let later = SolarPosition.horizonLight(at: iso2("2026-06-01T20:24"), in: days, latitude: Self.latitude)
        XCTAssertLessThan(later?.intensity ?? 1, justAfter?.intensity ?? 0)
    }

    func testTheLightGathersInTheEastBeforeSunrise() {
        let beforeDawn = SolarPosition.horizonLight(at: iso2("2026-06-01T05:44"), in: days, latitude: Self.latitude)
        XCTAssertEqual(beforeDawn?.position ?? -1, 0, accuracy: 0.001)
        XCTAssertGreaterThan(beforeDawn?.intensity ?? 0, 0)
    }

    func testThereIsNoLightInTheMiddleOfTheNight() {
        XCTAssertNil(SolarPosition.horizonLight(at: iso2("2026-06-01T02:00"), in: days, latitude: Self.latitude))
        XCTAssertNil(SolarPosition.horizonLight(at: iso2("2026-06-01T21:30"), in: days, latitude: Self.latitude))
    }

    func testNoSunTimesMeansNoLightRatherThanACrash() {
        XCTAssertNil(SolarPosition.horizonLight(at: Date(), in: [], latitude: Self.latitude))
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

/// Dusk lasts as long as the sun takes to sink six degrees below the horizon,
/// and that depends on how steeply it sets: nearly straight down at the
/// equator, on a long slant towards the poles. A fixed half hour was right
/// only in between.
@MainActor
final class CivilTwilightTests: XCTestCase {

    private func minutes(_ latitude: Double, _ day: String) -> Double? {
        SolarPosition.civilTwilight(latitude: latitude, on: iso2("\(day)T12:00")).map { $0 / 60 }
    }

    func testDuskIsShortAtTheEquator() {
        XCTAssertEqual(minutes(1.35, "2026-09-13") ?? 0, 21, accuracy: 1.5, "Singapore")
    }

    func testDuskLengthensTowardThePoles() {
        XCTAssertEqual(minutes(51.5, "2026-09-13") ?? 0, 34, accuracy: 1.5, "London in September")
        XCTAssertEqual(minutes(51.5, "2026-06-21") ?? 0, 48, accuracy: 2, "London in June")
        XCTAssertEqual(minutes(59.9, "2026-06-21") ?? 0, 104, accuracy: 6, "Oslo in June")
    }

    func testTheLongDusksAreInTheSouthernSummer() {
        XCTAssertEqual(minutes(-37.8, "2026-12-21") ?? 0, 31, accuracy: 1.5, "Melbourne in December")
        XCTAssertEqual(minutes(-37.8, "2026-09-13") ?? 0, 26, accuracy: 1.5, "Melbourne in September")
    }

    /// Reykjavík in June: the sun never gets six degrees down, so dusk runs
    /// straight into dawn and there is no end to count to.
    func testANightThatNeverGetsDarkHasNoEndToDusk() {
        XCTAssertNil(minutes(64.15, "2026-06-21"))
    }
}

/// The glow now lasts as long as the city's own dusk.
@MainActor
final class DuskByLatitudeTests: XCTestCase {

    private let june = [SolarDay(sunrise: iso2("2026-06-21T05:00"), sunset: iso2("2026-06-21T21:00")),
                        SolarDay(sunrise: iso2("2026-06-22T05:00"), sunset: iso2("2026-06-22T21:00"))]

    func testTheEquatorsGlowIsGoneBeforeHalfAnHour() {
        // 26 minutes after sunset: past the equator's dusk of about 23.
        XCTAssertNil(SolarPosition.horizonLight(at: iso2("2026-06-21T21:26"), in: june, latitude: 1.35))
    }

    func testLondonsSummerGlowOutlastsHalfAnHour() {
        // 40 minutes after sunset: London's June dusk runs about 48.
        let light = SolarPosition.horizonLight(at: iso2("2026-06-21T21:40"), in: june, latitude: 51.5)
        XCTAssertNotNil(light)
        XCTAssertEqual(light?.position ?? -1, 1, accuracy: 0.001, "Still in the west")
    }

    /// Before dawn the light gathers in the east against that morning's own
    /// sunrise — not the previous day's, which has already passed and left
    /// every dawn after the first without a glow.
    func testTheGlowGathersBeforeTheSecondMorningsSunrise() {
        let beforeDawn = SolarPosition.horizonLight(at: iso2("2026-06-22T04:45"), in: june, latitude: 40)
        XCTAssertEqual(beforeDawn?.position ?? -1, 0, accuracy: 0.001)
        XCTAssertGreaterThan(beforeDawn?.intensity ?? 0, 0)
    }

    /// A night that never gets dark keeps its glow. It drifts from west to
    /// east across the night and dims only as far as the sun actually sinks —
    /// in Reykjavík in June, to about seven tenths at the darkest point.
    func testANightThatNeverGetsDarkKeepsItsGlowAllNight() {
        let deepest = SolarPosition.horizonLight(at: iso2("2026-06-22T01:00"), in: june, latitude: 64.15)
        XCTAssertEqual(deepest?.position ?? -1, 0.5, accuracy: 0.01)
        XCTAssertEqual(deepest?.intensity ?? 0, 0.7, accuracy: 0.05)

        let evening = SolarPosition.horizonLight(at: iso2("2026-06-21T22:00"), in: june, latitude: 64.15)
        XCTAssertGreaterThan(evening?.position ?? 0, deepest?.position ?? 1)
        XCTAssertGreaterThan(evening?.intensity ?? 0, deepest?.intensity ?? 1)
    }
}

/// Whether the sun is up, from the sun itself. A forecast's sun times cover
/// only its own days, and a saved forecast old enough for all of them to have
/// passed left the page judging today against a sunset a week gone — dark all
/// day.
@MainActor
final class SunUpTests: XCTestCase {

    func testTheSunIsUpAtMiddayAndDownAtMidnight() {
        // Sydney is ten hours ahead of UTC in September.
        XCTAssertTrue(SolarPosition.isSunUp(at: iso2("2026-09-13T02:00"), latitude: -33.87, longitude: 151.21))
        XCTAssertFalse(SolarPosition.isSunUp(at: iso2("2026-09-13T14:00"), latitude: -33.87, longitude: 151.21))
    }

    /// London's sunset on 13 September, by Open-Meteo, was 18:19 UTC.
    func testItSetsWithinMinutesOfTheForecastsOwnSunset() {
        XCTAssertTrue(SolarPosition.isSunUp(at: iso2("2026-09-13T18:12"), latitude: 51.51, longitude: -0.13))
        XCTAssertFalse(SolarPosition.isSunUp(at: iso2("2026-09-13T18:26"), latitude: 51.51, longitude: -0.13))
    }

    func testTheMidnightSunAndThePolarNight() {
        // Longyearbyen, Svalbard: up at 1:30 am local in June, down at noon in December.
        XCTAssertTrue(SolarPosition.isSunUp(at: iso2("2026-06-21T23:30"), latitude: 78.22, longitude: 15.65))
        XCTAssertFalse(SolarPosition.isSunUp(at: iso2("2026-12-21T11:00"), latitude: 78.22, longitude: 15.65))
    }
}
