//
//  WeatherViewModel.swift
//  climyte
//
//  Created by Antigravity on 23/7/2026.
//

import Foundation
import Combine

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
    
    @Published var activeCity: City {
        didSet {
            saveActiveCity()
            Task {
                await fetchWeatherForActiveCity()
            }
        }
    }
    
    private let activeCityKey = "saved_active_city"
    private let hasUsedLocationKey = "has_used_location"
    private var searchTask: Task<Void, Never>?
    let locationManager = LocationManager()
    
    init() {
        // Load persistently or default to Sydney
        if let data = UserDefaults.standard.data(forKey: activeCityKey),
           let saved = try? JSONDecoder().decode(City.self, from: data) {
            self.activeCity = saved
        } else {
            self.activeCity = City(id: UUID(), name: "Sydney", country: "Australia", latitude: -33.8688, longitude: 151.2093)
        }
    }
    
    private func saveActiveCity() {
        if let encoded = try? JSONEncoder().encode(activeCity) {
            UserDefaults.standard.set(encoded, forKey: activeCityKey)
        }
    }
    
    /// Called on app launch — tries current location first, falls back to saved city.
    func loadWeatherOnLaunch() async {
        isLoading = true
        errorMessage = nil
        
        // Try to get the user's current location
        if let location = await locationManager.requestCurrentLocation() {
            if let geo = await locationManager.reverseGeocode(location) {
                let locCity = City(
                    id: UUID(),
                    name: geo.city,
                    country: geo.country,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
                self.isUsingCurrentLocation = true
                // Save and fetch without triggering didSet fetch (we do it below)
                if let encoded = try? JSONEncoder().encode(locCity) {
                    UserDefaults.standard.set(encoded, forKey: activeCityKey)
                }
                // Update activeCity directly and fetch
                self.activeCity = locCity
                // activeCity didSet already triggers fetch, so just return
                return
            }
        }
        
        // Fallback: fetch weather for saved/default city
        await fetchWeatherForActiveCity()
    }
    
    func fetchWeatherForActiveCity() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let weather = try await WeatherService.shared.fetchWeather(for: activeCity)
            self.activeWeather = weather
        } catch {
            self.errorMessage = "Failed to fetch weather for \(activeCity.name)."
        }
        
        isLoading = false
    }
    
    func selectCity(_ result: GeocodingResult) {
        let newCity = City(
            id: UUID(),
            name: result.name,
            country: result.country ?? "",
            latitude: result.latitude,
            longitude: result.longitude
        )
        self.isUsingCurrentLocation = false
        self.activeCity = newCity
        
        // Clear search
        searchQuery = ""
        searchResults = []
    }
    
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
                let results = try await WeatherService.shared.searchCities(query: query)
                if !Task.isCancelled {
                    self.searchResults = results
                }
            } catch {
                print("Search error: \(error)")
            }
        }
    }
}
