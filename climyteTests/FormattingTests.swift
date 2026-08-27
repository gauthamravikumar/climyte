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

    // MARK: - Unit selection

    func testFahrenheitCountriesUseImperial() {
        XCTAssertEqual(UnitSystem.forCountry(code: "US", name: "United States"), .imperial)
        XCTAssertEqual(UnitSystem.forCountry(code: "us", name: nil), .imperial, "Code match is case-insensitive")
        XCTAssertEqual(UnitSystem.forCountry(code: "BZ", name: nil), .imperial)
        XCTAssertEqual(UnitSystem.forCountry(code: "KY", name: nil), .imperial)
    }

    func testEverywhereElseUsesMetric() {
        XCTAssertEqual(UnitSystem.forCountry(code: "AU", name: "Australia"), .metric)
        XCTAssertEqual(UnitSystem.forCountry(code: "FR", name: "France"), .metric)
        XCTAssertEqual(UnitSystem.forCountry(code: "GB", name: "United Kingdom"), .metric)
        XCTAssertEqual(UnitSystem.forCountry(code: "JP", name: "Japan"), .metric)
    }

    /// Cities saved before the ISO code was stored decode without one; the
    /// country name is the only thing left to go on.
    func testFallsBackToCountryNameWhenNoCodeIsStored() {
        XCTAssertEqual(UnitSystem.forCountry(code: nil, name: "United States"), .imperial)
        XCTAssertEqual(UnitSystem.forCountry(code: nil, name: "France"), .metric)
    }

    /// A stored code wins outright — the name is not consulted, so a
    /// mismatched pair can't flip a city to the wrong units.
    func testAStoredCodeTakesPrecedenceOverTheName() {
        XCTAssertEqual(UnitSystem.forCountry(code: "FR", name: "United States"), .metric)
    }

    func testUnknownCountryFallsBackToMetric() {
        XCTAssertEqual(UnitSystem.forCountry(code: nil, name: nil), .metric)
        XCTAssertEqual(UnitSystem.forCountry(code: "ZZ", name: "Nowhere"), .metric)
    }

    func testCityDerivesItsOwnUnits() {
        let denver = City(id: UUID(), name: "Denver", country: "United States",
                          countryCode: "US", latitude: 39.74, longitude: -104.98)
        let paris = City(id: UUID(), name: "Paris", country: "France",
                         countryCode: "FR", latitude: 48.85, longitude: 2.35)

        XCTAssertEqual(denver.unitSystem, .imperial)
        XCTAssertEqual(paris.unitSystem, .metric)
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
        func description(_ speed: Double) -> String {
            String(localized: WeatherDetailsView.windDescription(speed))
        }

        XCTAssertEqual(description(0), "Light air")
        XCTAssertEqual(description(4.9), "Light air")
        XCTAssertEqual(description(5), "Light breeze")
        XCTAssertEqual(description(19.9), "Gentle breeze")
        XCTAssertEqual(description(20), "Moderate breeze")
        XCTAssertEqual(description(49.9), "Strong breeze")
        XCTAssertEqual(description(50), "High wind")
        XCTAssertEqual(description(120), "High wind")
    }

    // MARK: - Condition summary

    func testSummaryOmitsApparentTemperatureWhenItMatches() {
        XCTAssertEqual(
            CurrentConditionsView.summary(condition: "Sunny", actual: 61, apparent: 61),
            "Sunny"
        )
    }

    func testSummaryReportsAWarmerApparentTemperature() {
        XCTAssertEqual(
            CurrentConditionsView.summary(condition: "Cloudy", actual: 21, apparent: 23),
            "Cloudy · feels 2° warmer"
        )
    }

    func testSummaryReportsACoolerApparentTemperatureAsAPositiveNumber() {
        XCTAssertEqual(
            CurrentConditionsView.summary(condition: "Windy", actual: 12, apparent: 8),
            "Windy · feels 4° cooler"
        )
    }

    /// The difference is taken from already-converted values, so a 2°C gap
    /// reads as 4° to a Fahrenheit reader rather than 2°.
    func testDifferenceIsExpressedInTheDisplayedUnit() {
        let actualC = 20.0, apparentC = 22.0

        let metric = CurrentConditionsView.summary(
            condition: "Cloudy",
            actual: UnitSystem.metric.temperatureValue(actualC),
            apparent: UnitSystem.metric.temperatureValue(apparentC)
        )
        let imperial = CurrentConditionsView.summary(
            condition: "Cloudy",
            actual: UnitSystem.imperial.temperatureValue(actualC),
            apparent: UnitSystem.imperial.temperatureValue(apparentC)
        )

        XCTAssertEqual(metric, "Cloudy · feels 2° warmer")
        XCTAssertEqual(imperial, "Cloudy · feels 4° warmer")
    }

    /// Rounding can collapse a sub-degree difference to nothing; the line
    /// should disappear rather than claim "0° warmer".
    func testSubDegreeDifferenceIsTreatedAsNoDifference() {
        XCTAssertEqual(
            CurrentConditionsView.summary(
                condition: "Sunny",
                actual: UnitSystem.metric.temperatureValue(21.1),
                apparent: UnitSystem.metric.temperatureValue(21.4)
            ),
            "Sunny"
        )
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
