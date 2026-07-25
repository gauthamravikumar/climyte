//
//  WeatherService.swift
//  climyte
//
//  Created by Antigravity on 23/7/2026.
//

import Foundation

class WeatherService {
    static let shared = WeatherService()
    private init() {}
    
    enum WeatherError: LocalizedError {
        case invalidURL
        case noData
        case decodingError
        case networkError(Error)
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "The API URL was invalid."
            case .noData:
                return "No weather data was returned from the server."
            case .decodingError:
                return "Failed to parse the weather data response."
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            }
        }
    }
    
    func searchCities(query: String) async throws -> [GeocodingResult] {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(encodedQuery)&count=10&language=en&format=json") else {
            throw WeatherError.invalidURL
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            // Check status code if needed, but let's parse directly
            let result = try JSONDecoder().decode(GeocodingResponse.self, from: data)
            return result.results ?? []
        } catch let decodingError as DecodingError {
            print("Decoding error: \(decodingError)")
            throw WeatherError.decodingError
        } catch {
            throw WeatherError.networkError(error)
        }
    }
    
    func fetchWeather(for city: City) async throws -> CityWeather {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(city.latitude)&longitude=\(city.longitude)&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,wind_speed_10m,weather_code&hourly=temperature_2m,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max,precipitation_probability_max&timezone=auto&temperature_unit=celsius"
        guard let url = URL(string: urlString) else {
            throw WeatherError.invalidURL
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try JSONDecoder().decode(WeatherResponse.self, from: data)
            return CityWeather(city: city, response: result)
        } catch let decodingError as DecodingError {
            print("Decoding error: \(decodingError)")
            throw WeatherError.decodingError
        } catch {
            throw WeatherError.networkError(error)
        }
    }
}
