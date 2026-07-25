# Hourly Weather Forecast Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the 7-day forecast view and integrate an interactive, horizontal hourly weather forecast bar inside the main weather card.

**Architecture:** Fetch 24 hours of hourly weather data from Open-Meteo, parse into a structured timeline showing current and next-day hours divided by a vertical line, and embed it as a card footer.

**Tech Stack:** SwiftUI, Foundation, Combine, Open-Meteo API.

## Global Constraints
- Target platform: iOS/macOS (compatible with SwiftUI)
- Enforce Celsius metric temperature units
- No placeholders or empty blocks allowed

---

### Task 1: Update Weather Models

**Files:**
- Modify: `climyte/WeatherModel.swift`

**Interfaces:**
- Consumes: Open-Meteo Forecast response JSON
- Produces: `HourlyForecast` model, updated `CityWeather` properties

- [ ] **Step 1: Define HourlyForecast and update Response models**

Edit [WeatherModel.swift](file:///Users/gauthamravikumar/Documents/My%20Projects/climyte/climyte/WeatherModel.swift) to add the `HourlyForecast` struct and update `DailyWeatherResponse` and `WeatherResponse` to include the `hourly` properties.

```swift
struct HourlyForecast: Identifiable {
    let id = UUID()
    let time: String // e.g. "11 pm"
    let isTomorrow: Bool
    let condition: WeatherCondition
    let temperature: Double
}

struct HourlyWeatherResponse: Decodable {
    let time: [String]
    let temperature_2m: [Double]
    let weather_code: [Int]
}
```

Update `WeatherResponse`:
```swift
struct WeatherResponse: Decodable {
    let latitude: Double
    let longitude: Double
    let current: CurrentWeatherResponse
    let daily: DailyWeatherResponse
    let hourly: HourlyWeatherResponse
}
```

- [ ] **Step 2: Update CityWeather initialization**

Modify `CityWeather` struct to include:
`let hourlyForecasts: [HourlyForecast]`

Inside `CityWeather.init(city:response:)`, parse the `hourly` response data to extract the next 24 hours starting from the current hour. Compare the hour timestamps to determine the `isTomorrow` flag and format the output time (e.g., `"11 pm"`):

```swift
        // Parse hourly forecast for next 24 hours
        var hourlyList: [HourlyForecast] = []
        let currentEpoch = Date().timeIntervalSince1970
        
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        
        let hourFormatter = DateFormatter()
        hourFormatter.dateFormat = "h a"
        
        let hourCount = response.hourly.time.count
        var parsedHours = 0
        
        for i in 0..<hourCount {
            guard parsedHours < 24 else { break }
            let timeString = response.hourly.time[i]
            
            if let date = isoFormatter.date(from: timeString) {
                // Keep only current and future hours (within a 24h window)
                // Subtract 3600s (1h) so the user gets context of the current ongoing hour
                if date.timeIntervalSince1970 >= currentEpoch - 3600 {
                    let formattedHour = hourFormatter.string(from: date).lowercased()
                    let isTomorrowHour = !Calendar.current.isDateInToday(date)
                    
                    let forecast = HourlyForecast(
                        time: formattedHour,
                        isTomorrow: isTomorrowHour,
                        condition: WeatherCondition.from(wmoCode: response.hourly.weather_code[i]),
                        temperature: response.hourly.temperature_2m[i]
                    )
                    hourlyList.append(forecast)
                    parsedHours += 1
                }
            }
        }
        self.hourlyForecasts = hourlyList
```

- [ ] **Step 3: Verify model compilation**

Run: `swiftc -module-cache-path ./module-cache climyte/WeatherModel.swift climyte/WeatherService.swift climyte/WeatherViewModel.swift -o /dev/null`
Expected: Passes with no errors (except unused variable/argument issues in ContentView which hasn't been updated yet)

- [ ] **Step 4: Commit**

Run: `git commit -am "feat: add hourly weather models and parser"`

---

### Task 2: Update Weather Service API Call

**Files:**
- Modify: `climyte/WeatherService.swift`

**Interfaces:**
- Consumes: `City`
- Produces: Updated JSON forecast request containing `hourly` weather fields

- [ ] **Step 1: Update API forecast query parameters**

Modify the forecast endpoint in `fetchWeather(for:)` to request `hourly=temperature_2m,weather_code`.

```swift
    func fetchWeather(for city: City) async throws -> CityWeather {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(city.latitude)&longitude=\(city.longitude)&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,wind_speed_10m,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max,precipitation_probability_max&hourly=temperature_2m,weather_code&timezone=auto"
        guard let url = URL(string: urlString) else {
            throw WeatherError.invalidURL
        }
        // ...
```

- [ ] **Step 2: Verify service compiles**

Run: `swiftc -module-cache-path ./module-cache climyte/WeatherModel.swift climyte/WeatherService.swift climyte/WeatherViewModel.swift -o /dev/null`
Expected: PASS

- [ ] **Step 3: Commit**

Run: `git commit -am "feat: update weather api to fetch hourly forecast"`

---

### Task 3: Redesign ContentView Layout

**Files:**
- Modify: `climyte/ContentView.swift`

**Interfaces:**
- Consumes: `CityWeather` containing `hourlyForecasts` array
- Produces: Updated layout showing hourly weather inside `mainWeatherCard` and removing `forecastSection`

- [ ] **Step 1: Remove 7-day forecast code**

Remove the `forecastSection(_:)` call inside the main scroll view and delete the `private func forecastSection(_ weather: CityWeather)` view builder.

- [ ] **Step 2: Add hourly forecast UI builder**

Implement the `hourlyForecastSection(_:)` helper to build the horizontal scrolling weather timeline inside [ContentView.swift](file:///Users/gauthamravikumar/Documents/My%20Projects/climyte/climyte/ContentView.swift). It should filter hours into today vs tomorrow lists and split them with a vertical divider line as requested.

```swift
    // MARK: - Hourly Forecast View
    private func hourlyForecastSection(_ weather: CityWeather) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hourly Forecast")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    let todayHours = weather.hourlyForecasts.filter { !$0.isTomorrow }
                    let tomorrowHours = weather.hourlyForecasts.filter { $0.isTomorrow }
                    
                    // Render Today's Hours
                    HStack(spacing: 16) {
                        ForEach(todayHours) { hour in
                            hourlyCell(hour)
                        }
                    }
                    
                    if !todayHours.isEmpty && !tomorrowHours.isEmpty {
                        // Visual Divider separating Today and Tomorrow
                        HStack(spacing: 16) {
                            Spacer().frame(width: 8)
                            
                            VStack(spacing: 4) {
                                Text("Tomorrow")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.7))
                                
                                Rectangle()
                                    .fill(Color.white.opacity(0.3))
                                    .frame(width: 1, height: 45)
                            }
                            
                            Spacer().frame(width: 8)
                        }
                    }
                    
                    // Render Tomorrow's Hours
                    HStack(spacing: 16) {
                        ForEach(tomorrowHours) { hour in
                            hourlyCell(hour)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    private func hourlyCell(_ hour: HourlyForecast) -> some View {
        VStack(spacing: 8) {
            Text(hour.time)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            
            Image(systemName: hour.condition.iconName)
                .font(.system(size: 20))
                .symbolRenderingMode(.multicolor)
            
            Text(String(format: "%.0f°", hour.temperature))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 50)
    }
```

- [ ] **Step 3: Update mainWeatherCard to append the hourly section**

Insert a divider line and the `hourlyForecastSection` at the bottom of the `mainWeatherCard` VStack:

```swift
            // Current details (Temp, feels like, desc)
            VStack(spacing: 4) {
                Text(String(format: "%.0f°", weather.temperature))
                    .font(.system(size: 76, weight: .thin, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(radius: 2)
                
                Text(weather.condition.description)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(String(format: "Feels like %.0f°", weather.feelsLike))
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
            
            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
            
            // Hourly Footer
            hourlyForecastSection(weather)
                .padding(.horizontal, 16)
```

- [ ] **Step 4: Verify complete project compilation**

Run: `swiftc -module-cache-path ./module-cache climyte/WeatherModel.swift climyte/WeatherService.swift climyte/WeatherViewModel.swift climyte/ContentView.swift climyte/climyteApp.swift -o /dev/null`
Expected: PASS with no errors or warnings.

- [ ] **Step 5: Clean up cache and Commit**

Run: `rm -rf ./module-cache && git commit -am "feat: integrate hourly weather forecast footer into ContentView"`
