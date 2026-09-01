//
//  UnitsAndTimeZoneTests.swift
//  climyteTests
//

import XCTest
@testable import climyte

/// Units are chosen per country and per dimension; time zones come from the
/// city's IANA name rather than from a single instant's offset.
@MainActor
final class UnitsAndTimeZoneTests: XCTestCase {

    // MARK: - Per-dimension units

    func testTheUnitedStatesIsImperialThroughout() {
        let units = UnitSystem.forCountry(code: "US", name: "United States")

        XCTAssertEqual(units.temperature(0), "32°")
        XCTAssertEqual(units.windSpeed(100), "62 mph")
        XCTAssertEqual(units.visibility(10), "6 mi")
        XCTAssertTrue(units.precipitation(25.4).hasSuffix("in"))
    }

    /// The case the old single-enum model could not express, and got wrong.
    func testBritainIsCelsiusAndMillimetresButMilesAndMilesPerHour() {
        let units = UnitSystem.forCountry(code: "GB", name: "United Kingdom")

        XCTAssertEqual(units.temperature(20), "20°", "The Met Office forecasts in Celsius")
        XCTAssertEqual(units.windSpeed(100), "62 mph", "Wind is reported in mph")
        XCTAssertEqual(units.visibility(10), "6 mi", "Visibility is reported in miles")
        XCTAssertTrue(units.precipitation(9.5).hasSuffix("mm"), "Rainfall stays metric")
    }

    /// Fahrenheit and metric wind is a combination no country actually uses:
    /// where Fahrenheit survives, so do miles.
    func testFahrenheitCountriesAreImperialThroughout() {
        for code in ["BS", "BZ", "KY", "PW", "FM", "MH", "LR", "PR", "GU", "VI", "MP"] {
            let units = UnitSystem.forCountry(code: code, name: nil)

            XCTAssertEqual(units.temperatureUnit, .fahrenheit, code)
            XCTAssertEqual(units.speedUnit, .milesPerHour, code)
            XCTAssertEqual(units.distanceUnit, .miles, code)
        }
    }

    /// Celsius, but imperial road units — the British pattern.
    func testUKTerritoriesAndCommonwealthKeepCelsiusWithMiles() {
        for code in ["GB", "BM", "GI", "FK", "MM", "WS", "AG", "LC", "VG", "TC"] {
            let units = UnitSystem.forCountry(code: code, name: nil)

            XCTAssertEqual(units.temperatureUnit, .celsius, code)
            XCTAssertEqual(units.speedUnit, .milesPerHour, code)
            XCTAssertEqual(units.rainfallUnit, .millimetres, code)
        }
    }

    func testEverywhereElseIsFullyMetric() {
        for code in ["AU", "FR", "JP", "IN", "BR", "ZA", "CA", "DE"] {
            XCTAssertEqual(UnitSystem.forCountry(code: code, name: nil), .metric, code)
        }
    }

    /// A blank code is not a country. Treating it as one meant a legacy city
    /// with an empty string never reached the name fallback.
    func testABlankCodeFallsBackToTheCountryName() {
        XCTAssertEqual(UnitSystem.forCountry(code: "", name: "United States"), .imperial)
        XCTAssertEqual(UnitSystem.forCountry(code: "   ", name: "United Kingdom"), .british)
        XCTAssertEqual(UnitSystem.forCountry(code: nil, name: "United Kingdom"), .british)
    }

    func testAnUnknownCodeIsMetricRatherThanAGuess() {
        XCTAssertEqual(UnitSystem.forCountry(code: "ZZ", name: nil), .metric)
        XCTAssertEqual(UnitSystem.forCountry(code: nil, name: nil), .metric)
    }

