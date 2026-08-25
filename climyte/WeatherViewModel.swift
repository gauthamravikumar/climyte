//
//  WeatherViewModel.swift
//  climyte
//
//  Created by Antigravity on 23/7/2026.
//

import Foundation
import Combine
import CoreLocation

/// Seam that lets tests drive the view model without touching the network.
protocol WeatherFetching {
    func fetchWeather(for city: City) async throws -> CityWeather
    func searchCities(query: String) async throws -> [GeocodingResult]
}

extension WeatherService: WeatherFetching {}

@MainActor
class WeatherViewModel: ObservableObject {
    @Published var activeWeather: CityWeather?
    @Published var searchResults: [GeocodingResult] = []
    @Published var searchQuery: String = "" {
        didSet {
            performSearch()
        }
    }
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isUsingCurrentLocation: Bool = false

    /// Setting this only persists the choice. Fetching is always explicit, so
    /// callers control ordering instead of inheriting a hidden side effect.
    @Published var activeCity: City {
        didSet { saveActiveCity() }
    }

    private let activeCityKey = "saved_active_city"
    private let service: WeatherFetching
    private let defaults: UserDefaults
    private var searchTask: Task<Void, Never>?

    /// Monotonic counter identifying the newest in-flight fetch. Results from
    /// superseded fetches are discarded so a slow one can't overwrite a newer one.
    private var fetchToken = 0

    let locationManager = LocationManager()

    /// `service` defaults to the shared instance. It is resolved inside the
    /// initialiser rather than as a default argument, because default arguments
    /// are evaluated in a nonisolated context.
    init(service: WeatherFetching? = nil, defaults: UserDefaults = .standard) {
        self.service = service ?? WeatherService.shared
        self.defaults = defaults

        // Load persistently or default to Sydney
        if let data = defaults.data(forKey: activeCityKey),
           let saved = try? JSONDecoder().decode(City.self, from: data) {
            self.activeCity = saved
        } else {
            self.activeCity = City(id: UUID(), name: "Sydney", country: "Australia", latitude: -33.8688, longitude: 151.2093)
        }
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
        searchResults = []

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
        } catch {
            guard token == fetchToken else { return }
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
            searchResults = []
            return
        }

        searchTask = Task {
            // Debounce for 300ms
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }

            do {
                let results = try await service.searchCities(query: query)
                if !Task.isCancelled {
                    self.searchResults = results
                }
            } catch {
                print("Search error: \(error)")
            }
        }
    }
}
