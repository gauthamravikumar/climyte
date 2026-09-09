//
//  ErrorHandlingTests.swift
//  climyteTests
//

import XCTest
@testable import climyte

/// What the app does when things go wrong: failed searches, hostile input,
/// a corrupted cache, and requests racing each other.
@MainActor
final class ErrorHandlingTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var cacheDirectory: URL!
    private var cache: WeatherCache!

    override func setUp() {
        super.setUp()
        suiteName = "climyteTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("climyteErrors-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        cache = WeatherCache(directory: cacheDirectory)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: cacheDirectory)
        defaults = nil; suiteName = nil; cacheDirectory = nil; cache = nil
        super.tearDown()
    }

    // MARK: - Search failures

    /// Zero matches and a failed request are different things and must not
    /// look the same: one means "try another name", the other "try again".
    func testZeroResultsIsDistinguishableFromAFailure() async {
        let service = StubWeatherService()
        let viewModel = makeViewModel(service: service)

        service.searchResults = []
        viewModel.searchQuery = "Zzzz"
        await settle()
        XCTAssertEqual(viewModel.searchState, SearchState.empty)

        service.searchError = WeatherService.WeatherError.offline
        viewModel.searchQuery = "Paris"
        await settle()
        guard case .failed = viewModel.searchState else {
            return XCTFail("Expected .failed, got \(viewModel.searchState)")
        }
    }

    func testEverySearchFailureSaysSomethingUseful() {
        let cases: [(WeatherService.WeatherError, String)] = [
            (.offline, "internet"),
            (.serverError(statusCode: 500), "unavailable"),
            (.timedOut, "timed out"),
            (.unreachable, "reach"),
            (.insecureConnection, "Secure connection"),
        ]

        for (error, fragment) in cases {
            let message = WeatherViewModel.searchErrorMessage(for: error)
            XCTAssertTrue(message.localizedCaseInsensitiveContains(fragment),
                          "\(error) produced \"\(message)\"")
            XCTAssertFalse(message.isEmpty)
        }
    }

    /// The weather path names the URLError code; the search path used to
    /// collapse every transport fault into one anonymous sentence.
    func testAnUnrecognisedSearchFaultNamesItsCode() {
        let message = WeatherViewModel.searchErrorMessage(
            for: WeatherService.WeatherError.networkError(URLError(.init(rawValue: -1007)))
        )
        XCTAssertTrue(message.contains("-1007"), message)
        XCTAssertFalse(message.contains("-1,007"), "An error code is an identifier, not a quantity")
    }

    func testANonWeatherErrorStillProducesAMessage() {
        let message = WeatherViewModel.searchErrorMessage(for: CocoaError(.fileNoSuchFile))
        XCTAssertFalse(message.isEmpty)
    }

    /// Typing quickly cancels the in-flight search; the last query must win.
    func testASupersededSearchDoesNotOverwriteTheNewerOne() async {
        let service = StubWeatherService()
        let viewModel = makeViewModel(service: service)

        service.searchResults = [result(name: "London")]
        viewModel.searchQuery = "Lon"
        // No settle: replace the query while the first search is still
        // inside its debounce.
        service.searchResults = [result(name: "Tokyo")]
        viewModel.searchQuery = "Tok"
        await settle()

        XCTAssertEqual(viewModel.searchResults.map { $0.name }, ["Tokyo"])
    }

    /// A query of only spaces is not a search. The view and the search have
    /// to agree about that, or the saved-cities list disappears and nothing
    /// takes its place.
    func testAWhitespaceOnlyQueryIsNotASearch() async {
        let service = StubWeatherService()
        service.searchResults = [result(name: "London")]
        let viewModel = makeViewModel(service: service)

        viewModel.searchQuery = "   "
        await settle()

        XCTAssertFalse(viewModel.hasSearchQuery, "The view would show an empty results list")
        XCTAssertEqual(viewModel.searchState, SearchState.idle)
    }

    func testARealQuerySurroundedBySpacesStillSearches() async {
        let service = StubWeatherService()
        service.searchResults = [result(name: "London")]
        let viewModel = makeViewModel(service: service)

        viewModel.searchQuery = "  London  "
        await settle()

        XCTAssertTrue(viewModel.hasSearchQuery)
        XCTAssertEqual(viewModel.searchResults.map { $0.name }, ["London"])
    }

    // MARK: - Hostile query text

    /// Every one of these has to survive percent-encoding into a real URL.
    func testAwkwardQueriesProduceAWellFormedRequest() async throws {
        let queries = ["São Paulo", "Zürich", "Washington D.C.", "北京",
                       "a b  c", "Ōtaki", "!!!", "🌦️", String(repeating: "a", count: 500)]

        for query in queries {
            let recorded = try await capturedSearchURL(for: query)
            let url = try XCTUnwrap(recorded, "No request made for \(query)")

            XCTAssertEqual(url.host(), "geocoding-api.open-meteo.com", query)
            XCTAssertFalse(url.absoluteString.contains(" "), "Unencoded space for \(query)")
            // A round trip through URLComponents recovers the original text.
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            let name = items?.first { $0.name == "name" }?.value
            XCTAssertEqual(name, query, "Query text was mangled")
        }
    }

    /// A city whose coordinates are nonsense must not build a URL that
    /// silently asks for weather somewhere arbitrary.
    func testAbsurdCoordinatesAreRejectedRatherThanRequested() async {
        let broken: [(String, Double, Double)] = [
            ("not a number", .nan, 0),
            ("infinite", 0, .infinity),
            ("off the globe", 91, 0),
            ("past the date line", 0, -181),
        ]

        for (label, latitude, longitude) in broken {
            let city = City(id: UUID(), name: "Nowhere", country: "Nowhere",
                            countryCode: nil, latitude: latitude, longitude: longitude)
            do {
                _ = try await WeatherService.shared.fetchWeather(for: city)
                XCTFail("Expected a throw for \(label)")
            } catch let error as WeatherService.WeatherError {
                guard case .invalidURL = error else {
                    return XCTFail("\(label): expected .invalidURL, got \(error)")
                }
            } catch {
                XCTFail("\(label): expected WeatherError, got \(error)")
            }
        }
    }

    // MARK: - Corrupt storage

    func testATruncatedCacheFileReadsAsEmptyRatherThanCrashing() throws {
        cache.save(city: sydney, response: TestResponse.make())
        let file = cacheDirectory.appendingPathComponent("cached-weather.json")

        let data = try Data(contentsOf: file)
        try data.prefix(data.count / 2).write(to: file)

        XCTAssertEqual(cache.loadAll().count, 0)
        XCTAssertNil(cache.load(for: sydney))
    }

    func testGarbageInTheCacheFileReadsAsEmpty() throws {
        let file = cacheDirectory.appendingPathComponent("cached-weather.json")
        try Data([0xFF, 0x00, 0xFE, 0x42]).write(to: file)

        XCTAssertEqual(cache.loadAll().count, 0)
    }

    /// And the app still works afterwards: a corrupt file must not be a
    /// permanent dead end.
    func testAWriteAfterCorruptionRecovers() throws {
        let file = cacheDirectory.appendingPathComponent("cached-weather.json")
        try Data("not json at all".utf8).write(to: file)

        cache.save(city: sydney, response: TestResponse.make(temperature: 19))

        XCTAssertEqual(cache.load(for: sydney)?.response.current.temperature_2m, 19)
    }

    // MARK: - Requests racing each other

    func testRapidRepeatedRefreshesSettleOnTheLastResult() async {
        let service = StubWeatherService()
        let viewModel = makeViewModel(service: service)
        let key = viewModel.entries[0].id

        for temperature in 1...20 {
            service.result = .success(makeWeather(temperature: Double(temperature)))
            await viewModel.refresh(cityKey: key)
        }

        XCTAssertEqual(viewModel.entries[0].weather?.temperature, 20)
        XCTAssertNil(viewModel.entries[0].errorMessage)
        XCTAssertFalse(viewModel.entries[0].isLoading)
    }

    func testAddingACityWhileARefreshIsInFlightDisturbsNeither() async {
        let service = StubWeatherService()
        service.result = .success(makeWeather(temperature: 11))
        service.delayNanoseconds = 120_000_000
        let viewModel = makeViewModel(service: service)

        let first = viewModel.entries[0].id
        async let refresh: Void = viewModel.refresh(cityKey: first)
        viewModel.selectCity(result(name: "Tokyo", latitude: 35.68, longitude: 139.65))
        await refresh

        XCTAssertEqual(viewModel.entries.count, 2)
        XCTAssertEqual(viewModel.entries.first { $0.id == first }?.weather?.temperature, 11,
                       "The in-flight result still landed on its own city")
    }

    // MARK: - Helpers

    private let sydney = WeatherViewModel.defaultCity

    private func makeViewModel(service: WeatherFetching) -> WeatherViewModel {
        WeatherViewModel(service: service, defaults: defaults, cache: cache,
                         legacyDefaults: UserDefaults(suiteName: suiteName + ".legacy"),
                         reloader: SilentReloader(),
                         citiesSources: .init(mirror: cacheDirectory.appendingPathComponent("saved-cities.json"),
                                              backingFile: nil))
    }

    /// Longer than the 300ms debounce, so the search task has run.
    private func settle() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    private func result(name: String, latitude: Double = 1, longitude: Double = 2) -> GeocodingResult {
        GeocodingResult(id: Int.random(in: 1...10_000), name: name,
                        latitude: latitude, longitude: longitude,
                        country: "Testland", country_code: "AU", admin1: nil)
    }

    private func makeWeather(temperature: Double) -> CityWeather {
        CityWeather(city: sydney, response: TestResponse.make(temperature: temperature))
    }

    /// Runs a real `WeatherService` search through a stub protocol and hands
    /// back the URL it actually asked for.
    private func capturedSearchURL(for query: String) async throws -> URL? {
        URLCapture.captured = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLCapture.self]
        let service = WeatherService(session: URLSession(configuration: config))

        _ = try? await service.searchCities(query: query)
        return URLCapture.captured
    }
}

/// Captures the request and answers with an empty result set.
private final class URLCapture: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var captured: URL?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.captured = request.url
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"results":[]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class SilentReloader: WidgetReloading {
    func reload() {}
}

/// This file's own stub; the one in WeatherViewModelTests is private to it.
@MainActor
private final class StubWeatherService: WeatherFetching {
    var result: Result<CityWeather, Error>?
    var searchResults: [GeocodingResult] = []
    var searchError: Error?
    var delayNanoseconds: UInt64 = 0

    func fetchWeather(for city: City) async throws -> CityWeather {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        switch result {
        case .success(let weather): return weather
        case .failure(let error): throw error
        case nil: throw WeatherService.WeatherError.offline
        }
    }

    func searchCities(query: String) async throws -> [GeocodingResult] {
        if let searchError { throw searchError }
        return searchResults
    }
}
