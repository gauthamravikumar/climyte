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
    @Published var favoriteWeatherList: [CityWeather] = []
    @Published var selectedWeather: CityWeather?
    @Published var searchResults: [GeocodingResult] = []
    @Published var searchQuery: String = "" {
        didSet {
            performSearch()
        }
    }
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private var favorites: [City] = []
    private let favoritesKey = "saved_favorite_cities"
    private var searchTask: Task<Void, Never>?
    
    init() {
        loadSavedFavorites()
    }
    
    func loadSavedFavorites() {
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let saved = try? JSONDecoder().decode([City].self, from: data) {
            self.favorites = saved
        } else {
            // Default pre-populated list
            self.favorites = [
                City(id: UUID(), name: "Sydney", country: "Australia", latitude: -33.8688, longitude: 151.2093),
                City(id: UUID(), name: "New York", country: "United States", latitude: 40.7128, longitude: -74.0060),
                City(id: UUID(), name: "London", country: "United Kingdom", latitude: 51.5074, longitude: -0.1278),
                City(id: UUID(), name: "Tokyo", country: "Japan", latitude: 35.6762, longitude: 139.6503)
            ]
            saveFavorites()
        }
    }
    
    private func saveFavorites() {
        if let encoded = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(encoded, forKey: favoritesKey)
        }
    }
    
    func fetchWeatherForFavorites() async {
        guard !favorites.isEmpty else {
            self.favoriteWeatherList = []
            self.isLoading = false
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        var tempWeatherList: [CityWeather] = []
        
        await withTaskGroup(of: CityWeather?.self) { group in
            for city in favorites {
                group.addTask {
                    do {
                        return try await WeatherService.shared.fetchWeather(for: city)
                    } catch {
                        print("Failed to fetch weather for \(city.name): \(error.localizedDescription)")
                        return nil
                    }
                }
            }
            
            for await weather in group {
                if let weather = weather {
                    tempWeatherList.append(weather)
                }
            }
        }
        
        // Sort to match the order of favorites
        self.favoriteWeatherList = favorites.compactMap { city in
            tempWeatherList.first(where: { 
                $0.city.id == city.id || 
                (abs($0.city.latitude - city.latitude) < 0.01 && abs($0.city.longitude - city.longitude) < 0.01)
            })
        }
        
        if selectedWeather == nil, let firstWeather = favoriteWeatherList.first {
            selectedWeather = firstWeather
        } else if let selected = selectedWeather {
            // Update the selected weather object if it was refreshed
            if let updatedSelected = favoriteWeatherList.first(where: { $0.city.name == selected.city.name }) {
                selectedWeather = updatedSelected
            }
        }
        
        isLoading = false
    }
    
    func selectCityWeather(_ weather: CityWeather) {
        selectedWeather = weather
    }
    
    func addCityToFavorites(_ result: GeocodingResult) async {
        let newCity = City(
            id: UUID(),
            name: result.name,
            country: result.country ?? "",
            latitude: result.latitude,
            longitude: result.longitude
        )
        
        // Avoid duplicates
        if !favorites.contains(where: { abs($0.latitude - newCity.latitude) < 0.01 && abs($0.longitude - newCity.longitude) < 0.01 }) {
            favorites.append(newCity)
            saveFavorites()
            
            do {
                isLoading = true
                let weather = try await WeatherService.shared.fetchWeather(for: newCity)
                self.favoriteWeatherList.append(weather)
                self.selectedWeather = weather
                isLoading = false
            } catch {
                isLoading = false
                self.errorMessage = "Failed to fetch weather for \(newCity.name)."
            }
        } else {
            // Already in favorites, just select it
            if let existingWeather = favoriteWeatherList.first(where: { abs($0.city.latitude - newCity.latitude) < 0.01 }) {
                self.selectedWeather = existingWeather
            }
        }
        
        // Clear search
        searchQuery = ""
        searchResults = []
    }
    
    func removeCityFromFavorites(_ weather: CityWeather) {
        favorites.removeAll(where: { abs($0.latitude - weather.city.latitude) < 0.01 && abs($0.longitude - weather.city.longitude) < 0.01 })
        saveFavorites()
        
        favoriteWeatherList.removeAll(where: { $0.id == weather.id })
        
        // If the selected city was removed, reset it
        if selectedWeather?.id == weather.id {
            selectedWeather = favoriteWeatherList.first
        }
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
