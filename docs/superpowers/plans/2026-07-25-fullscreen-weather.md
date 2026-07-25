# Fullscreen Weather App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor Climyte to show a clean, fullscreen weather layout for a single persistently tracked city (removing card borders, favorites list, daily forecast grid, and sunrise/sunset metrics).

**Architecture:** Simplify models, prune unnecessary fields from the Open-Meteo query URL, save/load the active city persistently in `UserDefaults`, and render float-style layouts directly on the animated dynamic gradient background.

**Tech Stack:** SwiftUI, Foundation, Combine, Open-Meteo API.

## Global Constraints
- Target platform: iOS/macOS (compatible with SwiftUI)
- Enforce Celsius temperature units
- No placeholders or empty blocks allowed

---

### Task 1: Clean Up Weather Models

**Files:**
- Modify: `climyte/WeatherModel.swift`

**Interfaces:**
- Consumes: Open-Meteo current and hourly forecast JSON
- Produces: Simplified `CityWeather` structure with timezone-specific local formatting

- [ ] **Step 1: Simplify CityWeather and decode structures**

Edit [WeatherModel.swift](file:///Users/gauthamravikumar/Documents/My%20Projects/climyte/climyte/WeatherModel.swift) to:
* Remove `DailyForecast` model.
* Remove `DailyWeatherResponse` decoding struct.
* Simplify `CityWeather` to hold only `id`, `city`, `temperature`, `feelsLike`, `condition`, `isDay`, and `hourlyForecasts`.
* Update `WeatherResponse` to only decode `current` and `hourly`:

```swift
struct WeatherResponse: Decodable {
    let latitude: Double
    let longitude: Double
    let utc_offset_seconds: Int
    let current: CurrentWeatherResponse
    let hourly: HourlyWeatherResponse
}
```

- [ ] **Step 2: Update CityWeather initializer**

Inside `CityWeather.init`, parse the response and assign the values. Retain the timezone-aware formatters and calendar (as written in the previous fixes wave):

```swift
struct CityWeather: Identifiable {
    let id: UUID
    let city: City
    let temperature: Double
    let feelsLike: Double
    let condition: WeatherCondition
    let isDay: Bool
    let hourlyForecasts: [HourlyForecast]
    
    init(city: City, response: WeatherResponse) {
        self.id = UUID()
        self.city = city
        self.temperature = response.current.temperature_2m
        self.feelsLike = response.current.apparent_temperature
        self.condition = WeatherCondition.from(wmoCode: response.current.weather_code)
        self.isDay = response.current.is_day == 1
        
        let cityTimeZone = TimeZone(secondsFromGMT: response.utc_offset_seconds) ?? TimeZone.current
        var cityCalendar = Calendar.current
        cityCalendar.timeZone = cityTimeZone
        
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        isoFormatter.timeZone = cityTimeZone
        
        let hourFormatter = DateFormatter()
        hourFormatter.dateFormat = "h a"
        hourFormatter.timeZone = cityTimeZone
        
        var hourlyList: [HourlyForecast] = []
        let currentEpoch = Date().timeIntervalSince1970
        let hourCount = min(response.hourly.time.count, response.hourly.temperature_2m.count, response.hourly.weather_code.count)
        var parsedHours = 0
        
        for i in 0..<hourCount {
            guard parsedHours < 24 else { break }
            let timeString = response.hourly.time[i]
            
            if let date = isoFormatter.date(from: timeString) {
                if date.timeIntervalSince1970 >= currentEpoch - 3600 {
                    let formattedHour = hourFormatter.string(from: date).lowercased()
                    let isTomorrowHour = !cityCalendar.isDateInToday(date)
                    
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
    }
}
```

- [ ] **Step 3: Verify model compilation**

Run: `swiftc -module-cache-path ./module-cache climyte/WeatherModel.swift climyte/WeatherService.swift -o /dev/null`
Expected: Compile succeeds (except unused properties warnings/errors in view models/views)

- [ ] **Step 4: Commit**

Run: `git commit -am "feat: simplify weather models by removing daily forecasts"`

---

### Task 2: Simplify API Network Parameters

**Files:**
- Modify: `climyte/WeatherService.swift`

**Interfaces:**
- Consumes: `City`
- Produces: API request string matching current & hourly parameters only

- [ ] **Step 1: Prune forecast query URL**

Modify `fetchWeather(for:)` URL to remove `daily` metric parameters:

```swift
    func fetchWeather(for city: City) async throws -> CityWeather {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(city.latitude)&longitude=\(city.longitude)&current=temperature_2m,apparent_temperature,is_day,weather_code&hourly=temperature_2m,weather_code&timezone=auto&temperature_unit=celsius"
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
```

- [ ] **Step 2: Verify service compiles**

Run: `swiftc -module-cache-path ./module-cache climyte/WeatherModel.swift climyte/WeatherService.swift -o /dev/null`
Expected: PASS

- [ ] **Step 3: Commit**

Run: `git commit -am "feat: simplify forecast API request parameters"`

---

### Task 3: Refactor Weather View Model

**Files:**
- Modify: `climyte/WeatherViewModel.swift`

**Interfaces:**
- Consumes: User search selections
- Produces: Persistent single active city state

- [ ] **Step 1: Simplify properties and initialization**

Edit [WeatherViewModel.swift](file:///Users/gauthamravikumar/Documents/My%20Projects/climyte/climyte/WeatherViewModel.swift) to:
* Remove `favoriteWeatherList`.
* Add `activeWeather: CityWeather?`.
* Add `activeCity: City` with a `didSet` block that saves to `UserDefaults`.

```swift
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
    
    @Published var activeCity: City {
        didSet {
            saveActiveCity()
            Task {
                await fetchWeatherForActiveCity()
            }
        }
    }
    
    private let activeCityKey = "saved_active_city"
    private var searchTask: Task<Void, Never>?
    
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
        self.activeCity = newCity
        
        // Clear search
        searchQuery = ""
        searchResults = []
    }
    // ... keep performSearch() ...
}
```

- [ ] **Step 2: Verify View Model compiles**

Run: `swiftc -module-cache-path ./module-cache climyte/WeatherModel.swift climyte/WeatherService.swift climyte/WeatherViewModel.swift -o /dev/null`
Expected: PASS

- [ ] **Step 3: Commit**

Run: `git commit -am "feat: refactor view model to manage single active city"`

---

### Task 4: Refactor ContentView Layout

**Files:**
- Modify: `climyte/ContentView.swift`

**Interfaces:**
- Consumes: `WeatherViewModel` single active state
- Produces: Immersive fullscreen views directly floating on gradient background

- [ ] **Step 1: Update ContentView body**

Edit [ContentView.swift](file:///Users/gauthamravikumar/Documents/My%20Projects/climyte/climyte/ContentView.swift):
* Update the dynamic background gradient to animate based on `viewModel.activeWeather?.condition.backgroundColors`.
* Change `.task` to run `await viewModel.fetchWeatherForActiveCity()`.
* Remove horizontal favorites section and metrics grids.
* Render `mainWeatherCard` and `hourlyForecastSection` directly in the scrolling Stack.

```swift
struct ContentView: View {
    @StateObject private var viewModel = WeatherViewModel()
    @State private var isSearching = false
    
    var body: some View {
        ZStack {
            // Fullscreen Background Gradient
            LinearGradient(
                colors: viewModel.activeWeather?.condition.backgroundColors ?? [Color(hex: "2980B9"), Color(hex: "6DD5FA")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.8), value: viewModel.activeWeather?.condition)
            
            // Fullscreen ambient blobs
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: geo.size.width * 0.8, height: geo.size.width * 0.8)
                        .blur(radius: 60)
                        .offset(x: -geo.size.width * 0.2, y: geo.size.height * 0.1)
                    
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: geo.size.width * 0.6, height: geo.size.width * 0.6)
                        .blur(radius: 50)
                        .offset(x: geo.size.width * 0.4, y: geo.size.height * 0.5)
                }
            }
            .ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 36) {
                    // Header Search Bar
                    searchBarView
                    
                    if isSearching && !viewModel.searchQuery.isEmpty {
                        searchResultsView
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        if viewModel.isLoading && viewModel.activeWeather == nil {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                                .padding(.top, 80)
                        } else if let activeWeather = viewModel.activeWeather {
                            // Immersive Fullscreen Weather details
                            mainWeatherLayout(activeWeather)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            noWeatherDataView
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
        }
        .task {
            await viewModel.fetchWeatherForActiveCity()
        }
    }
```

- [ ] **Step 2: Update searchResultsView selection action**

Modify the selection action inside `searchResultsView` to call `viewModel.selectCity(result)` instead of the old favorite additions:

```swift
                            Button(action: {
                                withAnimation {
                                    viewModel.selectCity(result)
                                    isSearching = false
                                    hideKeyboard()
                                }
                            }) {
```

- [ ] **Step 3: Refactor mainWeatherCard to mainWeatherLayout**

Remove card borders, backgrounds, borders, and margins. Let everything float fullscreen. Position the hourly timeline as the footer of the layout:

```swift
    // MARK: - Main Weather Fullscreen Layout
    private func mainWeatherLayout(_ weather: CityWeather) -> some View {
        VStack(spacing: 32) {
            // City metadata
            VStack(spacing: 6) {
                Text(weather.city.name)
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .shadow(radius: 2)
                
                Text(weather.city.country)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Major Weather Symbol
            Image(systemName: weather.condition.iconName)
                .font(.system(size: 100))
                .symbolRenderingMode(.multicolor)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 10)
                .padding(.vertical, 8)
            
            // Condition details
            VStack(spacing: 4) {
                Text(String(format: "%.0f°", weather.temperature))
                    .font(.system(size: 84, weight: .thin, design: .rounded))
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
                .background(Color.white.opacity(0.25))
                .padding(.vertical, 8)
                .padding(.horizontal, 24)
            
            // Hourly Forecast Footer
            hourlyForecastSection(weather)
        }
        .padding(.vertical, 20)
    }
```

- [ ] **Step 4: Clean up unused code**

Delete all unused helper views: `metricItem`, `metricsGrid`, `sunCycleSection`, and the favorites scroll container. Clean up formatting lines.

- [ ] **Step 5: Verify project compilation**

Run: `swiftc -module-cache-path ./module-cache climyte/WeatherModel.swift climyte/WeatherService.swift climyte/WeatherViewModel.swift climyte/ContentView.swift climyte/climyteApp.swift -o /dev/null`
Expected: PASS

- [ ] **Step 6: Commit**

Run: `git commit -am "feat: refactor ContentView UI layout to support cardless fullscreen weather"`

---

### Task 5: Refactor Tests and Verify Build

**Files:**
- Modify: `climyteTests/WeatherModelTests.swift`

- [ ] **Step 1: Simplify WeatherModelTests payload**

Remove Sunrise, Sunset, UV Index, and Rain Chance fields from `WeatherResponse` test initializers to align with Task 1 model structure.

Inside `testWeatherResponseDecoding()`:
```swift
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
                "weather_code": 0
            },
            "hourly": {
                "time": ["2026-07-25T10:00", "2026-07-25T11:00", "2026-07-25T12:00"],
                "temperature_2m": [20.0, 21.5, 23.0],
                "weather_code": [0, 2, 61]
            }
        }
        """
        // ...
```

Inside `testCityWeatherHourlyForecastParsing()` and `testMismatchedHourlyArrayLengths()`, update the instantiations of `WeatherResponse`:
```swift
        let response = WeatherResponse(
            latitude: -33.8688,
            longitude: 151.2093,
            utc_offset_seconds: 36000,
            current: CurrentWeatherResponse(
                temperature_2m: 22.5,
                apparent_temperature: 21.0,
                is_day: 1,
                weather_code: 0
            ),
            hourly: HourlyWeatherResponse(
                time: times,
                temperature_2m: temps,
                weather_code: codes
            )
        )
```

- [ ] **Step 2: Run test suite**

Run: `swiftc -module-cache-path ./module-cache climyte/WeatherModel.swift climyteTests/WeatherModelTests.swift -o test_runner && ./test_runner && rm ./test_runner && rm -rf ./module-cache`
Expected: Passes with output:
```
Starting WeatherModel tests...
  ✓ testWeatherResponseDecoding passed
  ✓ testCityWeatherHourlyForecastParsing passed (24 hours parsed)
  ✓ testMismatchedHourlyArrayLengths passed without crashing
✅ All WeatherModel tests passed!
```

- [ ] **Step 3: Commit**

Run: `git commit -am "test: simplify unit tests for simplified weather responses"`
