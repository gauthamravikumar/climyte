//
//  WeatherViewModelTests.swift
//  climyteTests
//

import XCTest
import CoreLocation
@testable import climyte

@MainActor
final class WeatherViewModelTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var cacheDirectory: URL!
    private var cache: WeatherCache!
    private var legacyDefaults: UserDefaults!
    private var legacySuiteName: String!

    override func setUp() {
        super.setUp()
        // An isolated suite and cache directory so tests never read or clobber
        // the real app's state, and can't leak into each other.
        suiteName = "climyteTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)

        legacySuiteName = "climyteTests.legacy.\(UUID().uuidString)"
        legacyDefaults = UserDefaults(suiteName: legacySuiteName)

        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("climyteTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        cache = WeatherCache(directory: cacheDirectory)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        legacyDefaults.removePersistentDomain(forName: legacySuiteName)
        try? FileManager.default.removeItem(at: cacheDirectory)
        defaults = nil
        suiteName = nil
        cacheDirectory = nil
        cache = nil
        legacyDefaults = nil
        legacySuiteName = nil
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

    // MARK: - Current location

    /// The located city is put in front when it is new to the list — that is
    /// the whole reason to surface it.
    func testANewlyLocatedCityIsPlacedFirstAndSelected() async throws {
        defaults.set(try JSONEncoder().encode([paris, tokyo]), forKey: "saved_cities")
        let viewModel = makeViewModel(locatedAt: berlinPlace)

        await viewModel.loadWeatherOnLaunch()

        XCTAssertEqual(viewModel.entries.map(\.city.name), ["Berlin", "Paris", "Tokyo"])
        XCTAssertTrue(viewModel.entries[0].isCurrentLocation)
        XCTAssertEqual(viewModel.selectedCityKey, viewModel.entries[0].id)
    }

    /// A city already in the list keeps the place the reader gave it. It used
    /// to be dragged to the front on every launch, which would silently undo a
    /// reordering the moment CoreLocation answered.
    func testALocatedCityAlreadySavedKeepsItsPosition() async throws {
        defaults.set(try JSONEncoder().encode([paris, tokyo]), forKey: "saved_cities")
        let viewModel = makeViewModel(locatedAt: tokyoPlace, coordinate: tokyoCoordinate)

        await viewModel.loadWeatherOnLaunch()

        XCTAssertEqual(viewModel.entries.map(\.city.name), ["Paris", "Tokyo"],
                       "Being where you are is not a reason to reorder the list")
        XCTAssertTrue(viewModel.entries[1].isCurrentLocation)
        XCTAssertEqual(viewModel.selectedCityKey, viewModel.entries[1].id)
    }

    /// Travelling replaces the located entry rather than collecting one per
    /// trip.
    func testMovingReplacesThePreviousLocatedCity() async throws {
        let viewModel = makeViewModel(locatedAt: berlinPlace)
        await viewModel.loadWeatherOnLaunch()
        XCTAssertEqual(viewModel.entries.filter(\.isCurrentLocation).count, 1)

        locationProvider.location = tokyoCoordinate
        geocoder.result = .success(tokyoPlace)
        await viewModel.loadWeatherOnLaunch()

        XCTAssertEqual(viewModel.entries.filter(\.isCurrentLocation).map(\.city.name), ["Tokyo"])
        XCTAssertFalse(viewModel.entries.contains { $0.city.name == "Berlin" },
                       "The old located city should not linger once it is not where you are")
    }

    func testARefusedLocationIsRecordedSoTheListCanSaySo() async throws {
        defaults.set(try JSONEncoder().encode([paris]), forKey: "saved_cities")
        let viewModel = makeViewModel(authorization: .denied)

        await viewModel.loadWeatherOnLaunch()

        XCTAssertTrue(viewModel.locationAccessRefused)
        XCTAssertEqual(viewModel.entries.map(\.city.name), ["Paris"])
    }

    /// A failed fix is not a refusal, and must not be reported as one — the
    /// reader would be sent to Settings to change something already correct.
    func testAFailedFixIsNotReportedAsARefusal() async throws {
        defaults.set(try JSONEncoder().encode([paris]), forKey: "saved_cities")
        let viewModel = makeViewModel(authorization: .authorizedWhenInUse)
        geocoder.result = .success(nil)

        await viewModel.loadWeatherOnLaunch()

        XCTAssertFalse(viewModel.locationAccessRefused)
    }

    // MARK: - Reordering

    /// `destination` is an insertion point in the pre-move list, so moving a
    /// row down by one means a destination two past its own index. Getting
    /// this wrong is a no-op rather than a crash, which is why it is pinned.
    func testMovingACityDownReordersAndPersists() throws {
        defaults.set(try JSONEncoder().encode([paris, tokyo, berlin]), forKey: "saved_cities")
        let viewModel = makeViewModel()

        viewModel.moveCities(from: IndexSet(integer: 0), to: 2)

        XCTAssertEqual(viewModel.entries.map(\.city.name), ["Tokyo", "Paris", "Berlin"])
        XCTAssertEqual(try savedNames(), ["Tokyo", "Paris", "Berlin"])
    }

    func testMovingACityUpReordersAndPersists() throws {
        defaults.set(try JSONEncoder().encode([paris, tokyo, berlin]), forKey: "saved_cities")
        let viewModel = makeViewModel()

        viewModel.moveCities(from: IndexSet(integer: 2), to: 0)

        XCTAssertEqual(viewModel.entries.map(\.city.name), ["Berlin", "Paris", "Tokyo"])
        XCTAssertEqual(try savedNames(), ["Berlin", "Paris", "Tokyo"])
    }

    /// The order is the pager's order, but which city is on screen shouldn't
    /// change underneath someone who only dragged a row.
    func testMovingDoesNotChangeTheSelectedCity() throws {
        defaults.set(try JSONEncoder().encode([paris, tokyo, berlin]), forKey: "saved_cities")
        let viewModel = makeViewModel()
        viewModel.selectEntry(viewModel.entries[1])

        viewModel.moveCities(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(viewModel.entries.map(\.city.name), ["Tokyo", "Berlin", "Paris"])
        XCTAssertEqual(viewModel.selectedCityKey, tokyo.key)
    }

    func testMovingSeveralCitiesKeepsThemTogetherAndInOrder() throws {
        defaults.set(try JSONEncoder().encode([paris, tokyo, berlin]), forKey: "saved_cities")
        let viewModel = makeViewModel()

        viewModel.moveCities(from: IndexSet([0, 1]), to: 3)

        XCTAssertEqual(viewModel.entries.map(\.city.name), ["Berlin", "Paris", "Tokyo"])
    }

    /// A drag that ends where it started shouldn't write to disk or reload the
    /// widget for nothing.
    func testMovingACityOntoItselfChangesNothing() throws {
        defaults.set(try JSONEncoder().encode([paris, tokyo]), forKey: "saved_cities")
        let reloader = CountingReloader()
        let viewModel = makeViewModel(reloader: reloader)
        let before = reloader.count

        viewModel.moveCities(from: IndexSet(integer: 0), to: 0)
        viewModel.moveCities(from: IndexSet(integer: 0), to: 1)

        XCTAssertEqual(viewModel.entries.map(\.city.name), ["Paris", "Tokyo"])
        XCTAssertEqual(reloader.count, before)
    }

    func testMovingAnOutOfRangeIndexIsIgnored() throws {
        defaults.set(try JSONEncoder().encode([paris, tokyo]), forKey: "saved_cities")
        let viewModel = makeViewModel()

        viewModel.moveCities(from: IndexSet(integer: 7), to: 0)

        XCTAssertEqual(viewModel.entries.map(\.city.name), ["Paris", "Tokyo"])
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

    /// Moving storage into the App Group must not lose cities that were saved
    /// before it existed — an upgrade that silently resets to Sydney would be
    /// invisible in testing and infuriating in use.
    func testCitiesSavedBeforeTheAppGroupAreMigrated() throws {
        legacyDefaults.set(try JSONEncoder().encode([paris, tokyo]), forKey: "saved_cities")
        XCTAssertNil(defaults.data(forKey: "saved_cities"), "Shared suite starts empty")

        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.entries.map(\.city.name), ["Paris", "Tokyo"])
        XCTAssertNotNil(defaults.data(forKey: "saved_cities"),
                        "Migrated data should now live in the shared suite")
    }

    /// The single-city key predates both the list and the App Group, so it has
    /// to survive two migrations in one hop.
    func testTheLegacySingleCityKeyMigratesThroughTheAppGroup() throws {
        legacyDefaults.set(try JSONEncoder().encode(paris), forKey: "saved_active_city")

        XCTAssertEqual(makeViewModel().entries.map(\.city.name), ["Paris"])
    }

    /// Migration runs on every launch, not just the first, so it must never
    /// overwrite cities already in shared storage.
    func testMigrationDoesNotOverwriteExistingSharedCities() throws {
        legacyDefaults.set(try JSONEncoder().encode([paris]), forKey: "saved_cities")
        defaults.set(try JSONEncoder().encode([tokyo]), forKey: "saved_cities")

        XCTAssertEqual(makeViewModel().entries.map(\.city.name), ["Tokyo"])
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
    func testAFailureOnOneCityDoesNotAffectAnother() async throws {
        // Seeded through persistence rather than selectCity, which kicks off a
        // background refresh whose timing would race the assertions below.
        defaults.set(try JSONEncoder().encode([paris, tokyo]), forKey: "saved_cities")

        let service = StubWeatherService()
        let viewModel = makeViewModel(service: service)

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

    /// `.refreshable` runs its closure in a task tied to the refresh control.
    /// The first thing a fetch does is set isLoading, which republishes
    /// `entries`, rebuilds the ForEach inside the TabView and tears that task
    /// down — cancelling the request it was awaiting, so pull-to-refresh
    /// always failed with URLError -999. The work must outlive its caller.
    func testRefreshSurvivesCancellationOfTheCallingTask() async {
        let service = StubWeatherService()
        service.result = .success(makeCityWeather(temperature: 30))
        service.delayNanoseconds = 200_000_000
        let viewModel = makeViewModel(service: service)
        let key = viewModel.entries[0].id

        let caller = Task { await viewModel.refresh(cityKey: key) }
        try? await Task.sleep(nanoseconds: 30_000_000)
        caller.cancel()
        await caller.value

        XCTAssertEqual(viewModel.entries[0].weather?.temperature, 30,
                       "The fetch must complete despite its caller being cancelled")
        XCTAssertNil(viewModel.entries[0].errorMessage,
                     "A cancelled caller must not surface as a failure to the user")
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

    /// The saved list is the authority on what the cache may hold, and every
    /// path that changes it goes through saveCities.
    func testAddingACityPrunesCitiesThatAreNoLongerSaved() {
        // A cache left over from an earlier run, holding a city nobody saved.
        let ghost = City(id: UUID(), name: "Ghost", country: "Nowhere",
                         countryCode: "AU", latitude: 10, longitude: 10)
        cache.save(city: ghost, response: makeResponse(temperature: 5))

        let viewModel = makeViewModel()
        viewModel.selectCity(makeTokyoResult())

        XCTAssertFalse(cache.loadAll().contains { $0.city.key == ghost.key },
                       "A city that is not saved has no business in the cache")
    }

    /// And an app upgrading from a build that only pruned on delete gets its
    /// accumulated cache cleaned up on the next launch.
    func testLaunchingPrunesACacheLeftOversizedByAnEarlierBuild() {
        for i in 0..<5 {
            let stale = City(id: UUID(), name: "Stale \(i)", country: "Nowhere",
                             countryCode: "AU", latitude: Double(i) + 20, longitude: 5)
            cache.save(city: stale, response: makeResponse(temperature: 5))
        }
        XCTAssertEqual(cache.loadAll().count, 5)

        let viewModel = makeViewModel()

        XCTAssertEqual(cache.loadAll().count, 0,
                       "Only the default city is saved, and it has no cached reading")
        XCTAssertEqual(viewModel.entries.count, 1)
    }

    // MARK: - Returning to the foreground

    /// The date-rollover defect. `CityWeather` resolves which day is "today"
    /// when it is built, so an app left open overnight keeps labelling
    /// yesterday "Today". Rebuilding from the same cached response fixes it
    /// without a request.
    func testReturningToTheForegroundRebuildsFromTheCache() async {
        let service = StubWeatherService()
        service.result = .success(makeCityWeather())
        cache.save(city: WeatherViewModel.defaultCity,
                   response: makeResponse(temperature: 17),
                   at: Date())

        let viewModel = makeViewModel(service: service)
        XCTAssertNotNil(viewModel.entries.first?.weather, "Restored at init")

        await viewModel.refreshOnForeground()

        XCTAssertEqual(viewModel.entries.first?.weather?.temperature, 17,
                       "Rebuilt from the cached response, not invented")
    }

    func testAFreshReadingIsNotRefetchedOnReturningToTheForeground() async {
        let service = StubWeatherService()
        service.result = .success(makeCityWeather())
        cache.save(city: WeatherViewModel.defaultCity,
                   response: makeResponse(temperature: 17),
                   at: Date())

        let viewModel = makeViewModel(service: service)
        let before = service.fetchCount

        await viewModel.refreshOnForeground()

        XCTAssertEqual(service.fetchCount, before,
                       "Switching back to the app should not cost a request every time")
    }

    func testAnOldReadingIsRefetchedOnReturningToTheForeground() async {
        let service = StubWeatherService()
        service.result = .success(makeCityWeather(temperature: 25))
        cache.save(city: WeatherViewModel.defaultCity,
                   response: makeResponse(temperature: 17),
                   at: Date().addingTimeInterval(-WeatherViewModel.foregroundRefreshAfter - 60))

        let viewModel = makeViewModel(service: service)
        let before = service.fetchCount

        await viewModel.refreshOnForeground()

        XCTAssertGreaterThan(service.fetchCount, before)
        XCTAssertEqual(viewModel.entries.first?.weather?.temperature, 25)
    }

    // MARK: - Widget reloads

    /// The widget renders from the shared cache and cannot fetch on the app's
    /// behalf, so a reading the app has and the widget does not is a reading
    /// nobody asked WidgetKit to come and collect.
    func testASuccessfulFetchAsksTheWidgetToReload() async {
        let service = StubWeatherService()
        service.result = .success(makeCityWeather())
        let reloader = CountingReloader()
        let viewModel = makeViewModel(service: service, reloader: reloader)
        reloader.count = 0

        await viewModel.refresh(cityKey: viewModel.entries[0].id)

        XCTAssertEqual(reloader.count, 1)
    }

    func testAFailedFetchDoesNotAskTheWidgetToReload() async {
        let service = StubWeatherService()
        service.result = .failure(WeatherService.WeatherError.offline)
        let reloader = CountingReloader()
        let viewModel = makeViewModel(service: service, reloader: reloader)
        reloader.count = 0

        await viewModel.refresh(cityKey: viewModel.entries[0].id)

        XCTAssertEqual(reloader.count, 0, "Nothing was written for the widget to pick up")
    }

    /// An unconfigured widget shows whichever city is first, so the list
    /// changing can change what a widget displays with no reading involved.
    func testAddingACityAsksTheWidgetToReload() {
        let reloader = CountingReloader()
        let viewModel = makeViewModel(reloader: reloader)
        reloader.count = 0

        viewModel.selectCity(makeTokyoResult())

        XCTAssertGreaterThan(reloader.count, 0)
    }

    func testRemovingACityAsksTheWidgetToReload() {
        let reloader = CountingReloader()
        let viewModel = makeViewModel(reloader: reloader)
        viewModel.selectCity(makeTokyoResult())
        reloader.count = 0

        viewModel.removeCity(viewModel.entries[1])

        XCTAssertGreaterThan(reloader.count, 0)
    }

    // MARK: - Helpers

    private let paris = City(id: UUID(), name: "Paris", country: "France", countryCode: "FR", latitude: 48.8566, longitude: 2.3522)
    private let tokyo = City(id: UUID(), name: "Tokyo", country: "Japan", countryCode: "JP", latitude: 35.6762, longitude: 139.6503)
    private let berlin = City(id: UUID(), name: "Berlin", country: "Germany", countryCode: "DE", latitude: 52.52, longitude: 13.405)

    /// Read back through `SavedCities` rather than decoding the bytes: the
    /// stored shape is versioned now, and a test that hardcodes one version
    /// only pins the format, not the behaviour.
    private func savedNames() throws -> [String] {
        XCTAssertNotNil(defaults.data(forKey: "saved_cities"), "Nothing was saved")
        return SavedCities.load(from: defaults).map(\.name)
    }

    private func makeViewModel(service: WeatherFetching? = nil,
                               reloader: WidgetReloading? = nil) -> WeatherViewModel {
        WeatherViewModel(service: service ?? StubWeatherService(), defaults: defaults,
                         cache: cache, legacyDefaults: legacyDefaults,
                         reloader: reloader ?? CountingReloader())
    }

    // MARK: - Location helpers

    private var locationProvider: StubLocationProvider!
    private var geocoder: StubGeocoder!

    private let tokyoCoordinate = CLLocation(latitude: 35.6762, longitude: 139.6503)

    private var berlinPlace: GeocodedPlace {
        GeocodedPlace(locality: "Berlin", name: "Berlin",
                      country: "Germany", isoCountryCode: "DE")
    }

    private var tokyoPlace: GeocodedPlace {
        GeocodedPlace(locality: "Tokyo", name: "Tokyo",
                      country: "Japan", isoCountryCode: "JP")
    }

    /// Builds a view model whose CoreLocation is a stub. Without this the
    /// located-city paths cannot be reached at all under test — which is how
    /// `upsertCurrentLocation` changed behaviour once with nothing to catch it.
    private func makeViewModel(authorization: CLAuthorizationStatus = .authorizedWhenInUse,
                               locatedAt place: GeocodedPlace? = nil,
                               coordinate: CLLocation? = nil) -> WeatherViewModel {
        let provider = StubLocationProvider()
        provider.authorizationStatus = authorization
        provider.location = coordinate ?? CLLocation(latitude: 52.52, longitude: 13.405)
        locationProvider = provider

        let stubGeocoder = StubGeocoder()
        stubGeocoder.result = .success(place)
        geocoder = stubGeocoder

        return WeatherViewModel(service: StubWeatherService(), defaults: defaults,
                                cache: cache, legacyDefaults: legacyDefaults,
                                reloader: CountingReloader(),
                                locationManager: LocationManager(manager: provider,
                                                                 geocoder: stubGeocoder))
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
    private(set) var fetchCount = 0

    func fetchWeather(for city: City) async throws -> CityWeather {
        if delayNanoseconds > 0 {
            // Not `try?`: URLSession throws URLError.cancelled when its task
            // is cancelled, and a stub that swallows cancellation cannot
            // reproduce the bug this models.
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        try Task.checkCancellation()
        fetchCount += 1

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

/// The widget reads saved cities through this same type, so a disagreement
/// here is a disagreement between the app and its widget.
final class SavedCitiesTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "climyteTests.saved.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private let paris = City(id: UUID(), name: "Paris", country: "France",
                             countryCode: "FR", latitude: 48.8566, longitude: 2.3522)

    func testEmptyStorageReturnsNoCitiesRatherThanADefault() {
        XCTAssertTrue(SavedCities.load(from: defaults).isEmpty,
                      "Substituting a default here would make an unconfigured widget lie")
    }

    func testRoundTrip() {
        SavedCities.save([paris], to: defaults)
        XCTAssertEqual(SavedCities.load(from: defaults).map(\.name), ["Paris"])
    }

    func testReadsTheLegacySingleCityKey() throws {
        defaults.set(try JSONEncoder().encode(paris), forKey: SavedCities.legacySingleCityKey)
        XCTAssertEqual(SavedCities.load(from: defaults).map(\.name), ["Paris"])
    }

    func testCorruptDataDoesNotCrash() {
        defaults.set(Data("not json".utf8), forKey: SavedCities.key)
        XCTAssertTrue(SavedCities.load(from: defaults).isEmpty)
    }

    // MARK: - Versioned store

    /// The shape that shipped first. Anyone upgrading has this on disk, and
    /// reading it is the only thing standing between them and a reset to a
    /// default city.
    func testReadsTheUnversionedArrayThatShippedFirst() throws {
        defaults.set(try JSONEncoder().encode([paris]), forKey: SavedCities.key)
        XCTAssertEqual(SavedCities.load(from: defaults).map(\.name), ["Paris"])
    }

    func testSavingUpgradesTheStoreToTheCurrentVersion() throws {
        defaults.set(try JSONEncoder().encode([paris]), forKey: SavedCities.key)

        SavedCities.save(SavedCities.load(from: defaults), to: defaults)

        let data = try XCTUnwrap(defaults.data(forKey: SavedCities.key))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, SavedCities.version)
        XCTAssertEqual(SavedCities.load(from: defaults).map(\.name), ["Paris"])
    }

    /// The failure this guards is silent and total: the reader is dropped back
    /// to a default city, that default is saved, and their list is gone. The
    /// bytes are kept so the loss is recoverable.
    func testAStoreThisBuildCannotReadIsKeptRatherThanLost() {
        let unreadable = Data(#"{"version":99,"shape":"from a later build"}"#.utf8)
        defaults.set(unreadable, forKey: SavedCities.key)

        XCTAssertTrue(SavedCities.load(from: defaults).isEmpty)
        XCTAssertEqual(defaults.data(forKey: SavedCities.unreadableKey), unreadable)

        // What the app does next: falls back to a default and saves it.
        SavedCities.save([paris], to: defaults)
        XCTAssertEqual(defaults.data(forKey: SavedCities.unreadableKey), unreadable,
                       "The overwrite must not reach the quarantined copy")
    }

    func testTheFirstUnreadableStoreIsTheOneKept() {
        let original = Data("the reader's actual list".utf8)
        defaults.set(original, forKey: SavedCities.key)
        _ = SavedCities.load(from: defaults)

        defaults.set(Data("a later, worse attempt".utf8), forKey: SavedCities.key)
        _ = SavedCities.load(from: defaults)

        XCTAssertEqual(defaults.data(forKey: SavedCities.unreadableKey), original)
    }

    /// A store that reads cleanly and holds nothing is not a fault, and must
    /// not be quarantined — the bare-array format could not tell the two apart.
    func testAnEmptyStoreIsNotTreatedAsUnreadable() throws {
        defaults.set(try JSONEncoder().encode([City]()), forKey: SavedCities.key)

        XCTAssertTrue(SavedCities.load(from: defaults).isEmpty)
        XCTAssertNil(defaults.data(forKey: SavedCities.unreadableKey))
    }
}

/// Records reload requests instead of talking to WidgetKit, which does
/// nothing observable under test.
private final class CountingReloader: WidgetReloading {
    var count = 0
    func reload() { count += 1 }
}


/// CoreLocation stand-in. Resumes the manager's continuation the way the real
/// delegate would, so the async call actually returns.
@MainActor
private final class StubLocationProvider: LocationProviding {
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    var desiredAccuracy: CLLocationAccuracy = 0
    weak var locationDelegate: CLLocationManagerDelegate?

    var location = CLLocation(latitude: 0, longitude: 0)

    func requestWhenInUseAuthorization() {
        (locationDelegate as? LocationManager)?.handleAuthorizationChange()
    }

    func requestLocation() {
        guard let delegate = locationDelegate as? LocationManager else { return }
        delegate.locationManager(CLLocationManager(), didUpdateLocations: [location])
    }
}

private final class StubGeocoder: Geocoding, @unchecked Sendable {
    var result: Result<GeocodedPlace?, Error> = .success(nil)

    func firstPlacemark(for location: CLLocation) async throws -> GeocodedPlace? {
        try result.get()
    }
}
