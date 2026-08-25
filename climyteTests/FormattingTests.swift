//
//  FormattingTests.swift
//  climyteTests
//

import XCTest
@testable import climyte

final class FormattingTests: XCTestCase {

    // MARK: - Temperature

    func testDegreesRoundsToNearestWholeNumber() {
        XCTAssertEqual(CurrentConditionsView.degrees(22.4), "22°")
        XCTAssertEqual(CurrentConditionsView.degrees(22.5), "23°")
        XCTAssertEqual(CurrentConditionsView.degrees(-0.4), "0°")
        XCTAssertEqual(CurrentConditionsView.degrees(-3.6), "-4°")
    }

    // MARK: - UV index

    /// The category has to agree with the rounded number shown beside it —
    /// 2.4 displays as "2", which the WHO scale calls Low, not Moderate.
    func testUVIndexCategoryMatchesTheRoundedValue() {
        XCTAssertEqual(WeatherDetailsView.uvIndex(2.4), "2 Low")
        XCTAssertEqual(WeatherDetailsView.uvIndex(2.6), "3 Mod")
        XCTAssertEqual(WeatherDetailsView.uvIndex(5.4), "5 Mod")
        XCTAssertEqual(WeatherDetailsView.uvIndex(5.6), "6 High")
        XCTAssertEqual(WeatherDetailsView.uvIndex(7.6), "8 Very High")
        XCTAssertEqual(WeatherDetailsView.uvIndex(11.0), "11 Extreme")
    }

    func testUVIndexHandlesZero() {
        XCTAssertEqual(WeatherDetailsView.uvIndex(0), "0 Low")
    }

    // MARK: - Wind

    func testWindDescriptionCoversTheBeaufortBands() {
        XCTAssertEqual(WeatherDetailsView.windDescription(0), "Light air")
        XCTAssertEqual(WeatherDetailsView.windDescription(4.9), "Light air")
        XCTAssertEqual(WeatherDetailsView.windDescription(5), "Light breeze")
        XCTAssertEqual(WeatherDetailsView.windDescription(19.9), "Gentle breeze")
        XCTAssertEqual(WeatherDetailsView.windDescription(20), "Moderate breeze")
        XCTAssertEqual(WeatherDetailsView.windDescription(49.9), "Strong breeze")
        XCTAssertEqual(WeatherDetailsView.windDescription(50), "High wind")
        XCTAssertEqual(WeatherDetailsView.windDescription(120), "High wind")
    }

    // MARK: - Local time

    func testLocalTimeReflectsTheCitysOffsetRatherThanTheDevices() {
        let instant = Date(timeIntervalSince1970: 1_753_440_000)

        let sydney = CurrentConditionsView.localTime(at: instant, utcOffsetSeconds: 36000)
        let london = CurrentConditionsView.localTime(at: instant, utcOffsetSeconds: 3600)

        XCTAssertNotEqual(sydney, london, "Same instant in different zones should render differently")
    }

    func testLocalTimeAdvancesWithTheClock() {
        let instant = Date(timeIntervalSince1970: 1_753_440_000)
        let anHourLater = instant.addingTimeInterval(3600)

        XCTAssertNotEqual(
            CurrentConditionsView.localTime(at: instant, utcOffsetSeconds: 0),
            CurrentConditionsView.localTime(at: anHourLater, utcOffsetSeconds: 0)
        )
    }

    func testLocalTimeFallsBackToDeviceZoneForAbsurdOffsets() {
        let instant = Date(timeIntervalSince1970: 1_753_440_000)

        // TimeZone(secondsFromGMT:) returns nil beyond ±18h; must not crash.
        let result = CurrentConditionsView.localTime(at: instant, utcOffsetSeconds: 999_999)

        XCTAssertFalse(result.isEmpty)
    }
}
