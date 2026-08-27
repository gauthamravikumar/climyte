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
    @Published var activeWeather: CityWeather?

    /// What the search field should be showing. A single state replaces the
    /// old results array, which couldn't distinguish "no matches" from
    /// "the request failed" from "still typing".
    @Published private(set) var searchState: SearchState = .idle

    @Published var searchQuery: String = "" {
        didSet {
            performSearch()
        }
    }
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isUsingCurrentLocation: Bool = false

    /// Convenience for callers that only care about the successful case.
    var searchResults: [GeocodingResult] {
        if case .results(let results) = searchState { return results }
        return []
    }

    /// When the displayed reading was fetched — may predate this launch, since
    /// cached weather is shown before the network answers.
    @Published var lastUpdated: Date?

    @Published var unitSystem: UnitSystem {
        didSet {
            defaults.set(unitSystem.rawValue, forKey: unitSystemKey)
        }
    }

    /// Setting this only persists the choice. Fetching is always explicit, so
    /// callers control ordering instead of inheriting a hidden side effect.
    @Published var activeCity: City {
        didSet { saveActiveCity() }
    }

    private let activeCityKey = "saved_active_city"
    private let unitSystemKey = "unit_system"
    private let service: WeatherFetching
    private let defaults: UserDefaults
    private let cache: WeatherCache
    private var searchTask: Task<Void, Never>?

    /// Monotonic counter identifying the newest in-flight fetch. Results from
    /// superseded fetches are discarded so a slow one can't overwrite a newer one.
    private var fetchToken = 0

    let locationManager = LocationManager()

    /// `service` defaults to the shared instance. It is resolved inside the
    /// initialiser rather than as a default argument, because default arguments
    /// are evaluated in a nonisolated context.
    init(service: WeatherFetching? = nil,
         defaults: UserDefaults = .standard,
         cache: WeatherCache? = nil) {
        self.service = service ?? WeatherService.shared
        self.defaults = defaults
        self.cache = cache ?? WeatherCache()

        // Load persistently or default to Sydney
        if let data = defaults.data(forKey: activeCityKey),
           let saved = try? JSONDecoder().decode(City.self, from: data) {
            self.activeCity = saved
        } else {
            self.activeCity = City(id: UUID(), name: "Sydney", country: "Australia", latitude: -33.8688, longitude: 151.2093)
        }

        // Seed from the device's region until the user says otherwise.
        if let stored = defaults.string(forKey: unitSystemKey),
           let system = UnitSystem(rawValue: stored) {
            self.unitSystem = system
        } else {
            self.unitSystem = .deviceDefault
        }

        restoreCachedWeather()
    }

    /// Puts the last successful fetch on screen immediately, so a cold launch
    /// shows real data rather than a spinner while the network is in flight.
    private func restoreCachedWeather() {
        guard let cached = cache.load(), cached.city == activeCity else { return }
        activeWeather = CityWeather(city: cached.city, response: cached.response)
        lastUpdated = cached.fetchedAt
    }

    func toggleUnitSystem() {
        unitSystem = unitSystem.toggled
    }

    private func saveActiveCity() {
        if let encoded = try? JSONEncoder().encode(activeCity) {
            defaults.set(encoded, forKey: activeCityKey)
        }
    }

    /// Called on app launch. Paints the saved city immediately, then upgrades to
    /// the device's current location if and when CoreLocation produces one — so
    /// a slow or refused permission prompt never holds up the first render.
    func loadWeatherOnLaunch() async {
        let savedCity = activeCity
        let savedToken = nextFetchToken()
        let savedCityFetch = Task { await self.performFetch(city: savedCity, token: savedToken) }

        if let located = await currentLocationCity() {
            isUsingCurrentLocation = true
            activeCity = located
            await performFetch(city: located, token: nextFetchToken())
        }

        await savedCityFetch.value
    }

    func fetchWeatherForActiveCity() async {
        await performFetch(city: activeCity, token: nextFetchToken())
    }

    func selectCity(_ result: GeocodingResult) {
        let newCity = City(
            id: UUID(),
            name: result.name,
            country: result.country ?? "",
            latitude: result.latitude,
            longitude: result.longitude
        )
        isUsingCurrentLocation = false
        activeCity = newCity

        // Clear search
        searchQuery = ""

        Task { await self.fetchWeatherForActiveCity() }
    }

    // MARK: - Fetching

    private func nextFetchToken() -> Int {
        fetchToken += 1
        return fetchToken
    }

    private func performFetch(city: City, token: Int) async {
        isLoading = true
        errorMessage = nil

        do {
            let weather = try await service.fetchWeather(for: city)
            guard token == fetchToken else { return }
            activeWeather = weather
            lastUpdated = Date()
            cache.save(city: city, response: weather.response)
        } catch {
            guard token == fetchToken else { return }
            Log.weather.error("Fetch failed for \(city.name, privacy: .public): \(error.localizedDescription)")
            errorMessage = Self.userMessage(for: error, city: city)
        }

        guard token == fetchToken else { return }
        isLoading = false
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
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    /// Maps a thrown error onto something worth showing a person.
    static func userMessage(for error: Error, city: City) -> String {
        if let weatherError = error as? WeatherService.WeatherError {
            switch weatherError {
            case .offline:
                return "No internet connection."
            case .serverError:
                return "The weather service is unavailable right now."
            case .decodingError:
                return "Couldn't read the weather data for \(city.name)."
            case .invalidURL, .networkError:
                break
            }
        }
        return "Couldn't load weather for \(city.name)."
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
                return "No internet connection."
            case .serverError:
                return "City search is unavailable right now."
            case .decodingError, .invalidURL, .networkError:
                break
            }
        }
        return "Couldn't search for cities."
    }
}
