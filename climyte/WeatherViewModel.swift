//
//  WeatherViewModel.swift
//  climyte
//
//  Created by Antigravity on 23/7/2026.
//

import Foundation
import os
import CoreLocation

/// Seam that lets tests drive the view model without touching the network.
protocol WeatherFetching {
    func fetchWeather(for city: City) async throws -> CityWeather
    func searchCities(query: String) async throws -> [GeocodingResult]
}

extension WeatherService: WeatherFetching {}

/// The four things the search field can be showing. Modelling these explicitly
/// keeps "no matches" from standing in for "the request failed".
enum SearchState: Equatable {
    case idle
    case loading
    case results([GeocodingResult])
    case empty
    case failed(String)
}

/// `@Observable`, not `ObservableObject`: with `@Published` every change
/// republished the whole object, so one city's fetch finishing re-rendered the
/// pager and the name strip for all of them. Observation tracks reads per
/// property, so a view only rebuilds for the value it actually uses.
@MainActor
@Observable
class WeatherViewModel {

    /// One entry per saved city, in page order. The located city, when there
    /// is one, is always first.
    private(set) var entries: [CityEntry] = []

    /// Which page is showing. Keyed rather than indexed so a reorder or
    /// deletion can't silently select a different city.
    var selectedCityKey: String = ""

    /// What the search field should be showing. A single state replaces the
    /// old results array, which couldn't distinguish "no matches" from
    /// "the request failed" from "still typing".
    private(set) var searchState: SearchState = .idle

    var searchQuery: String = "" {
        didSet {
            performSearch()
        }
    }

    /// Whether the field holds anything worth searching for.
    ///
    /// Whitespace is not. `performSearch` trims before deciding, so a view
    /// testing `searchQuery.isEmpty` instead disagrees with it: typing a
    /// single space left the search idle while the view had already switched
    /// away from the saved-cities list, and the reader got a blank screen.
    var hasSearchQuery: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True once the app has asked for location and been refused. The saved
    /// list says so rather than simply not showing a city for where they are,
    /// which is indistinguishable from the feature not existing.
    private(set) var locationAccessRefused = false

    var selectedEntry: CityEntry? {
        entries.first { $0.id == selectedCityKey } ?? entries.first
    }

    var canRemoveCities: Bool { entries.count > 1 }

    private static let savedCitiesKeyName = "saved_cities"
    private let service: WeatherFetching
    private let defaults: UserDefaults
    private let cache: WeatherCache
    private let reloader: WidgetReloading

    /// Where the list's other copies live. Injected alongside `defaults`
    /// because they are part of the same store: a copy belonging to a
    /// different store would answer for one it knows nothing about.
    private let citiesSources: SavedCities.Sources

    /// False when the saved list could not be read from any source. While it
    /// is false the app still works, but it must not act as though the list
    /// it is showing is the reader's real one.
    private let listWasReadable: Bool

    /// True while the only city is the stand-in shown before anything is
    /// known about the reader. It gives way to their own location when that
    /// arrives: left in place, a new install in Melbourne opened as
    /// "Melbourne, Sydney", with a city nobody chose.
    private var isShowingStandInCity: Bool

    /// The quarter hour the pages were last brought up to date in.
    private var lastQuarterHour = WeatherViewModel.quarterHour(of: Date())
    private var searchTask: Task<Void, Never>?

    /// Newest in-flight fetch per city. Results from superseded fetches are
    /// discarded so a slow one can't overwrite a newer one.
    private var fetchTokens: [String: Int] = [:]

    private let locationManager: LocationManager

    static let defaultCity = City(
        id: UUID(), name: "Sydney", country: "Australia", countryCode: "AU",
        latitude: -33.8688, longitude: 151.2093
    )

