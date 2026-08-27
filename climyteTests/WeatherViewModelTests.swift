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

    // MARK: - Active city

    func testDefaultsToSydneyWhenNothingIsPersisted() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.activeCity.name, "Sydney")
        XCTAssertEqual(viewModel.activeCity.country, "Australia")
    }

    func testLoadsPersistedCityOnInit() throws {
        let paris = City(id: UUID(), name: "Paris", country: "France", latitude: 48.8566, longitude: 2.3522)
        defaults.set(try JSONEncoder().encode(paris), forKey: "saved_active_city")

        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.activeCity.name, "Paris")
        XCTAssertEqual(viewModel.activeCity.country, "France")
    }

    func testSelectCityUpdatesActiveCityAndClearsSearch() {
        let viewModel = makeViewModel()
        viewModel.searchQuery = "Tokyo"

        viewModel.selectCity(makeTokyoResult())

        XCTAssertEqual(viewModel.activeCity.name, "Tokyo")
        XCTAssertEqual(viewModel.activeCity.country, "Japan")
        XCTAssertEqual(viewModel.activeCity.latitude, 35.6762)
        XCTAssertEqual(viewModel.activeCity.longitude, 139.6503)
        XCTAssertEqual(viewModel.searchQuery, "")
        XCTAssertTrue(viewModel.searchResults.isEmpty)
        XCTAssertEqual(viewModel.searchState, .idle)
        XCTAssertFalse(viewModel.isUsingCurrentLocation)
    }

    func testSelectCityPersistsTheChoice() throws {
        let viewModel = makeViewModel()

        viewModel.selectCity(makeTokyoResult())

        let data = try XCTUnwrap(defaults.data(forKey: "saved_active_city"))
        let saved = try JSONDecoder().decode(City.self, from: data)
        XCTAssertEqual(saved.name, "Tokyo")
    }

    // MARK: - Fetching

    func testSuccessfulFetchPublishesWeatherAndClearsError() async {
        let service = StubWeatherService()
        service.result = .success(makeCityWeather())
        let viewModel = makeViewModel(service: service)

        await viewModel.fetchWeatherForActiveCity()

        XCTAssertNotNil(viewModel.activeWeather)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testOfflineErrorSurfacesAsAUserFacingMessage() async {
        let service = StubWeatherService()
        service.result = .failure(WeatherService.WeatherError.offline)
        let viewModel = makeViewModel(service: service)

        await viewModel.fetchWeatherForActiveCity()

        XCTAssertEqual(viewModel.errorMessage, "No internet connection.")
        XCTAssertNil(viewModel.activeWeather)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testServerErrorSurfacesAsAUserFacingMessage() async {
        let service = StubWeatherService()
        service.result = .failure(WeatherService.WeatherError.serverError(statusCode: 503))
        let viewModel = makeViewModel(service: service)

        await viewModel.fetchWeatherForActiveCity()

        XCTAssertEqual(viewModel.errorMessage, "The weather service is unavailable right now.")
    }

    func testDecodingErrorNamesTheCity() {
        let city = City(id: UUID(), name: "Oslo", country: "Norway", latitude: 59.91, longitude: 10.75)

        let message = WeatherViewModel.userMessage(
            for: WeatherService.WeatherError.decodingError,
            city: city
        )

        XCTAssertEqual(message, "Couldn't read the weather data for Oslo.")
    }

    /// A slow fetch that lost the race must not overwrite the newer one's result.
    func testSupersededFetchDoesNotOverwriteNewerResult() async {
        let service = StubWeatherService()
        let stale = makeCityWeather(cityName: "Stale", temperature: 1)
        let fresh = makeCityWeather(cityName: "Fresh", temperature: 30)

        service.result = .success(stale)
        service.delayNanoseconds = 200_000_000
        let viewModel = makeViewModel(service: service)

        let slowFetch = Task { await viewModel.fetchWeatherForActiveCity() }

        // Let the slow fetch start and suspend, then supersede it.
        try? await Task.sleep(nanoseconds: 20_000_000)
        service.result = .success(fresh)
        service.delayNanoseconds = 0
        await viewModel.fetchWeatherForActiveCity()

        await slowFetch.value

        XCTAssertEqual(viewModel.activeWeather?.temperature, 30, "Newest fetch should win")
    }

    // MARK: - Caching

    func testSuccessfulFetchIsWrittenToTheCache() async {
        let service = StubWeatherService()
        service.result = .success(makeCityWeather(cityName: "Oslo"))
        let viewModel = makeViewModel(service: service)

        await viewModel.fetchWeatherForActiveCity()

        let cached = cache.load()
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.city, viewModel.activeCity)
        XCTAssertNotNil(viewModel.lastUpdated)
    }

    /// A cold launch should show the last reading immediately rather than a
    /// spinner, even before any network call resolves.
    func testCachedWeatherIsRestoredOnInitWithoutFetching() throws {
        let city = City(id: UUID(), name: "Lisbon", country: "Portugal", latitude: 38.7, longitude: -9.1)
        defaults.set(try JSONEncoder().encode(city), forKey: "saved_active_city")

        let fetchedAt = Date().addingTimeInterval(-3600)
        cache.save(city: city, response: makeResponse(temperature: 19), at: fetchedAt)

        let viewModel = makeViewModel()

        XCTAssertNotNil(viewModel.activeWeather, "Cached weather should be on screen immediately")
        XCTAssertEqual(viewModel.activeWeather?.city.name, "Lisbon")
        XCTAssertEqual(viewModel.activeWeather?.temperature, 19)
        XCTAssertEqual(viewModel.lastUpdated, fetchedAt)
    }

    /// The cache holds one city; showing Lisbon's weather under Sydney's name
    /// would be worse than showing nothing.
    func testCacheForADifferentCityIsIgnored() {
        let cachedCity = City(id: UUID(), name: "Lisbon", country: "Portugal", latitude: 38.7, longitude: -9.1)
        cache.save(city: cachedCity, response: makeResponse(temperature: 19))

        // No saved active city, so the view model defaults to Sydney.
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.activeCity.name, "Sydney")
        XCTAssertNil(viewModel.activeWeather)
    }

    func testCacheRoundTripsThroughDisk() {
        let city = City(id: UUID(), name: "Reykjavik", country: "Iceland", latitude: 64.1, longitude: -21.9)
        cache.save(city: city, response: makeResponse(temperature: 3))

        let reloaded = WeatherCache(directory: cacheDirectory).load()

        XCTAssertEqual(reloaded?.city.name, "Reykjavik")
        XCTAssertEqual(reloaded?.response.current.temperature_2m, 3)
    }

    func testLoadReturnsNilWhenNothingHasBeenCached() {
        XCTAssertNil(cache.load())
    }

    // MARK: - Units

    func testUnitSystemDefaultsToTheDeviceRegion() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.unitSystem, UnitSystem.deviceDefault)
    }

    func testTogglingUnitsPersistsTheChoice() {
        let viewModel = makeViewModel()
        let original = viewModel.unitSystem

        viewModel.toggleUnitSystem()

        XCTAssertEqual(viewModel.unitSystem, original.toggled)
        XCTAssertEqual(makeViewModel().unitSystem, original.toggled, "Choice should survive a relaunch")
    }

    // MARK: - Search

    func testSearchPublishesResults() async {
        let service = StubWeatherService()
        service.searchResults = [makeTokyoResult()]
        let viewModel = makeViewModel(service: service)

        viewModel.searchQuery = "Tokyo"
        await settleSearch()

        XCTAssertEqual(viewModel.searchState, .results([makeTokyoResult()]))
        XCTAssertEqual(viewModel.searchResults.count, 1)
    }

    /// "No matches" and "the request failed" are different things and must not
    /// share a presentation.
    func testEmptyResultsAreDistinctFromFailure() async {
        let service = StubWeatherService()
        service.searchResults = []
        let viewModel = makeViewModel(service: service)

        viewModel.searchQuery = "Xyzzy"
        await settleSearch()

        XCTAssertEqual(viewModel.searchState, .empty)
    }

    func testSearchFailureSurfacesAMessageInsteadOfFailingSilently() async {
        let service = StubWeatherService()
        service.searchError = WeatherService.WeatherError.offline
        let viewModel = makeViewModel(service: service)

        viewModel.searchQuery = "Tokyo"
        await settleSearch()

        XCTAssertEqual(viewModel.searchState, .failed("No internet connection."))
    }

    func testServerErrorDuringSearchIsNamedAsSuch() async {
        let service = StubWeatherService()
        service.searchError = WeatherService.WeatherError.serverError(statusCode: 500)
        let viewModel = makeViewModel(service: service)

        viewModel.searchQuery = "Tokyo"
        await settleSearch()

        XCTAssertEqual(viewModel.searchState, .failed("City search is unavailable right now."))
    }

    func testRetryAfterFailureCanSucceed() async {
        let service = StubWeatherService()
        service.searchError = WeatherService.WeatherError.offline
        let viewModel = makeViewModel(service: service)

        viewModel.searchQuery = "Tokyo"
        await settleSearch()
        XCTAssertEqual(viewModel.searchState, .failed("No internet connection."))

        service.searchError = nil
        service.searchResults = [makeTokyoResult()]
        viewModel.retrySearch()
        await settleSearch()

        XCTAssertEqual(viewModel.searchState, .results([makeTokyoResult()]))
    }

    func testClearingTheQueryReturnsToIdle() async {
        let service = StubWeatherService()
        service.searchResults = [makeTokyoResult()]
        let viewModel = makeViewModel(service: service)

        viewModel.searchQuery = "Tokyo"
        await settleSearch()
        XCTAssertEqual(viewModel.searchResults.count, 1)

        viewModel.searchQuery = ""

        XCTAssertEqual(viewModel.searchState, .idle)
        XCTAssertTrue(viewModel.searchResults.isEmpty)
    }

    /// The view model debounces for 300ms before hitting the network.
    private func settleSearch() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    // MARK: - Helpers

    private func makeViewModel(service: WeatherFetching? = nil) -> WeatherViewModel {
        WeatherViewModel(service: service ?? StubWeatherService(), defaults: defaults, cache: cache)
    }

    private func makeTokyoResult() -> GeocodingResult {
        GeocodingResult(id: 1, name: "Tokyo", latitude: 35.6762, longitude: 139.6503, country: "Japan", admin1: "Tokyo")
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
                wind_speed_10m: 12.0,
                visibility: 10000.0
            ),
            hourly: HourlyWeatherResponse(time: [], temperature_2m: [], weather_code: []),
            daily: DailyWeatherResponse(
                time: [], weather_code: [], temperature_2m_max: [],
                temperature_2m_min: [], sunrise: [], sunset: [], uv_index_max: []
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
