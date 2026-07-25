import Foundation

// Simple test assertions
func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #file, line: Int = #line) {
    if actual != expected {
        print("❌ Test failed [\(file):\(line)]: expected \(expected), got \(actual). \(message)")
        exit(1)
    }
}

func assertTrue(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
    if !condition {
        print("❌ Test failed [\(file):\(line)]: expected true condition. \(message)")
        exit(1)
    }
}

@main
struct TestRunner {
    static func main() {
        print("Starting WeatherModel tests...")
        testWeatherResponseDecoding()
        testCityWeatherHourlyForecastParsing()
        testMismatchedHourlyArrayLengths()
        print("✅ All WeatherModel tests passed!")
    }
    
    static func testWeatherResponseDecoding() {
        let jsonString = """
        {
            "latitude": -33.8688,
            "longitude": 151.2093,
            "utc_offset_seconds": 36000,
            "current": {
                "temperature_2m": 22.5,
                "apparent_temperature": 21.0,
                "is_day": 1,
                "weather_code": 0,
                "relative_humidity_2m": 60.0,
                "wind_speed_10m": 12.0
            },
            "hourly": {
                "time": ["2026-07-25T10:00", "2026-07-25T11:00", "2026-07-25T12:00"],
                "temperature_2m": [20.0, 21.5, 23.0],
                "weather_code": [0, 2, 61]
            },
            "daily": {
                "time": ["2026-07-25"],
                "weather_code": [0],
                "temperature_2m_max": [25.0],
                "temperature_2m_min": [15.0],
                "uv_index_max": [2.0],
                "sunrise": ["2026-07-25T06:00"],
                "sunset": ["2026-07-25T18:00"]
            }
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        do {
            let response = try JSONDecoder().decode(WeatherResponse.self, from: data)
            assertEqual(response.hourly.time.count, 3, "Hourly time array length should be 3")
            assertEqual(response.hourly.temperature_2m, [20.0, 21.5, 23.0], "Hourly temperatures should match JSON")
            assertEqual(response.hourly.weather_code, [0, 2, 61], "Hourly weather codes should match JSON")
            print("  ✓ testWeatherResponseDecoding passed")
        } catch {
            print("❌ Failed to decode WeatherResponse: \(error)")
            exit(1)
        }
    }
    
    static func testCityWeatherHourlyForecastParsing() {
        let city = City(id: UUID(), name: "Sydney", country: "Australia", latitude: -33.8688, longitude: 151.2093)
        
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        
        // Generate hourly data spanning current date and tomorrow
        let now = Date()
        let calendar = Calendar.current
        
        var times: [String] = []
        var temps: [Double] = []
        var codes: [Int] = []
        
        // Generate timestamps around now (-2h to +25h)
        for hourOffset in -2...25 {
            if let date = calendar.date(byAdding: .hour, value: hourOffset, to: now) {
                times.append(isoFormatter.string(from: date))
                temps.append(20.0 + Double(hourOffset))
                codes.append(hourOffset % 2 == 0 ? 0 : 61)
            }
        }
        
        let response = WeatherResponse(
            latitude: -33.8688,
            longitude: 151.2093,
            utc_offset_seconds: 36000,
            current: CurrentWeatherResponse(
                temperature_2m: 22.5,
                apparent_temperature: 21.0,
                is_day: 1,
                weather_code: 0,
                relative_humidity_2m: 60.0,
                wind_speed_10m: 12.0
            ),
            hourly: HourlyWeatherResponse(
                time: times,
                temperature_2m: temps,
                weather_code: codes
            ),
            daily: DailyWeatherResponse(
                time: ["2026-07-25"],
                weather_code: [0],
                temperature_2m_max: [25.0],
                temperature_2m_min: [15.0],
                sunrise: ["2026-07-25T06:00"],
                sunset: ["2026-07-25T18:00"],
                uv_index_max: [2.0]
            )
        )
        
        let cityWeather = CityWeather(city: city, response: response)
        
        assertTrue(cityWeather.hourlyForecasts.count <= 24, "Should parse at most 24 hourly forecasts")
        assertTrue(!cityWeather.hourlyForecasts.isEmpty, "Should have hourly forecasts")
        
        // Verify time string formatting (e.g. ends with "am" or "pm")
        let firstForecast = cityWeather.hourlyForecasts[0]
        assertTrue(firstForecast.time.hasSuffix("am") || firstForecast.time.hasSuffix("pm"), "Formatted hour should end with am/pm")
        
        print("  ✓ testCityWeatherHourlyForecastParsing passed (\(cityWeather.hourlyForecasts.count) hours parsed)")
    }
    
    static func testMismatchedHourlyArrayLengths() {
        let city = City(id: UUID(), name: "Sydney", country: "Australia", latitude: -33.8688, longitude: 151.2093)
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        
        let now = Date()
        let calendar = Calendar.current
        var times: [String] = []
        for hourOffset in 0..<10 {
            if let date = calendar.date(byAdding: .hour, value: hourOffset, to: now) {
                times.append(isoFormatter.string(from: date))
            }
        }
        
        // Mismatched array lengths: 10 times, 5 temperatures, 7 weather codes
        let response = WeatherResponse(
            latitude: -33.8688,
            longitude: 151.2093,
            utc_offset_seconds: 36000,
            current: CurrentWeatherResponse(
                temperature_2m: 22.5,
                apparent_temperature: 21.0,
                is_day: 1,
                weather_code: 0,
                relative_humidity_2m: 60.0,
                wind_speed_10m: 12.0
            ),
            hourly: HourlyWeatherResponse(
                time: times, // length 10
                temperature_2m: [20.0, 21.0, 22.0, 23.0, 24.0], // length 5
                weather_code: [0, 1, 2, 3, 45, 51, 61] // length 7
            ),
            daily: DailyWeatherResponse(
                time: ["2026-07-25"],
                weather_code: [0],
                temperature_2m_max: [25.0],
                temperature_2m_min: [15.0],
                sunrise: ["2026-07-25T06:00"],
                sunset: ["2026-07-25T18:00"],
                uv_index_max: [2.0]
            )
        )
        
        let cityWeather = CityWeather(city: city, response: response)
        assertEqual(cityWeather.hourlyForecasts.count, 5, "Hourly forecast count should be capped by min array length (5)")
        print("  ✓ testMismatchedHourlyArrayLengths passed without crashing")
    }
}

