//
//  WeatherDetailsTests.swift
//  climyteTests
//

import XCTest
@testable import climyte

/// The details section is driven by relevance rules, so these cover which
/// rows appear rather than how they look.
final class WeatherDetailsTests: XCTestCase {

    // MARK: - Rain

    func testRainAppearsOnlyAboveTheChanceThreshold() {
        XCTAssertTrue(kinds(rainChance: 99).contains(.rain))
        XCTAssertTrue(kinds(rainChance: 20).contains(.rain), "Threshold is inclusive")
        XCTAssertFalse(kinds(rainChance: 19).contains(.rain))
        XCTAssertFalse(kinds(rainChance: 0).contains(.rain))
    }

    func testRainIsHiddenWhenTheApiHasNoProbability() {
        XCTAssertFalse(kinds(rainChance: nil).contains(.rain))
    }

    func testRainLeadsTheSection() {
        XCTAssertEqual(kinds(rainChance: 80).first, .rain)
    }

    func testRainCaptionDescribesAmountAndDuration() {
        let detail = details(rainChance: 80, rainAmount: 9.5, rainHours: 7)
            .first { $0.kind == .rain }

        // The separator follows the reader's locale — "9,5 mm" in German —
        // so assert the parts rather than one region's punctuation.
        let separator = Locale.current.decimalSeparator ?? "."
        XCTAssertEqual(detail?.caption, "9\(separator)5 mm over 7h")
    }

    /// A forecast can carry a chance without a measurable amount.
    func testRainCaptionIsOmittedWhenNoAmountIsExpected() {
        let detail = details(rainChance: 40, rainAmount: 0, rainHours: 0)
            .first { $0.kind == .rain }
        XCTAssertNotNil(detail)
        XCTAssertNil(detail?.caption)
    }

    // MARK: - UV

    func testUVAppearsOnlyInDaylightAndAboveTheProtectionThreshold() {
        XCTAssertTrue(kinds(uv: 8, isNight: false).contains(.uv))
        XCTAssertFalse(kinds(uv: 8, isNight: true).contains(.uv), "UV is meaningless at night")
        XCTAssertFalse(kinds(uv: 2, isNight: false).contains(.uv))
    }

    // MARK: - Humidity

    /// Relative humidity misleads in both directions, so the trigger is dew
    /// point: 85% at 11°C is not muggy, and 51% at 33°C is.
    func testHumidityUsesDewPointRatherThanRelativeHumidity() {
        XCTAssertFalse(kinds(dewPoint: 8.9).contains(.humidity), "Cool and damp is not humid")
        XCTAssertTrue(kinds(dewPoint: 21.8).contains(.humidity), "Warm and sticky is")
        XCTAssertTrue(kinds(dewPoint: 0).contains(.humidity), "Very dry is worth saying")
        XCTAssertFalse(kinds(dewPoint: 10).contains(.humidity), "Unremarkable stays hidden")
    }

    func testHumidLabelDiffersFromDryLabel() {
        let humid = details(dewPoint: 20).first { $0.kind == .humidity }
        let dry = details(dewPoint: 0).first { $0.kind == .humidity }
        XCTAssertNotEqual(humid?.label, dry?.label)
    }

    // MARK: - Wind

    func testGustsAreMentionedOnlyWhenTheyExceedTheAverage() {
        let gusty = details(windSpeed: 15, windGusts: 34).first { $0.kind == .wind }
        let steady = details(windSpeed: 15, windGusts: 18).first { $0.kind == .wind }

        XCTAssertNotNil(gusty?.caption)
        XCTAssertNil(steady?.caption)
    }

    // MARK: - Visibility

    func testVisibilityAppearsOnlyWhenReduced() {
        XCTAssertTrue(kinds(visibilityKm: 2).contains(.visibility))
        XCTAssertFalse(kinds(visibilityKm: 10).contains(.visibility),
                       "A tile that always reads 10 km is decoration")
    }

    // MARK: - Always present

    func testWindAndSunTimesAlwaysAppear() {
        let quiet = kinds(rainChance: 0, uv: 0, isNight: true, dewPoint: 10, visibilityKm: 30)
        XCTAssertTrue(quiet.contains(.wind))
        XCTAssertTrue(quiet.contains(.sunrise))
        XCTAssertTrue(quiet.contains(.sunset))
    }

    func testAQuietNightStillShowsSomething() {
        let quiet = kinds(rainChance: 0, uv: 0, isNight: true, dewPoint: 10, visibilityKm: 30)
        XCTAssertGreaterThanOrEqual(quiet.count, 3)
    }

    // MARK: - Daylight

    func testDurationIsFormattedInHoursAndMinutes() {
        XCTAssertEqual(WeatherDetails.duration(49993), "13h 53m")
        XCTAssertEqual(WeatherDetails.duration(3600), "1h 0m")
    }

    func testDaylightChangeNamesItsDirection() {
        XCTAssertEqual(WeatherDetails.daylightChange(-240), "4m shorter")
        XCTAssertEqual(WeatherDetails.daylightChange(120), "2m longer")
    }

    /// Sub-minute drift either way is not a change worth reporting.
    func testDaylightChangeIsOmittedWhenNegligible() {
        XCTAssertNil(WeatherDetails.daylightChange(20))
        XCTAssertNil(WeatherDetails.daylightChange(-20))
    }

    // MARK: - Helpers

    private func kinds(rainChance: Int? = 0,
                       rainAmount: Double? = 0,
                       rainHours: Double? = 0,
                       uv: Double = 0,
                       isNight: Bool = false,
                       dewPoint: Double = 10,
                       windSpeed: Double = 10,
                       windGusts: Double = 12,
                       visibilityKm: Double = 20) -> [WeatherDetail.Kind] {
        details(rainChance: rainChance, rainAmount: rainAmount, rainHours: rainHours,
                uv: uv, isNight: isNight, dewPoint: dewPoint,
                windSpeed: windSpeed, windGusts: windGusts,
                visibilityKm: visibilityKm).map(\.kind)
    }

    private func details(rainChance: Int? = 0,
                         rainAmount: Double? = 0,
                         rainHours: Double? = 0,
                         uv: Double = 0,
                         isNight: Bool = false,
                         dewPoint: Double = 10,
                         windSpeed: Double = 10,
                         windGusts: Double = 12,
                         visibilityKm: Double = 20) -> [WeatherDetail] {
        let weather = CityWeather(
            city: City(id: UUID(), name: "Test", country: "Testland",
                       countryCode: "AU", latitude: 0, longitude: 0),
            response: TestResponse.make(
                isDay: isNight ? 0 : 1,
                dewPoint: dewPoint,
                windSpeed: windSpeed,
                windGusts: windGusts,
                visibilityMetres: visibilityKm * 1000,
                uvIndex: uv,
                rainChance: rainChance,
                rainAmount: rainAmount,
                rainHours: rainHours
            )
        )
        return WeatherDetails.build(for: weather, units: .metric)
    }
}
