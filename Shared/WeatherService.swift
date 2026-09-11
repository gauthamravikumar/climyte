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

    /// The instance the widget extension fetches with.
    ///
    /// A shorter leash than the app's: an extension that sits waiting on a
    /// slow network is killed rather than allowed to finish, and a widget with
    /// no answer should fall back to the cache quickly instead. Ephemeral
    /// because there is nothing worth persisting between two runs that may be
    /// hours apart.
    static let widget: WeatherService = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return WeatherService(session: URLSession(configuration: config))
    }()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

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
                return String(localized: "The API URL was invalid.")
            case .serverError(let statusCode):
                return String(localized: "The weather service returned an error (HTTP \(String(statusCode))).")
            case .decodingError:
                return String(localized: "Failed to parse the weather data response.")
            case .offline:
                return String(localized: "No internet connection.")
            case .timedOut:
                return String(localized: "The request timed out.")
            case .unreachable:
                return String(localized: "Could not reach the weather service.")
            case .insecureConnection:
                return String(localized: "The secure connection failed.")
            case .networkError(let error):
                return String(localized: "Network error: \(error.localizedDescription)")
            }
        }
    }

    func searchCities(query: String) async throws -> [GeocodingResult] {
        // URLComponents rather than interpolation: `.urlQueryAllowed` leaves
        // `&` and `=` unescaped, so a city name containing either used to add
        // parameters of its own to the request.
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]

        guard let url = components?.url else {
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
        // A city decoded from a corrupted store can carry NaN, infinity, or
        // coordinates off the globe. Interpolated into the URL those become a
        // request the server answers with a 400, which reaches the reader as
        // "the weather service is unavailable" — blaming Open-Meteo for a
        // question we should never have asked.
        guard city.latitude.isFinite, city.longitude.isFinite,
              (-90...90).contains(city.latitude),
              (-180...180).contains(city.longitude) else {
            Log.weather.error("Refusing to fetch for out-of-range coordinates")
            throw WeatherError.invalidURL
        }

        let urlString = """
        https://api.open-meteo.com/v1/forecast?\
        latitude=\(city.latitude)&longitude=\(city.longitude)&\
        current=temperature_2m,apparent_temperature,is_day,weather_code,\
        relative_humidity_2m,dew_point_2m,wind_speed_10m,wind_gusts_10m,visibility&\
        hourly=temperature_2m,weather_code,precipitation,precipitation_probability&\
        minutely_15=precipitation&forecast_minutely_15=8&\
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
            let (data, response) = try await session.data(from: url)

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
                 .resourceUnavailable:
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
