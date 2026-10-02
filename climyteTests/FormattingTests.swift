//
//  FormattingTests.swift
//  climyteTests
//

import XCTest
@testable import climyte

nonisolated final class FormattingTests: XCTestCase {

    // MARK: - Temperature

    @MainActor func testMetricTemperatureRoundsToNearestWholeNumber() {
        XCTAssertEqual(UnitSystem.metric.temperature(22.4), "22°")
        XCTAssertEqual(UnitSystem.metric.temperature(22.5), "23°")
        XCTAssertEqual(UnitSystem.metric.temperature(-0.4), "0°")
        XCTAssertEqual(UnitSystem.metric.temperature(-3.6), "-4°")
    }

    @MainActor func testImperialTemperatureConvertsFromCelsius() {
        XCTAssertEqual(UnitSystem.imperial.temperature(0), "32°")
        XCTAssertEqual(UnitSystem.imperial.temperature(100), "212°")
        XCTAssertEqual(UnitSystem.imperial.temperature(-40), "-40°")
        XCTAssertEqual(UnitSystem.imperial.temperature(22.5), "73°")
    }

    @MainActor func testWindSpeedConvertsAndLabelsItsUnit() {
        XCTAssertEqual(UnitSystem.metric.windSpeed(12), "12 km/h")
        XCTAssertEqual(UnitSystem.imperial.windSpeed(100), "62 mph")
        XCTAssertEqual(UnitSystem.imperial.windSpeed(0), "0 mph")
    }

    @MainActor func testVisibilityConvertsAndLabelsItsUnit() {
        XCTAssertEqual(UnitSystem.metric.visibility(10), "10 km")
        XCTAssertEqual(UnitSystem.imperial.visibility(10), "6 mi")
    }

    // MARK: - Unit selection

    @MainActor func testFahrenheitCountriesUseImperial() {
        XCTAssertEqual(UnitSystem.forCountry(code: "US", name: "United States"), .imperial)
        XCTAssertEqual(UnitSystem.forCountry(code: "us", name: nil), .imperial, "Code match is case-insensitive")
        XCTAssertEqual(UnitSystem.forCountry(code: "BZ", name: nil), .imperial)
        XCTAssertEqual(UnitSystem.forCountry(code: "KY", name: nil), .imperial)
    }

    @MainActor func testEverywhereElseUsesMetric() {
        XCTAssertEqual(UnitSystem.forCountry(code: "AU", name: "Australia"), .metric)
        XCTAssertEqual(UnitSystem.forCountry(code: "FR", name: "France"), .metric)
        XCTAssertEqual(UnitSystem.forCountry(code: "JP", name: "Japan"), .metric)
    }

    /// Britain was filed under metric because a two-value enum had nowhere
    /// else to put it, which meant showing wind in km/h to a country whose
    /// forecasts are in mph. Celsius was the half that model got right.
    @MainActor func testBritainIsItsOwnMixture() {
        XCTAssertEqual(UnitSystem.forCountry(code: "GB", name: "United Kingdom"), .british)
        XCTAssertNotEqual(UnitSystem.forCountry(code: "GB", name: nil), .metric)
    }

    /// Cities saved before the ISO code was stored decode without one; the
    /// country name is the only thing left to go on.
    @MainActor func testFallsBackToCountryNameWhenNoCodeIsStored() {
        XCTAssertEqual(UnitSystem.forCountry(code: nil, name: "United States"), .imperial)
        XCTAssertEqual(UnitSystem.forCountry(code: nil, name: "France"), .metric)
    }

    /// A stored code wins outright — the name is not consulted, so a
    /// mismatched pair can't flip a city to the wrong units.
    @MainActor func testAStoredCodeTakesPrecedenceOverTheName() {
        XCTAssertEqual(UnitSystem.forCountry(code: "FR", name: "United States"), .metric)
    }

    @MainActor func testUnknownCountryFallsBackToMetric() {
        XCTAssertEqual(UnitSystem.forCountry(code: nil, name: nil), .metric)
        XCTAssertEqual(UnitSystem.forCountry(code: "ZZ", name: "Nowhere"), .metric)
    }

    @MainActor func testCityDerivesItsOwnUnits() {
        let denver = City(id: UUID(), name: "Denver", country: "United States",
                          countryCode: "US", latitude: 39.74, longitude: -104.98)
        let paris = City(id: UUID(), name: "Paris", country: "France",
                         countryCode: "FR", latitude: 48.85, longitude: 2.35)

        XCTAssertEqual(denver.unitSystem, .imperial)
        XCTAssertEqual(paris.unitSystem, .metric)
    }

    // MARK: - Stale data age

    @MainActor func testStaleAgeUsesTheLargestSensibleUnit() {
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
    @MainActor func testUVIndexCategoryMatchesTheRoundedValue() {
        XCTAssertEqual(WeatherDetails.uvIndex(2.4), "2 Low")
        XCTAssertEqual(WeatherDetails.uvIndex(2.6), "3 Mod")
        XCTAssertEqual(WeatherDetails.uvIndex(5.4), "5 Mod")
        XCTAssertEqual(WeatherDetails.uvIndex(5.6), "6 High")
        XCTAssertEqual(WeatherDetails.uvIndex(7.6), "8 Very High")
        XCTAssertEqual(WeatherDetails.uvIndex(11.0), "11 Extreme")
    }

    @MainActor func testUVIndexHandlesZero() {
        XCTAssertEqual(WeatherDetails.uvIndex(0), "0 Low")
    }

    // MARK: - Condition summary

    @MainActor func testSummaryOmitsApparentTemperatureWhenItMatches() {
        XCTAssertEqual(
            CurrentConditionsView.summary(condition: "Sunny", actual: 61, apparent: 61),
            "Sunny"
        )
    }

    @MainActor func testSummaryReportsAWarmerApparentTemperature() {
        XCTAssertEqual(
            CurrentConditionsView.summary(condition: "Cloudy", actual: 21, apparent: 23),
            "Cloudy · feels 2° warmer"
        )
    }

    @MainActor func testSummaryReportsACoolerApparentTemperatureAsAPositiveNumber() {
        XCTAssertEqual(
            CurrentConditionsView.summary(condition: "Windy", actual: 12, apparent: 8),
            "Windy · feels 4° cooler"
        )
    }

    /// The difference is taken from already-converted values, so a 2°C gap
    /// reads as 4° to a Fahrenheit reader rather than 2°.
    @MainActor func testDifferenceIsExpressedInTheDisplayedUnit() {
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
    @MainActor func testSubDegreeDifferenceIsTreatedAsNoDifference() {
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

    @MainActor func testLocalTimeReflectsTheCitysOffsetRatherThanTheDevices() {
        let instant = Date(timeIntervalSince1970: 1_753_440_000)

        let sydney = CurrentConditionsView.localTime(at: instant, in: TimeZone(secondsFromGMT: 36000)!)
        let london = CurrentConditionsView.localTime(at: instant, in: TimeZone(secondsFromGMT: 3600)!)

        XCTAssertNotEqual(sydney, london, "Same instant in different zones should render differently")
    }

    @MainActor func testLocalTimeAdvancesWithTheClock() {
        let instant = Date(timeIntervalSince1970: 1_753_440_000)
        let anHourLater = instant.addingTimeInterval(3600)

        XCTAssertNotEqual(
            CurrentConditionsView.localTime(at: instant, in: TimeZone(secondsFromGMT: 0)!),
            CurrentConditionsView.localTime(at: anHourLater, in: TimeZone(secondsFromGMT: 0)!)
        )
    }

    /// Every other time in the app is lowercased. In a region that writes
    /// "PM", the header said "9:44 PM" over a sun arc saying "6:24 pm".
    @MainActor func testTheHeaderClockIsLowercasedLikeEveryOtherTime() {
        let evening = Date(timeIntervalSince1970: 1_753_469_040) // 18:44 UTC
        let utc = TimeZone(secondsFromGMT: 0)!

        XCTAssertEqual(
            CurrentConditionsView.localTime(at: evening, in: utc, locale: Locale(identifier: "en_US"))
                .replacingOccurrences(of: "\u{202F}", with: " "),
            "6:44 pm"
        )
    }
}

/// Two places can share a name, a state and a country — Oslo, Minnesota is two
/// towns in two counties — and the results showed both as "Minnesota, United
/// States", so the reader could not tell which one they were adding.
nonisolated final class SearchResultRegionTests: XCTestCase {

    @MainActor private func place(_ id: Int, admin2: String?, admin1: String?, country: String?) -> GeocodingResult {
        GeocodingResult(id: id, name: "Oslo", latitude: 0, longitude: 0,
                        country: country, country_code: nil, admin1: admin1, admin2: admin2)
    }

    @MainActor func testNamesakesInOneStateAreToldApartByTheirCounty() {
        let marshall = place(1, admin2: "Marshall", admin1: "Minnesota", country: "United States")
        let dodge = place(2, admin2: "Dodge", admin1: "Minnesota", country: "United States")
        let results = [place(3, admin2: nil, admin1: "Oslo", country: "Norway"), marshall, dodge]

        XCTAssertEqual(SearchResultsView.region(for: marshall, among: results),
                       "Marshall, Minnesota, United States")
        XCTAssertEqual(SearchResultsView.region(for: dodge, among: results),
                       "Dodge, Minnesota, United States")
    }

    /// The county is noise when nothing else in the list could be mistaken
    /// for this place, so the short form stays wherever it is enough.
    @MainActor func testAPlaceWithNoNamesakeKeepsTheShortForm() {
        let norway = place(3, admin2: "Oslo", admin1: "Oslo", country: "Norway")
        let florida = place(4, admin2: "Manatee", admin1: "Florida", country: "United States")
        let minnesota = place(1, admin2: "Marshall", admin1: "Minnesota", country: "United States")
        let results = [norway, florida, minnesota]

        XCTAssertEqual(SearchResultsView.region(for: norway, among: results), "Oslo, Norway")
        XCTAssertEqual(SearchResultsView.region(for: florida, among: results), "Florida, United States")
        XCTAssertEqual(SearchResultsView.region(for: minnesota, among: results), "Minnesota, United States")
    }
}

/// The strip centres the city you are on, so its neighbours run off both
/// edges. Cut hard, "Melbourne" arrived as "rne" — a word that is not there.
/// Faded, a cut name reads as "more this way".
nonisolated final class CityNameStripFadeTests: XCTestCase {

    @MainActor private func fade(offset: CGFloat, content: CGFloat = 800, viewport: CGFloat = 346,
                      fadesLeading: Bool = true) -> CityNameStrip.EdgeFade {
        CityNameStrip.EdgeFade(offset: offset, namesWidth: content, viewportWidth: viewport,
                               fadeWidth: 32, fadesLeading: fadesLeading)
    }

    /// Scrolled to the start, the first name begins at the edge. Fading it
    /// would take letters off the one name there that is whole.
    @MainActor func testNothingFadesAtAnEdgeNoNameRunsPast() {
        XCTAssertEqual(fade(offset: 0).leading, 0)
        XCTAssertEqual(fade(offset: 800 - 346).trailing, 0)
    }

    @MainActor func testBothEdgesFadeInTheMiddleOfTheList() {
        let middle = fade(offset: 200)
        XCTAssertEqual(middle.leading, 1)
        XCTAssertEqual(middle.trailing, 1)
    }

    /// The fade eases in over its own width rather than switching on at the
    /// first point of scroll.
    @MainActor func testAFadeEasesInAsNamesScrollPastTheEdge() {
        XCTAssertEqual(fade(offset: 16).leading, 0.5, accuracy: 0.001)
        XCTAssertEqual(fade(offset: 800 - 346 - 8).trailing, 0.25, accuracy: 0.001)
    }

    /// At accessibility sizes the current city sits at the leading edge;
    /// fading there would fade the one name the strip is for.
    @MainActor func testTheLeadingEdgeStaysSharpWhenTheCurrentCitySitsThere() {
        let large = fade(offset: 200, fadesLeading: false)
        XCTAssertEqual(large.leading, 0)
        XCTAssertEqual(large.trailing, 1)
    }

    @MainActor func testAListThatFitsDoesNotFade() {
        let fits = fade(offset: 0, content: 300)
        XCTAssertEqual(fits.leading, 0)
        XCTAssertEqual(fits.trailing, 0)
    }
}

/// When the page says how old its readings are. After a failed refresh, as
/// ever — and now also whenever they are old enough to be called stale, so a
/// forecast saved days ago never passes for today's. Not while a refresh is
/// on its way, though: that would flash the notice for a second on every
/// launch after a few hours away.
nonisolated final class StaleNoticeTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_788_960_000)

    @MainActor private func shown(error: String? = nil, hoursOld: Double?, refreshing: Bool = false) -> Bool {
        StaleDataNotice.isShown(errorMessage: error,
                                fetchedAt: hoursOld.map { now.addingTimeInterval(-$0 * 3_600) },
                                isRefreshing: refreshing, now: now)
    }

    @MainActor func testAFailedRefreshAlwaysSaysSo() {
        XCTAssertTrue(shown(error: "No internet connection.", hoursOld: 0.5))
    }

    @MainActor func testAStaleReadingSaysHowOldItIs() {
        XCTAssertTrue(shown(hoursOld: 240))
        XCTAssertTrue(shown(hoursOld: 4))
    }

    @MainActor func testAFreshReadingSaysNothing() {
        XCTAssertFalse(shown(hoursOld: 1))
        XCTAssertFalse(shown(hoursOld: nil))
    }

    @MainActor func testNothingFlashesWhileARefreshIsOnItsWay() {
        XCTAssertFalse(shown(hoursOld: 240, refreshing: true))
    }

    /// With no error there is no message to lead with, so the notice is the
    /// age alone rather than an age after a stray space.
    @MainActor func testTheAgeStandsAloneWithoutAnError() {
        let notice = StaleDataNotice.fullMessage(message: "", fetchedAt: now.addingTimeInterval(-240 * 3_600), now: now)
        XCTAssertEqual(notice, "Showing readings from 10d ago.")
    }
}

/// The location arrow is hidden from VoiceOver in the city strip, as it is in
/// the saved list, so the words have to say which city is the located one.
/// The saved list already did; the strip read only the name, so the located
/// city and a saved city of the same name sounded identical there.
nonisolated final class SpokenCityNameTests: XCTestCase {

    @MainActor func testTheLocatedCityIsSaidToBeTheCurrentLocation() {
        XCTAssertEqual(CityNameStrip.spokenName("Melbourne", isCurrentLocation: true),
                       "Melbourne, current location")
    }

    @MainActor func testASavedCityIsJustItsName() {
        XCTAssertEqual(CityNameStrip.spokenName("Singapore", isCurrentLocation: false), "Singapore")
    }
}

/// Daylight left, in whole minutes. Rounded down, the last minute before
/// sunset read "0 min of light left" beside a sun still drawn up.
nonisolated final class DaylightMinutesTests: XCTestCase {

    @MainActor func testAPartMinuteOfLightRoundsUp() {
        XCTAssertEqual(SunArcView.minutesLeft(30), 1)
        XCTAssertEqual(SunArcView.minutesLeft(60), 1)
        XCTAssertEqual(SunArcView.minutesLeft(61), 2)
        XCTAssertEqual(SunArcView.minutesLeft(3_594), 60)
    }

    @MainActor func testNoLightLeftIsNoCountdown() {
        XCTAssertNil(SunArcView.minutesLeft(0))
        XCTAssertNil(SunArcView.minutesLeft(nil))
    }
}

/// The 24-hour strip shows a chance of rain only where rain is likely.
nonisolated final class HourlyRainChanceTests: XCTestCase {

    @MainActor func testEachHourCarriesItsChanceOfRain() {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.calendar = Calendar(identifier: .gregorian)
        stamp.dateFormat = "yyyy-MM-dd'T'HH:mm"
        stamp.timeZone = TimeZone(secondsFromGMT: 0)

        let hourStart = Date(timeIntervalSince1970:
            (Date().timeIntervalSince1970 / 3_600).rounded(.down) * 3_600)
        let hourly = HourlyWeatherResponse(
            time: (0..<2).map { stamp.string(from: hourStart.addingTimeInterval(Double($0) * 3_600)) },
            temperature_2m: [20, 19],
            precipitation: [0, 1],
            precipitation_probability: [10, 60]
        )
        let city = City(id: UUID(), name: "Testville", country: "Nowhere",
                        countryCode: "AU", latitude: 0, longitude: 0)
        let weather = CityWeather(city: city, response: TestResponse.make(hourly: hourly))

        XCTAssertEqual(weather.hourlyForecasts.map(\.rainChance), [10, 60])
    }

    /// The Rain row's own threshold, so the two never disagree.
    @MainActor func testOnlyALikelyChanceIsShown() {
        XCTAssertFalse(HourlyForecastView.isLikely(nil))
        XCTAssertFalse(HourlyForecastView.isLikely(19))
        XCTAssertTrue(HourlyForecastView.isLikely(20))
    }
}
