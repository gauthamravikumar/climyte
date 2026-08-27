//
//  WeatherService.swift
//  climyte
//
//  Created by Antigravity on 23/7/2026.
//

import Foundation
import os

class WeatherService {
    static let shared = WeatherService()
    private init() {}

    enum WeatherError: LocalizedError {
        case invalidURL
        case serverError(statusCode: Int)
        case decodingError
        case offline
        case timedOut
        case unreachable
        case insecureConnection
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "The API URL was invalid."
            case .serverError(let statusCode):
                return "The weather service returned an error (HTTP \(statusCode))."
            case .decodingError:
                return "Failed to parse the weather data response."
            case .offline:
                return "No internet connection."
            case .timedOut:
                return "The request timed out."
            case .unreachable:
                return "Could not reach the weather service."
            case .insecureConnection:
                return "The secure connection failed."
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

        let data = try await get(url)
        do {
            let result = try JSONDecoder().decode(GeocodingResponse.self, from: data)
            return result.results ?? []
        } catch {
            throw WeatherError.decodingError
        }
    }

    func fetchWeather(for city: City) async throws -> CityWeather {
        let urlString = """
        https://api.open-meteo.com/v1/forecast?\
        latitude=\(city.latitude)&longitude=\(city.longitude)&\
        current=temperature_2m,apparent_temperature,is_day,weather_code,\
        relative_humidity_2m,dew_point_2m,wind_speed_10m,wind_gusts_10m,visibility&\
        hourly=temperature_2m,weather_code&\
        daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,\
        uv_index_max,precipitation_probability_max,precipitation_sum,\
        precipitation_hours,daylight_duration&\
        timezone=auto&temperature_unit=celsius&past_days=1
        """.replacingOccurrences(of: "\n", with: "")
        guard let url = URL(string: urlString) else {
            throw WeatherError.invalidURL
        }

        let data = try await get(url)
        do {
            let result = try JSONDecoder().decode(WeatherResponse.self, from: data)
            return CityWeather(city: city, response: result)
        } catch {
            throw WeatherError.decodingError
        }
    }

    /// Performs the request and maps transport/HTTP failures onto `WeatherError`.
    /// A non-2xx response carries a JSON error body that would otherwise surface
    /// as a misleading "failed to parse" message.
    private func get(_ url: URL) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                throw WeatherError.serverError(statusCode: http.statusCode)
            }

            return data
        } catch let error as WeatherError {
            throw error
        } catch let error as URLError {
            // Log the raw code: the user-facing message is deliberately plain,
            // but the code is what actually identifies the fault.
            Log.weather.error("URLError \(error.code.rawValue) for \(url.host() ?? "?", privacy: .public): \(error.localizedDescription)")

            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost,
                 .dataNotAllowed, .internationalRoamingOff:
                throw WeatherError.offline
            case .timedOut:
                throw WeatherError.timedOut
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                 .resourceUnavailable, .notConnectedToInternet:
                throw WeatherError.unreachable
            case .secureConnectionFailed, .serverCertificateUntrusted,
                 .serverCertificateHasBadDate, .serverCertificateNotYetValid,
                 .appTransportSecurityRequiresSecureConnection:
                throw WeatherError.insecureConnection
            default:
                throw WeatherError.networkError(error)
            }
        } catch {
            throw WeatherError.networkError(error)
        }
    }
}
