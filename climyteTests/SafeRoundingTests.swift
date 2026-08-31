//
//  SafeRoundingTests.swift
//  climyteTests
//

import XCTest
@testable import climyte

/// Every number the app displays is rounded from a Double a remote service
/// sent. `Int(_:)` traps on infinity and NaN, so each of those roundings was a
/// way for the weather API to terminate the app.
@MainActor
final class SafeRoundingTests: XCTestCase {

    func testOrdinaryValuesRoundNormally() {
        XCTAssertEqual((21.4).toInt(), 21)
        XCTAssertEqual((21.5).toInt(), 22)
        XCTAssertEqual((-3.5).toInt(), -4)
        XCTAssertEqual((0.0).toInt(), 0)
    }

    func testTowardZeroTruncates() {
        XCTAssertEqual((2.9).toInt(.towardZero), 2)
        XCTAssertEqual((-2.9).toInt(.towardZero), -2)
    }

    func testInfinitySaturatesInsteadOfTrapping() {
        XCTAssertEqual(Double.infinity.toInt(), .max)
        XCTAssertEqual((-Double.infinity).toInt(), .min)
    }

    func testValuesBeyondIntRangeSaturate() {
        XCTAssertEqual(1e300.toInt(), .max)
        XCTAssertEqual((-1e300).toInt(), .min)
        XCTAssertEqual(Double.greatestFiniteMagnitude.toInt(), .max)
    }

    func testNaNBecomesZeroRatherThanCrashing() {
        XCTAssertEqual(Double.nan.toInt(), 0)
        XCTAssertEqual(Double.signalingNaN.toInt(), 0)
    }

    /// The end-to-end version: a response carrying absurd numbers must render
    /// something, however meaningless, rather than terminate the process.
    func testAnAbsurdResponseRendersRatherThanCrashing() {
        let city = City(id: UUID(), name: "Nowhere", country: "Nowhere",
                        countryCode: "AU", latitude: 0, longitude: 0)
        let response = TestResponse.make(
            temperature: .infinity,
            apparent: .infinity,
            humidity: .infinity,
            windSpeed: 1e308,
            windGusts: 1e308,
            visibilityMetres: -1e308,
            maxTemp: .infinity,
            minTemp: -.infinity
        )

        let weather = CityWeather(city: city, response: response)
        let units = UnitSystem.metric

        // Each of these traps on the unguarded conversion.
        XCTAssertFalse(units.temperature(weather.temperature).isEmpty)
        XCTAssertFalse(units.windSpeed(weather.windSpeed).isEmpty)
        XCTAssertFalse(units.visibility(weather.visibility).isEmpty)
        XCTAssertEqual(weather.humidity, .max)
    }
}
