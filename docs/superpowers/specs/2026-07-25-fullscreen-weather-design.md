# Design Spec: Fullscreen Weather App with Single City & Hourly Timeline

This document outlines the design and architecture for refactoring Climyte into a clean, immersive fullscreen single-city weather application.

## 1. Design & UI Specifications
* **Fullscreen Gradient Background**: The dynamic ambient weather-themed gradient background will fill the entire screen, ignoring safe areas.
* **No Cards**: Remove all card borders, backgrounds, shadows, and paddings from the weather view. Text and icons will float directly on the ambient background.
* **No Saved Cities Carousel**: Remove the top carousel of saved favorites.
* **Single Active City**: The app displays weather for a single active city at a time.
* **Persistent Last City**: The selected city will be saved in `UserDefaults` so the app re-opens with the last searched city (defaulting to "Sydney" on first run).
* **Layout Hierarchy**:
  1. **Top**: Search Bar (glassmorphic input).
  2. **Middle**: Current Weather Details (City, Country, large Weather Symbol, large Temperature, Condition text, Feels-like temperature).
  3. **Bottom**: Hourly Forecast Timeline (horizontal scroll view with Today vs Tomorrow divider line).

---

## 2. Technical Architecture

### Data Models (`WeatherModel.swift`)
Simplify models to contain only the necessary properties:
* `City`: Holds latitude, longitude, name, country.
* `HourlyForecast`: Time, isTomorrow, condition, temperature.
* `CityWeather`: Holds `City`, temperature, feelsLike, condition, isDay, and `hourlyForecasts` array.
* Remove `DailyForecast` model.
* Remove daily-level metrics decoding structures: `DailyWeatherResponse`.
* Update `WeatherResponse`:
  ```swift
  struct WeatherResponse: Decodable {
      let latitude: Double
      let longitude: Double
      let utc_offset_seconds: Int
      let current: CurrentWeatherResponse
      let hourly: HourlyWeatherResponse
  }
  ```

### API Service (`WeatherService.swift`)
Query only the current and hourly weather data. Remove daily query parameters:
* Endpoint URL: `https://api.open-meteo.com/v1/forecast?latitude=\(city.latitude)&longitude=\(city.longitude)&current=temperature_2m,apparent_temperature,is_day,weather_code&hourly=temperature_2m,weather_code&timezone=auto&temperature_unit=celsius`

### View Model (`WeatherViewModel.swift`)
* Maintain a single `activeCity: City` property.
* Maintain a single `activeWeather: CityWeather?` property.
* Save `activeCity` to `UserDefaults` under key `active_city` on update; load it in `init()`.
* Manage `searchQuery` and `searchResults` for looking up and switching the active city.

### Views (`ContentView.swift`)
* Remove horizontal favorites section.
* Remove metrics grid and sunrise/sunset views.
* Render `mainWeather` details directly in the scrolling stack without card formatting.
* Render `hourlyForecastSection` directly in the scrolling stack.
