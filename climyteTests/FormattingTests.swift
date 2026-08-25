//
//  FormattingTests.swift
//  climyteTests
//

import XCTest
@testable import climyte

final class FormattingTests: XCTestCase {

    // MARK: - Temperature

    func testMetricTemperatureRoundsToNearestWholeNumber() {
        XCTAssertEqual(UnitSystem.metric.temperature(22.4), "22°")
        XCTAssertEqual(UnitSystem.metric.temperature(22.5), "23°")
        XCTAssertEqual(UnitSystem.metric.temperature(-0.4), "0°")
        XCTAssertEqual(UnitSystem.metric.temperature(-3.6), "-4°")
    }

    func testImperialTemperatureConvertsFromCelsius() {
        XCTAssertEqual(UnitSystem.imperial.temperature(0), "32°")
        XCTAssertEqual(UnitSystem.imperial.temperature(100), "212°")
        XCTAssertEqual(UnitSystem.imperial.temperature(-40), "-40°")
        XCTAssertEqual(UnitSystem.imperial.temperature(22.5), "73°")
    }

    func testWindSpeedConvertsAndLabelsItsUnit() {
        XCTAssertEqual(UnitSystem.metric.windSpeed(12), "12 km/h")
        XCTAssertEqual(UnitSystem.imperial.windSpeed(100), "62 mph")
        XCTAssertEqual(UnitSystem.imperial.windSpeed(0), "0 mph")
    }

    func testVisibilityConvertsAndLabelsItsUnit() {
        XCTAssertEqual(UnitSystem.metric.visibility(10), "10 km")
        XCTAssertEqual(UnitSystem.imperial.visibility(10), "6 mi")
    }

    func testToggleFlipsBetweenSystems() {
        XCTAssertEqual(UnitSystem.metric.toggled, .imperial)
        XCTAssertEqual(UnitSystem.imperial.toggled, .metric)
    }

    // MARK: - Stale data age

    func testStaleAgeUsesTheLargestSensibleUnit() {
        let now = Date()
        func age(_ secondsAgo: TimeInterval) -> String {
            StaleDataNotice.age(of: now.addingTimeInterval(-secondsAgo), relativeTo: now)
        }

        XCTAssertEqual(age(10), "Showing readings from just now.")
        XCTAssertEqual(age(60 * 5), "Showing readings from 5m ago.")
        XCTAssertEqual(age(60 * 90), "Showing readings from 1h ago.")
        XCTAssertEqual(age(60 * 60 * 50), "Showing readings from 2d ago.")
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