    /// `String(format:)` has no locale and always emits a full stop, so a
    /// German reader saw "9.5 mm" where the language expects "9,5 mm".
    /// Run under `-testRegion DE` this asserts the comma; elsewhere it asserts
    /// whatever the reader's own separator is, which is the actual rule.
    func testRainfallUsesTheReadersDecimalSeparator() {
        let separator = Locale.current.decimalSeparator ?? "."
        let rendered = UnitSystem.metric.precipitation(9.5)

        XCTAssertTrue(rendered.contains("9\(separator)5"),
                      "Expected 9\(separator)5 in \(rendered)")

        let inches = UnitSystem.imperial.precipitation(25.4)
        XCTAssertTrue(inches.contains("1\(separator)00"), "Expected 1\(separator)00 in \(inches)")
    }

    // MARK: - Time zones

    /// The DST defect: a zone rebuilt from `utc_offset_seconds` answers with
    /// the offset in force when the response was fetched, and applies it to
    /// every date in the response — including dates on the other side of a
    /// transition.
    func testSunTimesAfterADSTTransitionResolveToTheRightInstant() throws {
        // Fetched in August, when Paris is on CEST (+2).
        let response = parisResponse(includeZoneName: true)
        let city = City(id: UUID(), name: "Paris", country: "France",
                        countryCode: "FR", latitude: 48.8566, longitude: 2.3522)

        let weather = CityWeather(city: city, response: response)
        XCTAssertEqual(weather.timeZone.identifier, "Europe/Paris")

        // 26 October is after the transition, so Paris is on CET (+1) and
        // 08:23 local is 07:23 UTC. Read through a fixed +2 it would be 06:23.
        let october = try XCTUnwrap(weather.solarDays.last)
        XCTAssertEqual(october.sunrise, isoUTC("2026-10-26T07:23:00Z"),
                       "An hour out means the widget inverts its palette at the wrong time")
    }

    /// Responses cached before the zone name was requested must still decode
    /// and still work, falling back to the offset.
    func testAResponseWithNoZoneNameStillDecodesAndFallsBack() throws {
        let response = parisResponse(includeZoneName: false)
        let city = City(id: UUID(), name: "Paris", country: "France",
                        countryCode: "FR", latitude: 48.8566, longitude: 2.3522)

        let weather = CityWeather(city: city, response: response)

        XCTAssertNil(response.timezone)
        XCTAssertEqual(weather.timeZone.secondsFromGMT(), 7200)
        XCTAssertFalse(weather.solarDays.isEmpty, "The fallback still produces sun times")
    }

    func testAnUnrecognisedZoneNameFallsBackRatherThanFailing() {
        var response = parisResponse(includeZoneName: true)
        response.timezone = "Mars/Olympus_Mons"

        let city = City(id: UUID(), name: "Nowhere", country: "Nowhere",
                        countryCode: "FR", latitude: 0, longitude: 0)
        XCTAssertEqual(CityWeather(city: city, response: response).timeZone.secondsFromGMT(), 7200)
    }

    // MARK: - Helpers

    private func isoUTC(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: string)!
    }

    /// A response fetched in Paris in August whose daily block reaches past the
    /// October DST transition.
    private func parisResponse(includeZoneName: Bool) -> WeatherResponse {
        WeatherResponse(
            latitude: 48.8566,
            longitude: 2.3522,
            utc_offset_seconds: 7200,
            timezone: includeZoneName ? "Europe/Paris" : nil,
            current: CurrentWeatherResponse(
                temperature_2m: 18, apparent_temperature: 18, is_day: 1,
                weather_code: 0, relative_humidity_2m: 60, dew_point_2m: 10,
                wind_speed_10m: 10, wind_gusts_10m: 12, visibility: 20_000
            ),
            hourly: HourlyWeatherResponse(time: [], temperature_2m: [], weather_code: []),
            daily: DailyWeatherResponse(
                time: ["2026-08-30", "2026-10-26"],
                weather_code: [0, 0],
                temperature_2m_max: [24, 14],
                temperature_2m_min: [12, 6],
                sunrise: ["2026-08-30T07:07", "2026-10-26T08:23"],
                sunset: ["2026-08-30T20:47", "2026-10-26T18:22"],
                uv_index_max: [4, 1],
                precipitation_probability_max: [0, 0],
                precipitation_sum: [0, 0],
                precipitation_hours: [0, 0],
                daylight_duration: [49_200, 35_940]
            )
        )
    }
}
