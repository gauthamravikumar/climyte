//
//  WeatherViewModel.swift
//  climyte
//
//  Created by Antigravity on 23/7/2026.
//

import Foundation
import os
import Combine
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

@MainActor
class WeatherViewModel: ObservableObject {

    /// One entry per saved city, in page order. The located city, when there
    /// is one, is always first.
    @Published private(set) var entries: [CityEntry] = []

    /// Which page is showing. Keyed rather than indexed so a reorder or
    /// deletion can't silently select a different city.
    @Published var selectedCityKey: String = ""

    /// What the search field should be showing. A single state replaces the
    /// old results array, which couldn't distinguish "no matches" from
    /// "the request failed" from "still typing".
    @Published private(set) var searchState: SearchState = .idle

    @Published var searchQuery: String = "" {
        didSet {
            performSearch()
        }
    }

    /// Convenience for callers that only care about the successful case.
    var searchResults: [GeocodingResult] {
        if case .results(let results) = searchState { return results }
        return []
    }

    var selectedEntry: CityEntry? {
        entries.first { $0.id == selectedCityKey } ?? entries.first
    }

    var canRemoveCities: Bool { entries.count > 1 }

    private let savedCitiesKey = "saved_cities"
    private let service: WeatherFetching
    private let defaults: UserDefaults
    private let cache: WeatherCache
    private var searchTask: Task<Void, Never>?

    /// Newest in-flight fetch per city. Results from superseded fetches are
    /// discarded so a slow one can't overwrite a newer one.
    private var fetchTokens: [String: Int] = [:]

    let locationManager = LocationManager()

    static let defaultCity = City(
        id: UUID(), name: "Sydney", country: "Australia", countryCode: "AU",
        latitude: -33.8688, longitude: 151.2093
    )

    /// `service` defaults to the shared instance. It is resolved inside the
    /// initialiser rather than as a default argument, because default arguments
    /// are evaluated in a nonisolated context.
    init(service: WeatherFetching? = nil,
         defaults: UserDefaults = .standard,
         cache: WeatherCache? = nil) {
        self.service = service ?? WeatherService.shared
        self.defaults = defaults
        self.cache = cache ?? WeatherCache()

        let cities = Self.loadSavedCities(from: defaults, key: savedCitiesKey)

        self.entries = cities.map { CityEntry(city: $0) }
        self.selectedCityKey = entries.first?.id ?? ""

        restoreCachedWeather()
    }

    // MARK: - Persistence

    private static func loadSavedCities(from defaults: UserDefaults, key: String) -> [City] {
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([City].self, from: data),
           !saved.isEmpty {
            return saved
        }

        // Migrate anyone upgrading from the single-city build.
        if let data = defaults.data(forKey: "saved_active_city"),
           let legacy = try? JSONDecoder().decode(City.self, from: data) {
            return [legacy]
        }

        return [defaultCity]
    }

    private func saveCities() {
        if let encoded = try? JSONEncoder().encode(entries.map(\.city)) {
            defaults.set(encoded, forKey: savedCitiesKey)
        }
    }

    /// Puts the last successful fetch for every saved city on screen
    /// immediately, so a cold launch renders real data rather than a spinner.
    private func restoreCachedWeather() {
        for index in entries.indices {
            guard let cached = cache.load(for: entries[index].city) else { continue }
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
        cache.prune(keeping: entries.map(\.city))
    }

    func removeCities(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where entries.indices.contains(index) {
            removeCity(entries[index])
        }
    }

    // MARK: - Launch

    /// Paints saved cities immediately, then upgrades to the device's current
    /// location if and when CoreLocation produces one — so a slow or refused
    /// permission prompt never holds up the first render.
    func loadWeatherOnLaunch() async {
        let selectedFirst = refreshSelectedThenRest()

        if let located = await currentLocationCity() {
            upsertCurrentLocation(located)
            await refresh(cityKey: located.key)
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

    /// Replaces the previous located entry rather than accumulating one per
    /// trip, and keeps it pinned to the front.
    private func upsertCurrentLocation(_ city: City) {
        entries.removeAll { $0.isCurrentLocation && $0.city.key != city.key }

        if let index = entries.firstIndex(where: { $0.city.key == city.key }) {
            entries[index].isCurrentLocation = true
            let entry = entries.remove(at: index)
            entries.insert(entry, at: 0)
        } else {
            entries.insert(CityEntry(city: city, isCurrentLocation: true), at: 0)
        }

        selectedCityKey = city.key
        saveCities()
    }

    func refreshSelected() async {
        guard let selected = selectedEntry else { return }
        await refresh(cityKey: selected.id)
    }

    // MARK: - Fetching

    private func nextFetchToken(for cityKey: String) -> Int {
        let next = (fetchTokens[cityKey] ?? 0) + 1
        fetchTokens[cityKey] = next
        return next
    }

    /// Fetches one city, writing the result back into its entry. Safe to call
    /// concurrently for different cities; a superseded fetch for the same city
    /// discards its own result.
    func refresh(cityKey: String) async {
        guard let startIndex = index(of: cityKey) else { return }

        let city = entries[startIndex].city
        let token = nextFetchToken(for: cityKey)

        entries[startIndex].isLoading = true
        entries[startIndex].errorMessage = nil

        do {
            let weather = try await service.fetchWeather(for: city)
            guard fetchTokens[cityKey] == token, let i = index(of: cityKey) else { return }
            entries[i].weather = weather
            entries[i].lastUpdated = Date()
            entries[i].isLoading = false
            cache.save(city: city, response: weather.response)
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
            try? await Task.sleep(nanoseconds: 300_000_000)
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
            case .decodingError, .invalidURL, .networkError:
                break
            }
        }
        return String(localized: "Couldn't search for cities.")
    }
}
