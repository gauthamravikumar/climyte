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

    /// Rain already under way gets its amount alone; the strip beneath the row
    /// says whether it is falling now.
    func testRainCaptionGivesTheAmountAhead() {
        let detail = details(rainChance: 80, rainAmount: 9.5, rainHours: 7)
            .first { $0.kind == .rain }

        // The separator follows the reader's locale — "9,5 mm" in German —
        // so assert the parts rather than one region's punctuation.
        let separator = Locale.current.decimalSeparator ?? "."
        XCTAssertEqual(detail?.caption, "9\(separator)5 mm")
    }

    /// A forecast can carry a chance without a measurable amount.
    func testRainCaptionIsOmittedWhenNoAmountIsExpected() {
        let detail = details(rainChance: 40, rainAmount: 0, rainHours: 0)
            .first { $0.kind == .rain }
        XCTAssertNotNil(detail)
        XCTAssertNil(detail?.caption)
    }

    // MARK: - Rain in the next two hours

    /// The day's threshold is meant for the rest of the day. A reader about to
    /// step outside is not helped by it.
    func testImminentRainEarnsTheRowOnAnUnlikelyDay() {
        let detail = details(rainChance: 5, minutely: [0, 0.4, 0.8, 0.2])
            .first { $0.kind == .rain }

        XCTAssertNotNil(detail, "rain within the hour should show even at 5% for the day")
        XCTAssertEqual(detail?.caption, "in the next 2 hours")
    }

    /// A dry outlook on a day never likely to rain has nothing to say, so the
    /// row goes the way Wind and UV do when they have nothing to say.
    func testADryOutlookOnAnUnlikelyDayLeavesNoRow() {
        XCTAssertFalse(kinds(rainChance: 5, minutely: [0, 0, 0]).contains(.rain))
    }

    /// The chance ahead keeps the row when it earns it; the next two hours are
    /// elaboration beneath, not a replacement for it.
    func testALikelyDayKeepsItsOwnFiguresInTheRow() {
        let detail = details(rainChance: 80, rainAmount: 9.5, rainHours: 7,
                             minutely: [0, 0.4]).first { $0.kind == .rain }

        let separator = Locale.current.decimalSeparator ?? "."
        XCTAssertEqual(detail?.caption, "9\(separator)5 mm")
    }

    func testWithoutMinutelyDataNothingChanges() {
        XCTAssertFalse(kinds(rainChance: 5, minutely: nil).contains(.rain))
        XCTAssertTrue(kinds(rainChance: 80, minutely: nil).contains(.rain))
    }

    // MARK: - Rain in the next day

    /// The bug that started this: London at 2 pm said 76% about rain that had
    /// stopped before 5 am. Hours that have already gone must not count.
    func testRainThatHasAlreadyFallenDoesNotEarnTheRow() {
        let hourStart = Date(timeIntervalSince1970:
            (Date().timeIntervalSince1970 / 3_600).rounded(.down) * 3_600)
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.calendar = Calendar(identifier: .gregorian)
        stamp.dateFormat = "yyyy-MM-dd'T'HH:mm"
        stamp.timeZone = TimeZone(identifier: "UTC")

        // Ten hours behind now and fourteen ahead, with rain and a 76% chance
        // only in the first five — all of which are over.
        let offsets = -10..<14
        let hourly = HourlyWeatherResponse(
            time: offsets.map { stamp.string(from: hourStart.addingTimeInterval(TimeInterval($0 * 3_600))) },
            temperature_2m: offsets.map { _ in nil },
            weather_code: offsets.map { _ in nil },
            precipitation: offsets.map { $0 < -5 ? 0.3 : 0 },
            precipitation_probability: offsets.map { $0 < -5 ? 76 : 0 }
        )
        let weather = CityWeather(
            city: City(id: UUID(), name: "London", country: "United Kingdom",
                       countryCode: "GB", latitude: 51.5, longitude: -0.13),
            response: TestResponse.make(rainChance: 76, rainAmount: 1.3, rainHours: 4, hourly: hourly)
        )

        XCTAssertEqual(weather.precipitationChance, 0, "only hours still ahead count")
        XCTAssertFalse(WeatherDetails.build(for: weather, units: .metric).map(\.kind).contains(.rain),
                       "the day's own 76% must no longer reach the row")
    }

    /// When it starts is the part worth knowing a day ahead.
    func testTheCaptionSaysWhenLaterToday() {
        let (now, timeZone) = Self.captionClock()
        let start = now.addingTimeInterval(3 * 3_600)
        XCTAssertEqual(
            WeatherDetails.rainCaption(amount: "3 mm", start: start, now: now, timeZone: timeZone),
            "3 mm from \(Self.clock(start, timeZone))"
        )
    }

    func testTheCaptionSaysTomorrowWhenItIs() {
        let (now, timeZone) = Self.captionClock()
        let start = now.addingTimeInterval(18 * 3_600)
        XCTAssertEqual(
            WeatherDetails.rainCaption(amount: "3 mm", start: start, now: now, timeZone: timeZone),
            "3 mm from \(Self.clock(start, timeZone)) tomorrow"
        )
    }

    func testRainAlreadyUnderWayGetsTheAmountAlone() {
        let (now, timeZone) = Self.captionClock()
        XCTAssertEqual(
            WeatherDetails.rainCaption(amount: "3 mm", start: now.addingTimeInterval(-600),
                                       now: now, timeZone: timeZone),
            "3 mm"
        )
    }

    /// 1:20 pm UTC, so three hours on is still today and eighteen is tomorrow.
    private static func captionClock() -> (Date, TimeZone) {
        (Date(timeIntervalSince1970: 1_788_960_000), TimeZone(secondsFromGMT: 0)!)
    }

    /// Built with the app's own style, so the expectation holds in the German
    /// and Thai regions CI also runs, where the clock reads differently.
    private static func clock(_ date: Date, _ timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(timeZone: timeZone).hour(.defaultDigits(amPM: .abbreviated)))
            .lowercased()
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

    func testWindAlwaysAppears() {
        let quiet = kinds(rainChance: 0, uv: 0, isNight: true, dewPoint: 10, visibilityKm: 30)
        XCTAssertTrue(quiet.contains(.wind))
    }

    func testAQuietNightStillShowsSomething() {
        let quiet = kinds(rainChance: 0, uv: 0, isNight: true, dewPoint: 10, visibilityKm: 30)
        XCTAssertGreaterThanOrEqual(quiet.count, 1, "An empty section is worse than a plain one")
        XCTAssertTrue(quiet.contains(.wind))
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
                       visibilityKm: Double = 20,
                       minutely: [Double?]? = nil) -> [WeatherDetail.Kind] {
        details(rainChance: rainChance, rainAmount: rainAmount, rainHours: rainHours,
                uv: uv, isNight: isNight, dewPoint: dewPoint,
                windSpeed: windSpeed, windGusts: windGusts,
                visibilityKm: visibilityKm, minutely: minutely).map(\.kind)
    }

    private func details(rainChance: Int? = 0,
                         rainAmount: Double? = 0,
                         rainHours: Double? = 0,
                         uv: Double = 0,
                         isNight: Bool = false,
                         dewPoint: Double = 10,
                         windSpeed: Double = 10,
                         windGusts: Double = 12,
                         visibilityKm: Double = 20,
                         minutely: [Double?]? = nil) -> [WeatherDetail] {
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
                rainHours: rainHours,
                minutelyPrecipitation: minutely
            )
        )
        return WeatherDetails.build(for: weather, units: .metric)
    }
}