    /// `service` defaults to the shared instance. It is resolved inside the
    /// initialiser rather than as a default argument, because default arguments
    /// are evaluated in a nonisolated context.
    /// `legacyDefaults` is where pre-App-Group data is migrated from. It is
    /// injectable because it defaults to `UserDefaults.standard`, which under
    /// test is the host app's own storage — reading it unconditionally would
    /// pull real cities into every isolated test suite.
    init(service: WeatherFetching? = nil,
         defaults: UserDefaults? = nil,
         cache: WeatherCache? = nil,
         legacyDefaults: UserDefaults? = nil,
         reloader: WidgetReloading? = nil,
         locationManager: LocationManager? = nil,
         citiesSources: SavedCities.Sources) {
        let defaults = defaults ?? AppGroup.defaults
        Self.migrateIfNeeded(from: legacyDefaults ?? .standard,
                             into: defaults,
                             key: Self.savedCitiesKeyName)

        self.service = service ?? WeatherService.shared
        self.defaults = defaults
        self.cache = cache ?? WeatherCache()
        self.reloader = reloader ?? WidgetReloader.shared
        self.locationManager = locationManager ?? LocationManager()
        self.citiesSources = citiesSources

        // nil means no source could be read. That is not a reader with no
        // cities, and must not be mistaken for one.
        let loaded = SavedCities.loadIfReadable(from: defaults, sources: citiesSources)
        self.listWasReadable = loaded != nil
        self.isShowingStandInCity = loaded?.isEmpty == true

        let cities = (loaded ?? []).isEmpty ? [Self.defaultCity] : (loaded ?? [])

        self.entries = cities.map { CityEntry(city: $0) }
        self.selectedCityKey = entries.first?.id ?? ""

        restoreCachedWeather()

        // Repairs a cache that grew under an earlier build, where pruning only
        // happened on an explicit delete. Skipped when the saved list could
        // not be read: pruning against the fallback city is how a failed read
        // turned into three cities' readings being deleted at launch.
        if listWasReadable {
            self.cache.prune(keeping: entries.map(\.city))
        }
    }

    // MARK: - Persistence

    /// Moves cities saved before the App Group existed into shared storage.
    ///
    /// Without this an existing install would silently reset to the default
    /// city on upgrade, because the widget-readable suite starts empty while
    /// the real data sits in `.standard`.
    private static func migrateIfNeeded(from legacy: UserDefaults,
                                       into defaults: UserDefaults,
                                       key: String) {
        guard legacy !== defaults else { return }
        guard defaults.data(forKey: key) == nil else { return }

        if let cities = legacy.data(forKey: key) {
            defaults.set(cities, forKey: key)
        } else if let single = legacy.data(forKey: "saved_active_city") {
            defaults.set(single, forKey: "saved_active_city")
        }
    }


    private func saveCities() {
        // A list the reader has added to or reordered is theirs, stand-in
        // and all.
        isShowingStandInCity = false
        SavedCities.save(entries.map(\.city), to: defaults, sources: citiesSources)
        // Every path that changes the saved list comes through here, which
        // makes it the one place pruning cannot be forgotten — unless we
        // never knew the list, in which case there is nothing to prune
        // against.
        if listWasReadable {
            cache.prune(keeping: entries.map(\.city))
        }
        // The widget picks its city from this list, and an unconfigured one
        // falls back to whichever is first — so adding, removing or promoting
        // a city can change what a widget shows without any reading changing.
        reloader.reload()
    }

    /// Puts the last successful fetch for every saved city on screen
    /// immediately, so a cold launch renders real data rather than a spinner.
    ///
    /// Also how a page is kept honest without the network. `CityWeather`
    /// works out "today", the hours ahead and the rain timing when it is
    /// built, so rebuilding from the same response re-resolves all of them
    /// against the present moment.
    ///
    /// One read of the file for every city. Asking the cache city by city
    /// decoded the whole file each time.
    private func restoreCachedWeather() {
        let cachedByKey = Dictionary(cache.loadAll().map { ($0.city.key, $0) },
                                     uniquingKeysWith: { first, _ in first })
        for index in entries.indices {
            guard let cached = cachedByKey[entries[index].city.key] else { continue }
            entries[index].weather = CityWeather(city: cached.city, response: cached.response)
            entries[index].lastUpdated = cached.fetchedAt
        }
    }

    // MARK: - Cities

    /// Adds a searched city, or selects it if already saved.
    func selectCity(_ result: GeocodingResult) {
        let newCity = City(
            id: UUID(),
            name: result.name,
            country: result.country ?? "",
            countryCode: result.country_code,
            latitude: result.latitude,
            longitude: result.longitude
        )

        searchQuery = ""

        if let existing = entries.first(where: { $0.city.key == newCity.key }) {
            selectedCityKey = existing.id
            return
        }

        entries.append(CityEntry(city: newCity))
        selectedCityKey = newCity.key
        saveCities()

        Task { await self.refresh(cityKey: newCity.key) }
    }

