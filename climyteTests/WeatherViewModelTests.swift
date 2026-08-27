//
//  WeatherViewModelTests.swift
//  climyteTests
//

import XCTest
@testable import climyte

@MainActor
final class WeatherViewModelTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var cacheDirectory: URL!
    private var cache: WeatherCache!

    override func setUp() {
        super.setUp()
        // An isolated suite and cache directory so tests never read or clobber
        // the real app's state, and can't leak into each other.
        suiteName = "climyteTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)

        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("climyteTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        cache = WeatherCache(directory: cacheDirectory)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: cacheDirectory)
        defaults = nil
        suiteName = nil
        cacheDirectory = nil
        cache = nil
        super.tearDown()
    }

    // MARK: - Saved cities

    func testDefaultsToSydneyWhenNothingIsPersisted() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.entries.count, 1)
        XCTAssertEqual(viewModel.entries.first?.city.name, "Sydney")
        XCTAssertEqual(viewModel.selectedCityKey, viewModel.entries.first?.id)
    }

    func testLoadsPersistedCitiesInOrder() throws {
        let cities = [paris, tokyo]
        defaults.set(try JSONEncoder().encode(cities), forKey: "saved_cities")

        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.entries.map(\.city.name), ["Paris", "Tokyo"])
        XCTAssertEqual(viewModel.selectedCityKey, paris.key)
    }

    /// Anyone upgrading from the single-city build should keep their city
    /// rather than being silently reset to Sydney.
    func testMigratesTheLegacySingleCityKey() throws {
        defaults.set(try JSONEncoder().encode(paris), forKey: "saved_active_city")

        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.entries.map(\.city.name), ["Paris"])
    }

    func testSelectingASearchResultAppendsAndSelectsIt() {
        let viewModel = makeViewModel()

        viewModel.selectCity(makeTokyoResult())

        XCTAssertEqual(viewModel.entries.map(\.city.name), ["Sydney", "Tokyo"])
        XCTAssertEqual(viewModel.selectedCityKey, tokyo.key)
        XCTAssertEqual(viewModel.searchQuery, "")
    }

    /// Adding a city you already have should move to it, not duplicate it.
    func testSelectingAnAlreadySavedCitySelectsRatherThanDuplicates() {
        let viewModel = makeViewModel()
        viewModel.selectCity(makeTokyoResult())
        XCTAssertEqual(viewModel.entries.count, 2)

        viewModel.selectCity(makeTokyoResult())

        XCTAssertEqual(viewModel.entries.count, 2)
        XCTAssertEqual(viewModel.selectedCityKey, tokyo.key)
    }

    func testSavedCitiesPersistAcrossLaunches() {
        let viewModel = makeViewModel()
        viewModel.selectCity(makeTokyoResult())

        XCTAssertEqual(makeViewModel().entries.map(\.city.name), ["Sydney", "Tokyo"])
    }

    func testRemovingACitySelectsANeighbourAndPersists() {
        let viewModel = makeViewModel()
        viewModel.selectCity(makeTokyoResult())
        XCTAssertEqual(viewModel.selectedCityKey, tokyo.key)

        viewModel.removeCity(viewModel.entries[1])

        XCTAssertEqual(viewModel.entries.map(\.city.name), ["Sydney"])
        XCTAssertEqual(viewModel.selectedCityKey, viewModel.entries[0].id)
        XCTAssertEqual(makeViewModel().entries.map(\.city.name), ["Sydney"])
    }

    /// An app with no cities has nothing to show and no way back.
    func testTheLastCityCannotBeRemoved() {
        let viewModel = makeViewModel()

        XCTAssertFalse(viewModel.canRemoveCities)
        viewModel.removeCity(viewModel.entries[0])

        XCTAssertEqual(viewModel.entries.count, 1)
    }

    func testRemovingACityPrunesItsCachedWeather() {
        let viewModel = makeViewModel()
        viewModel.selectCity(makeTokyoResult())
        cache.save(city: tokyo, response: makeResponse(temperature: 8))
        XCTAssertNotNil(cache.load(for: tokyo))

        viewModel.removeCity(viewModel.entries[1])

        XCTAssertNil(cache.load(for: tokyo), "Removed cities shouldn't leave payloads on disk")
    }

    // MARK: - Fetching

    func testSuccessfulFetchPublishesWeatherAgainstItsOwnEntry() async {
        let service = StubWeatherService()
        service.result = .success(makeCityWeather())
        let viewModel = makeViewModel(service: service)
        let key = viewModel.entries[0].id

        await viewModel.refresh(cityKey: key)

        XCTAssertNotNil(viewModel.entries[0].weather)
        XCTAssertNil(viewModel.entries[0].errorMessage)
        XCTAssertFalse(viewModel.entries[0].isLoading)
        XCTAssertNotNil(viewModel.entries[0].lastUpdated)
    }

    func testOfflineErrorSurfacesAsAUserFacingMessage() async {
        let service = StubWeatherService()
        service.result = .failure(WeatherService.WeatherError.offline)
        let viewModel = makeViewModel(service: service)

        await viewModel.refresh(cityKey: viewModel.entries[0].id)

        XCTAssertEqual(viewModel.entries[0].errorMessage, "No internet connection.")
        XCTAssertNil(viewModel.entries[0].weather)
        XCTAssertFalse(viewModel.entries[0].isLoading)
    }

    func testServerErrorSurfacesAsAUserFacingMessage() async {
        let service = StubWeatherService()
        service.result = .failure(WeatherService.WeatherError.serverError(statusCode: 503))
        let viewModel = makeViewModel(service: service)

        await viewModel.refresh(cityKey: viewModel.entries[0].id)

        XCTAssertEqual(viewModel.entries[0].errorMessage, "The weather service is unavailable right now.")
    }

    func testDecodingErrorNamesTheCity() {
        let message = WeatherViewModel.userMessage(
            for: WeatherService.WeatherError.decodingError,
            city: City(id: UUID(), name: "Oslo", country: "Norway", countryCode: nil, latitude: 59.91, longitude: 10.75)
        )

        XCTAssertEqual(message, "Couldn't read the weather data for Oslo.")
    }

    /// One city failing must not blank out another city's page.
    func testAFailureOnOneCityDoesNotAffectAnother() async {
        let service = StubWeatherService()
        let viewModel = makeViewModel(service: service)
        viewModel.selectCity(makeTokyoResult())

        service.result = .success(makeCityWeather(temperature: 21))
        await viewModel.refresh(cityKey: viewModel.entries[0].id)

        service.result = .failure(WeatherService.WeatherError.offline)
        await viewModel.refresh(cityKey: viewModel.entries[1].id)

        XCTAssertNotNil(viewModel.entries[0].weather)
        XCTAssertNil(viewModel.entries[0].errorMessage)
        XCTAssertNil(viewModel.entries[1].weather)
        XCTAssertEqual(viewModel.entries[1].errorMessage, "No internet connection.")
    }

    /// A slow fetch that lost the race must not overwrite the newer one's result.
    func testSupersededFetchDoesNotOverwriteNewerResult() async {
        let service = StubWeatherService()
        service.result = .success(makeCityWeather(temperature: 1))
        service.delayNanoseconds = 200_000_000
        let viewModel = makeViewModel(service: service)
        let key = viewModel.entries[0].id

        let slowFetch = Task { await viewModel.refresh(cityKey: key) }

        try? await Task.sleep(nanoseconds: 20_000_000)
        service.result = .success(makeCityWeather(temperature: 30))
        service.delayNanoseconds = 0
        await viewModel.refresh(cityKey: key)

        await slowFetch.value

        XCTAssertEqual(viewModel.entries[0].weather?.temperature, 30, "Newest fetch should win")
    }

    /// The array can be mutated while a request is in flight, so the write-back
    /// must re-resolve its index rather than trusting the old one.
    func testFetchCompletingAfterARemovalDoesNotCorruptOtherEntries() async {
        let service = StubWeatherService()
        service.result = .success(makeCityWeather(temperature: 8))
        service.delayNanoseconds = 150_000_000
        let viewModel = makeViewModel(service: service)
        viewModel.selectCity(makeTokyoResult())

        let tokyoKey = viewModel.entries[1].id
        let inFlight = Task { await viewModel.refresh(cityKey: tokyoKey) }

        try? await Task.sleep(nanoseconds: 20_000_000)
        viewModel.removeCity(viewModel.entries[1])
        await inFlight.value

        XCTAssertEqual(viewModel.entries.count, 1)
        XCTAssertEqual(viewModel.entries[0].city.name, "Sydney")
        XCTAssertNil(viewModel.entries[0].weather, "Tokyo's result must not land on Sydney")
    }

    /// Every network fault used to collapse into one sentence that named
    /// nothing. These are genuinely different problems with different fixes.
    func testDistinctNetworkFaultsGetDistinctMessages() {
        let city = City(id: UUID(), name: "Oslo", country: "Norway",
                        countryCode: "NO", latitude: 59.91, longitude: 10.75)

        func message(_ error: WeatherService.WeatherError) -> String {
            WeatherViewModel.userMessage(for: error, city: city)
        }

        XCTAssertEqual(message(.timedOut), "The request timed out.")
        XCTAssertEqual(message(.unreachable), "Couldn't reach the weather service.")
        XCTAssertEqual(message(.insecureConnection),
                       "Secure connection failed — check the date and time on your device.")
        XCTAssertEqual(message(.offline), "No internet connection.")

        XCTAssertNotEqual(message(.timedOut), message(.unreachable))
        XCTAssertNotEqual(message(.unreachable), message(.insecureConnection))
    }

    /// An unrecognised URLError still names its code, so a report identifies
    /// the fault even when the app has no friendly wording for it.
    func testUnrecognisedURLErrorNamesItsCode() {
        let city = City(id: UUID(), name: "Oslo", country: "Norway",
                        countryCode: "NO", latitude: 59.91, longitude: 10.75)
        let underlying = URLError(.httpTooManyRedirects)

        let message = WeatherViewModel.userMessage(
            for: WeatherService.WeatherError.networkError(underlying), city: city
        )

        XCTAssertTrue(message.contains("-1007"),
                      "Expected an ungrouped code in: \(message)")
        XCTAssertFalse(message.contains(","),
                       "An error code must not be thousands-separated: \(message)")
    }

    // MARK: - Caching

    func testSuccessfulFetchIsWrittenToTheCache() async {
        let service = StubWeatherService()
        service.result = .success(makeCityWeather())
        let viewModel = makeViewModel(service: service)
        let city = viewModel.entries[0].city

        await viewModel.refresh(cityKey: viewModel.entries[0].id)

        XCTAssertNotNil(cache.load(for: city))
    }

    /// A cold launch should show the last reading immediately rather than a
    /// spinner, even before any network call resolves.
    func testCachedWeatherIsRestoredForEveryCityOnInit() throws {
        defaults.set(try JSONEncoder().encode([paris, tokyo]), forKey: "saved_cities")

        let fetchedAt = Date().addingTimeInterval(-3600)
        cache.save(city: paris, response: makeResponse(temperature: 19), at: fetchedAt)
        cache.save(city: tokyo, response: makeResponse(temperature: 8), at: fetchedAt)

        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.entries[0].weather?.temperature, 19)
        XCTAssertEqual(viewModel.entries[1].weather?.temperature, 8)
        XCTAssertEqual(viewModel.entries[0].lastUpdated, fetchedAt)
    }

    func testCacheKeepsCitiesSeparate() {
        cache.save(city: paris, response: makeResponse(temperature: 19))
        cache.save(city: tokyo, response: makeResponse(temperature: 8))

        XCTAssertEqual(cache.load(for: paris)?.response.current.temperature_2m, 19)
        XCTAssertEqual(cache.load(for: tokyo)?.response.current.temperature_2m, 8)
        XCTAssertEqual(cache.loadAll().count, 2)
    }

    func testSavingTheSameCityTwiceReplacesRatherThanAccumulates() {
        cache.save(city: paris, response: makeResponse(temperature: 19))
        cache.save(city: paris, response: makeResponse(temperature: 25))

        XCTAssertEqual(cache.loadAll().count, 1)
        XCTAssertEqual(cache.load(for: paris)?.response.current.temperature_2m, 25)
    }

    func testCacheRoundTripsThroughDisk() {
        cache.save(city: paris, response: makeResponse(temperature: 19))

        let reloaded = WeatherCache(directory: cacheDirectory).load(for: paris)

        XCTAssertEqual(reloaded?.city.name, "Paris")
        XCTAssertEqual(reloaded?.response.current.temperature_2m, 19)
    }

    func testLoadReturnsNilWhenNothingHasBeenCached() {
        XCTAssertNil(cache.load(for: paris))
        XCTAssertTrue(cache.loadAll().isEmpty)
    }

    // MARK: - Units

    /// Units come from each city's own country, with no global setting.
    func testEachCityUsesItsOwnCountrysUnits() {
        let viewModel = makeViewModel()
        viewModel.selectCity(makeDenverResult())

        let sydney = viewModel.entries[0].city
        let denver = viewModel.entries[1].city

        XCTAssertEqual(sydney.unitSystem, .metric)
        XCTAssertEqual(denver.unitSystem, .imperial)
    }

    func testAddedCitiesRetainTheirCountryCode() {
        let viewModel = makeViewModel()
        viewModel.selectCity(makeDenverResult())

        XCTAssertEqual(viewModel.entries[1].city.countryCode, "US")
    }

    func testCountryCodeSurvivesARelaunch() {
        let viewModel = makeViewModel()
        viewModel.selectCity(makeDenverResult())

        let reloaded = makeViewModel()
        XCTAssertEqual(reloaded.entries[1].city.countryCode, "US")
        XCTAssertEqual(reloaded.entries[1].city.unitSystem, .imperial)
    }

    // MARK: - Helpers

    private let paris = City(id: UUID(), name: "Paris", country: "France", countryCode: "FR", latitude: 48.8566, longitude: 2.3522)
    private let tokyo = City(id: UUID(), name: "Tokyo", country: "Japan", countryCode: "JP", latitude: 35.6762, longitude: 139.6503)

    private func makeViewModel(service: WeatherFetching? = nil) -> WeatherViewModel {
        WeatherViewModel(service: service ?? StubWeatherService(), defaults: defaults, cache: cache)
    }

    private func makeTokyoResult() -> GeocodingResult {
        GeocodingResult(id: 1, name: "Tokyo", latitude: 35.6762, longitude: 139.6503,
                        country: "Japan", country_code: "JP", admin1: "Tokyo")
    }

    private func makeDenverResult() -> GeocodingResult {
        GeocodingResult(id: 2, name: "Denver", latitude: 39.7392, longitude: -104.9847,
                        country: "United States", country_code: "US", admin1: "Colorado")
    }

    private func makeCityWeather(cityName: String = "Sydney", temperature: Double = 22.5) -> CityWeather {
        let city = City(id: UUID(), name: cityName, country: "Australia", latitude: -33.8688, longitude: 151.2093)
        return CityWeather(city: city, response: makeResponse(temperature: temperature))
    }

    private func makeResponse(temperature: Double) -> WeatherResponse {
        WeatherResponse(
            latitude: -33.8688,
            longitude: 151.2093,
            utc_offset_seconds: 36000,
            current: CurrentWeatherResponse(
                temperature_2m: temperature,
                apparent_temperature: temperature - 1,
                is_day: 1,
                weather_code: 0,
                relative_humidity_2m: 60.0,
                dew_point_2m: 10.0,
                wind_speed_10m: 12.0,
                wind_gusts_10m: 14.0,
                visibility: 10000.0
            ),
            hourly: HourlyWeatherResponse(time: [], temperature_2m: [], weather_code: []),
            daily: DailyWeatherResponse(
                time: [], weather_code: [], temperature_2m_max: [],
                temperature_2m_min: [], sunrise: [], sunset: [], uv_index_max: [],
                precipitation_probability_max: [], precipitation_sum: [],
                precipitation_hours: [], daylight_duration: []
            )
        )
    }
}

// MARK: - Stub

private final class StubWeatherService: WeatherFetching {
    var result: Result<CityWeather, Error>?
    var searchResults: [GeocodingResult] = []
    var searchError: Error?
    var delayNanoseconds: UInt64 = 0

    func fetchWeather(for city: City) async throws -> CityWeather {
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }

        switch result {
        case .success(let weather):
            return weather
        case .failure(let error):
            throw error
        case nil:
            throw WeatherService.WeatherError.noResultConfigured
        }
    }

    func searchCities(query: String) async throws -> [GeocodingResult] {
        if let searchError { throw searchError }
        return searchResults
    }
}

private extension WeatherService.WeatherError {
    static var noResultConfigured: WeatherService.WeatherError {
        .networkError(NSError(domain: "StubWeatherService", code: -1))
    }
}
