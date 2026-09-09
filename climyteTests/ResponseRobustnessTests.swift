//
//  ResponseRobustnessTests.swift
//  climyteTests
//

import XCTest
@testable import climyte

/// What the app does with a response, or a stored list, that isn't ideal.
@MainActor
final class ResponseRobustnessTests: XCTestCase {

    /// Open-Meteo sends null past the horizon of the model backing a field.
    /// The daily arrays were typed for that; the hourly ones were not, so one
    /// missing hour failed the whole decode and the reader was told the data
    /// couldn't be read — for a response that was almost entirely usable.
    func testANullHourIsSkippedRatherThanFailingTheWholeCity() throws {
        let json = """
        {"time":["2026-08-31T00:00","2026-08-31T01:00","2026-08-31T02:00"],
         "temperature_2m":[12.0,null,14.0],
         "weather_code":[0,1,null]}
        """.data(using: .utf8)!

        let hourly = try JSONDecoder().decode(HourlyWeatherResponse.self, from: json)

        XCTAssertEqual(hourly.temperature_2m.count, 3)
        XCTAssertNil(hourly.temperature_2m[1])
        XCTAssertNil(hourly.weather_code[2])
    }

    func testHoursWithNullValuesAreDroppedButTheRestSurvive() {
        let now = Date()
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.calendar = Calendar(identifier: .gregorian)
        stamp.dateFormat = "yyyy-MM-dd'T'HH:mm"
        stamp.timeZone = TimeZone(secondsFromGMT: 0)

        let times = (0..<4).map { stamp.string(from: now.addingTimeInterval(Double($0) * 3600)) }
        let response = TestResponse.make(
            hourly: HourlyWeatherResponse(
                time: times,
                temperature_2m: [12.0, nil, 14.0, 15.0],
                weather_code: [0, 0, nil, 0]
            )
        )

        let city = City(id: UUID(), name: "Testville", country: "Nowhere",
                        countryCode: "AU", latitude: 0, longitude: 0)
        let weather = CityWeather(city: city, response: response)

        XCTAssertEqual(weather.hourlyForecasts.count, 2,
                       "The two complete hours survive; the two with nulls are skipped")
        XCTAssertEqual(weather.hourlyForecasts.map(\.temperature), [12.0, 15.0])
    }

    /// `CityEntry.id` is `city.key` and the pager is a `ForEach` over those
    /// ids, so duplicates are undefined behaviour rather than a repeated row.
    func testDuplicateCitiesAreCollapsedOnTheWayInAndOut() throws {
        let suite = "climyteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // Two names, one location — City.key is built from the coordinates.
        let paris = City(id: UUID(), name: "Paris", country: "France",
                         countryCode: "FR", latitude: 48.8566, longitude: 2.3522)
        let alias = City(id: UUID(), name: "Paris, Île-de-France", country: "France",
                         countryCode: "FR", latitude: 48.8566, longitude: 2.3522)

        // Written directly, bypassing save's own guard, as a corrupted or
        // hand-edited store would be.
        defaults.set(try JSONEncoder().encode([paris, alias]), forKey: SavedCities.key)

        let loaded = SavedCities.load(from: defaults, sources: .none)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, "Paris", "The first occurrence wins")
    }

    func testSavingDropsDuplicatesToo() {
        let suite = "climyteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let tokyo = City(id: UUID(), name: "Tokyo", country: "Japan",
                         countryCode: "JP", latitude: 35.6762, longitude: 139.6503)

        SavedCities.save([tokyo, tokyo, tokyo], to: defaults, sources: .none)

        XCTAssertEqual(SavedCities.load(from: defaults, sources: .none).count, 1)
    }
}