    func selectEntry(_ entry: CityEntry) {
        selectedCityKey = entry.id
    }

    /// Removes a city. The last remaining city can't be removed — an empty app
    /// has nothing to show and no way back.
    func removeCity(_ entry: CityEntry) {
        guard canRemoveCities, let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }

        entries.remove(at: index)
        if selectedCityKey == entry.id {
            selectedCityKey = entries[min(index, entries.count - 1)].id
        }

        saveCities()
    }

    func removeCities(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where entries.indices.contains(index) {
            removeCity(entries[index])
        }
    }

    /// Reorders the saved cities. The order is the pager's order and the name
    /// strip's, so this is the one place someone can decide which city they
    /// land on and what sits beside it.
    /// `destination` is an insertion point in the list *before* the move, which
    /// is SwiftUI's convention — spelled out here rather than reached for via
    /// `move(fromOffsets:toOffset:)` so the view model stays free of SwiftUI.
    func moveCities(from offsets: IndexSet, to destination: Int) {
        let indices = offsets.sorted().filter { entries.indices.contains($0) }
        guard !indices.isEmpty else { return }

        let moving = indices.map { entries[$0] }
        var remaining = entries
        for index in indices.reversed() {
            remaining.remove(at: index)
        }

        let insertAt = destination - indices.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: min(max(insertAt, 0), remaining.count))

        guard remaining.map(\.id) != entries.map(\.id) else { return }
        entries = remaining
        saveCities()
    }

    // MARK: - Launch

    /// Paints saved cities immediately, then upgrades to the device's current
    /// location if and when CoreLocation produces one — so a slow or refused
    /// permission prompt never holds up the first render.
    func loadWeatherOnLaunch() async {
        let selectedFirst = refreshSelectedThenRest()

        if let located = await currentLocationCity() {
            locationAccessRefused = false
            await refresh(cityKey: upsertCurrentLocation(located, select: true))
        } else {
            locationAccessRefused = locationManager.accessIsRefused
        }

        await selectedFirst.value
    }

    /// The visible page is fetched first; the rest follow concurrently so
    /// swiping to another city finds it already loaded.
    private func refreshSelectedThenRest() -> Task<Void, Never> {
        Task {
            if let selected = self.selectedEntry {
                await self.refresh(cityKey: selected.id)
            }

            await withTaskGroup(of: Void.self) { group in
                for entry in self.entries where entry.id != self.selectedCityKey {
                    group.addTask { await self.refresh(cityKey: entry.id) }
                }
            }
        }
    }

    /// Marks the entry for where the reader is, adding it at the front when it
    /// is new, and returns its key.
    ///
    /// Replaces the previous located entry rather than accumulating one per
    /// trip. A city already in the list keeps its place: it used to be dragged
    /// back to the front on every launch, which silently undid a reordering
    /// the moment the location resolved.
    ///
    /// `select` is false when the reader has merely come back to the app on
    /// another city's page. Having moved is not a reason to turn their page.
    @discardableResult
    private func upsertCurrentLocation(_ located: City, select: Bool) -> String {
        let idsBefore = entries.map(\.id)

        if isShowingStandInCity {
            entries.removeAll { $0.city.key == Self.defaultCity.key }
            isShowingStandInCity = false
        }

        let key = entryID(samePlaceAs: located) ?? located.key
        entries.removeAll { $0.isCurrentLocation && $0.id != key }

        if let index = index(of: key) {
            entries[index].isCurrentLocation = true
        } else {
            entries.insert(CityEntry(city: located, isCurrentLocation: true), at: 0)
        }

        if select || index(of: selectedCityKey) == nil {
            selectedCityKey = key
        }

        // Only when the list itself changed. Which entry is the located one is
        // not stored, so saving for that alone would rewrite the list and
        // reload every widget each time the app came forward.
        if entries.map(\.id) != idsBefore {
            saveCities()
        }
        return key
    }

    /// The saved city that is the same place as a located one, if any.
    ///
    /// Coordinates alone cannot say. A fix lands somewhere different in the
    /// same town each time, so keyed by where the fix fell the located city
    /// was a new city on every launch: a second "Melbourne" beside the saved
    /// one, its cached reading lost with its key. The same name within this
    /// distance is the same place as far as a forecast is concerned.
    private func entryID(samePlaceAs located: City) -> String? {
        if let exact = index(of: located.key) { return entries[exact].id }

        let here = CLLocation(latitude: located.latitude, longitude: located.longitude)
        return entries.first {
            $0.city.name == located.name
                && CLLocation(latitude: $0.city.latitude, longitude: $0.city.longitude)
                    .distance(from: here) < Self.samePlaceRadius
        }?.id
    }

    static let samePlaceRadius: CLLocationDistance = 50_000

    /// Brings the app back up to date when it returns to the foreground.
    ///
    /// Three separate problems. The pages describe the moment they were
    /// built, so an app left overnight keeps labelling yesterday "Today":
    /// rebuilding from the cached response fixes that without a request. The
    /// reading itself may simply be old, which needs the network. And the
    /// reader may have travelled since the app last asked where they are.
    func refreshOnForeground() async {
        async let location: Void = followCurrentLocation()
        await bringUpToDate()
        await location
    }

    /// Called on every tick of the app's clock, and acts once a quarter hour.
    ///
    /// Coming forward was the only thing that brought a page up to date, so
    /// an app left open kept its hours, its "Starts 6:15 pm" and its Rain row
    /// exactly as they were when the reading arrived. A quarter hour because
    /// that is the step the rain outlook moves in.
    func clockTicked(_ now: Date) async {
        let quarter = Self.quarterHour(of: now)
        guard quarter != lastQuarterHour else { return }
        lastQuarterHour = quarter
        await bringUpToDate(now: now)
    }

    private static func quarterHour(of date: Date) -> Int {
        (date.timeIntervalSince1970 / 900).toInt(.down)
    }

    /// Rebuilds every page for the present moment, then fetches any reading
    /// old enough to be worth replacing.
    private func bringUpToDate(now: Date = Date()) async {
        restoreCachedWeather()

        let stale = entries.filter {
            guard let updated = $0.lastUpdated else { return true }
            return now.timeIntervalSince(updated) >= Self.foregroundRefreshAfter
        }
        guard !stale.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for entry in stale {
                group.addTask { await self.refresh(cityKey: entry.id) }
            }
        }
    }

    /// Re-checks where the reader is, once they have already said yes.
    ///
    /// Never the first ask: a permission prompt belongs to launch, not to
    /// switching back from another app.
    private func followCurrentLocation() async {
        guard locationManager.isAuthorized, let located = await currentLocationCity() else { return }

        let previous = entries.first(where: \.isCurrentLocation)?.id
        let key = upsertCurrentLocation(located, select: selectedEntry?.isCurrentLocation == true)
        if key != previous {
            await refresh(cityKey: key)
        }
    }

    /// Below this, returning to the app does not re-fetch. Weather does not
    /// move fast enough to justify a request every time someone switches back.
    static let foregroundRefreshAfter: TimeInterval = 15 * 60

    // MARK: - Fetching

    private func nextFetchToken(for cityKey: String) -> Int {
        let next = (fetchTokens[cityKey] ?? 0) + 1
        fetchTokens[cityKey] = next
        return next
    }

    /// Fetches one city, writing the result back into its entry.
    ///
    /// The work runs in an unstructured task so it outlives whichever view
    /// asked for it. `.refreshable` runs its closure in a task tied to the
    /// refresh control, and the first thing a fetch does is set `isLoading`,
    /// which republishes `entries`, rebuilds the `ForEach` inside the
    /// `TabView` and tears that task down — cancelling the very request it
    /// was awaiting. An unstructured task does not inherit that cancellation.
    ///
    /// Deliberately does not de-duplicate concurrent refreshes of one city:
    /// joining an in-flight request would hand back a result fetched under
    /// earlier conditions. `fetchToken` already discards superseded results.
    func refresh(cityKey: String) async {
        guard let startIndex = index(of: cityKey) else { return }

        // Claim the token and mark loading synchronously, before the task hop.
        // Two refreshes of one city must be ordered by when they were asked
        // for, not by when their tasks happen to get scheduled — otherwise a
        // background refresh started earlier can claim the higher token and
        // overwrite the result of a later, more deliberate one.
        let city = entries[startIndex].city
        let token = nextFetchToken(for: cityKey)

        entries[startIndex].isLoading = true
        entries[startIndex].errorMessage = nil

        await Task { await self.performRefresh(city: city, cityKey: cityKey, token: token) }.value
    }

    private func performRefresh(city: City, cityKey: String, token: Int) async {
        do {
            let weather = try await service.fetchWeather(for: city)
            guard fetchTokens[cityKey] == token, let i = index(of: cityKey) else { return }
            entries[i].weather = weather
            entries[i].lastUpdated = Date()
            entries[i].isLoading = false
            cache.save(city: city, response: weather.response)
            // The widget reads this cache and cannot fetch for itself.
            reloader.reload()
        } catch {
            guard fetchTokens[cityKey] == token, let i = index(of: cityKey) else { return }
            Log.weather.error("Fetch failed for \(city.name, privacy: .public): \(error.localizedDescription)")
            entries[i].errorMessage = Self.userMessage(for: error, city: city)
            entries[i].isLoading = false
        }
    }

    /// Re-resolves the index after awaiting — the array may have been
    /// reordered or had a city removed while the request was in flight.
    private func index(of cityKey: String) -> Int? {
        entries.firstIndex { $0.id == cityKey }
    }

    private func currentLocationCity() async -> City? {
        guard let location = await locationManager.requestCurrentLocation(),
              let geo = await locationManager.reverseGeocode(location) else {
            return nil
        }

        return City(
            id: UUID(),
            name: geo.city,
            country: geo.country,
            countryCode: geo.countryCode,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    /// Maps a thrown error onto something worth showing a person.
    static func userMessage(for error: Error, city: City) -> String {
        if let weatherError = error as? WeatherService.WeatherError {
            switch weatherError {
            case .offline:
                return String(localized: "No internet connection.")
            case .serverError:
                return String(localized: "The weather service is unavailable right now.")
            case .decodingError:
                return String(localized: "Couldn't read the weather data for \(city.name).")
            case .timedOut:
                return String(localized: "The request timed out.")
            case .unreachable:
                return String(localized: "Couldn't reach the weather service.")
            case .insecureConnection:
                return String(localized: "Secure connection failed — check the date and time on your device.")
            case .networkError(let underlying):
                // Naming the code is ugly but it is the only thing that
                // identifies an otherwise anonymous failure, and it is what
                // someone can actually report back.
                if let urlError = underlying as? URLError {
                    // Interpolated as a String, not an Int: integer
                    // interpolation applies a grouping separator, rendering
                    // URLError -1007 as "-1,007" — or "-1.007" in locales that
                    // group with periods. An error code is an identifier, not
                    // a quantity.
                    let code = String(urlError.code.rawValue)
                    return String(localized: "Couldn't load weather (error \(code)).")
                }
                break
            case .invalidURL:
                break
            }
        }
        return String(localized: "Couldn't load weather for \(city.name).")
    }

    // MARK: - Search

    private func performSearch() {
        searchTask?.cancel()

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchState = .idle
            return
        }

        searchState = .loading

        searchTask = Task {
            // Debounce for 300ms
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }

            do {
                let results = try await service.searchCities(query: query)
                if Task.isCancelled { return }
                searchState = results.isEmpty ? .empty : .results(results)
            } catch {
                if Task.isCancelled { return }
                Log.weather.error("City search failed: \(error.localizedDescription)")
                searchState = .failed(Self.searchErrorMessage(for: error))
            }
        }
    }

    /// Re-runs the last search. Bound to the retry button on the failure state.
    func retrySearch() {
        performSearch()
    }

    static func searchErrorMessage(for error: Error) -> String {
        if let weatherError = error as? WeatherService.WeatherError {
            switch weatherError {
            case .offline:
                return String(localized: "No internet connection.")
            case .serverError:
                return String(localized: "City search is unavailable right now.")
            case .timedOut:
                return String(localized: "The request timed out.")
            case .unreachable:
                return String(localized: "Couldn't reach the weather service.")
            case .insecureConnection:
                return String(localized: "Secure connection failed — check the date and time on your device.")
            case .networkError(let underlying):
                // The weather path names the code; a search that fails for the
                // same reason should not be more mysterious than the fetch
                // beside it.
                if let urlError = underlying as? URLError {
                    let code = String(urlError.code.rawValue)
                    return String(localized: "Couldn't search for cities (error \(code)).")
                }
            case .decodingError, .invalidURL:
                break
            }
        }
        return String(localized: "Couldn't search for cities.")
    }
}
