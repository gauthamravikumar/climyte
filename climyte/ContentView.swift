//
//  ContentView.swift
//  climyte
//
//  Created by Antigravity on 23/7/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WeatherViewModel()
    @State private var isSearching = false
    
    var body: some View {
        ZStack {
            // Dynamic Background Gradient
            LinearGradient(
                colors: viewModel.selectedWeather?.condition.backgroundColors ?? [Color(hex: "2980B9"), Color(hex: "6DD5FA")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.8), value: viewModel.selectedWeather?.condition)
            
            // Subtly colored ambient light blobs for premium visual depth
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
                VStack(spacing: 24) {
                    // Header / Search Bar
                    searchBarView
                    
                    if isSearching && !viewModel.searchQuery.isEmpty {
                        searchResultsView
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        // Horizontal Favorites List
                        favoritesSection
                        
                        if viewModel.isLoading && viewModel.favoriteWeatherList.isEmpty {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                                .padding(.top, 40)
                        } else if let selectedWeather = viewModel.selectedWeather {
                            // Main Weather View
                            mainWeatherCard(selectedWeather)
                                .transition(.scale.combined(with: .opacity))
                            
                            // Metrics Grid
                            metricsGrid(selectedWeather)
                            
                            // Sunrise & Sunset Cycle
                            sunCycleSection(selectedWeather)
                        } else {
                            noCitiesView
                        }
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 20)
            }
        }
        .task {
            await viewModel.fetchWeatherForFavorites()
        }
    }
    
    // MARK: - Search Bar View
    private var searchBarView: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.6))
                
                TextField("Search for a city...", text: $viewModel.searchQuery, onEditingChanged: { editing in
                    withAnimation {
                        isSearching = editing
                    }
                })
                .foregroundColor(.white)
                .accentColor(.white)
                
                if !viewModel.searchQuery.isEmpty {
                    Button(action: {
                        viewModel.searchQuery = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.15))
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            
            if isSearching {
                Button("Cancel") {
                    withAnimation {
                        viewModel.searchQuery = ""
                        isSearching = false
                        hideKeyboard()
                    }
                }
                .foregroundColor(.white)
                .padding(.leading, 8)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Search Results
    private var searchResultsView: some View {
        VStack(spacing: 0) {
            if viewModel.searchResults.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "cloud.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.4))
                    Text("No cities found")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.6))
                    Text("Try typing another city name.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.searchResults) { result in
                            Button(action: {
                                withAnimation {
                                    Task {
                                        await viewModel.addCityToFavorites(result)
                                    }
                                    isSearching = false
                                    hideKeyboard()
                                }
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(result.name)
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        
                                        Text([result.admin1, result.country].compactMap { $0 }.joined(separator: ", "))
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .padding()
                                .background(Color.white.opacity(0.05))
                            }
                            Divider()
                                .background(Color.white.opacity(0.1))
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
        }
        .background(Color.white.opacity(0.1))
        .background(.ultraThinMaterial)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 15)
        .padding(.horizontal, 4)
    }
    
    // MARK: - Favorites Horizontal Carousel
    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Saved Cities")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
            .padding(.horizontal, 8)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(viewModel.favoriteWeatherList) { weather in
                        let isSelected = viewModel.selectedWeather?.city.id == weather.city.id
                        
                        ZStack(alignment: .topTrailing) {
                            // Card view
                            Button(action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    viewModel.selectCityWeather(weather)
                                }
                            }) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(weather.city.name)
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    
                                    HStack {
                                        Image(systemName: weather.condition.iconName)
                                            .font(.title2)
                                            .symbolRenderingMode(.multicolor)
                                        
                                        Spacer()
                                        
                                        Text(String(format: "%.0f°", weather.temperature))
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                    }
                                }
                                .padding()
                                .frame(width: 140, height: 95)
                                .background(isSelected ? Color.white.opacity(0.25) : Color.white.opacity(0.1))
                                .background(.ultraThinMaterial)
                                .cornerRadius(20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(isSelected ? Color.white : Color.white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                                )
                                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
                            }
                            
                            // Delete button (visible when we have more than 1 favorite, to prevent empty state crashes)
                            if viewModel.favoriteWeatherList.count > 1 {
                                Button(action: {
                                    withAnimation {
                                        viewModel.removeCityFromFavorites(weather)
                                    }
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red.opacity(0.8))
                                        .background(Circle().fill(.white))
                                        .font(.body)
                                }
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
        }
    }
    
    // MARK: - Main Weather Card
    private func mainWeatherCard(_ weather: CityWeather) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
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
            
            Image(systemName: weather.condition.iconName)
                .font(.system(size: 90))
                .symbolRenderingMode(.multicolor)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 10)
                .padding(.vertical, 8)
            
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
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.12))
        .background(.ultraThinMaterial)
        .cornerRadius(30)
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 15, x: 0, y: 12)
    }
    
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
    
    // MARK: - Metrics Grid
    private func metricsGrid(_ weather: CityWeather) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            metricItem(title: "HUMIDITY", value: String(format: "%.0f%%", weather.humidity), icon: "humidity.fill")
            metricItem(title: "WIND SPEED", value: String(format: "%.1f km/h", weather.windSpeed), icon: "wind")
            metricItem(title: "UV INDEX", value: String(format: "%.1f", weather.uvIndex), icon: "sun.max.fill")
            metricItem(title: "RAIN CHANCE", value: "\(weather.precipitationChance)%", icon: "cloud.drizzle.fill")
        }
    }
    
    // MARK: - Sunrise & Sunset Card
    private func sunCycleSection(_ weather: CityWeather) -> some View {
        HStack(spacing: 24) {
            HStack(spacing: 12) {
                Image(systemName: "sunrise.fill")
                    .font(.title)
                    .foregroundColor(.yellow)
                VStack(alignment: .leading, spacing: 4) {
                    Text("SUNRISE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.5))
                    Text(weather.sunrise)
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            Spacer()
            
            Divider()
                .background(Color.white.opacity(0.2))
                .frame(height: 40)
            
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: "sunset.fill")
                    .font(.title)
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("SUNSET")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.5))
                    Text(weather.sunset)
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .background(.ultraThinMaterial)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
    
    private func metricItem(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.5))
                
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            Spacer()
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
    

    
    // MARK: - Empty State View
    private var noCitiesView: some View {
        VStack(spacing: 20) {
            Image(systemName: "cloud.sun.rain.fill")
                .font(.system(size: 70))
                .symbolRenderingMode(.multicolor)
            
            Text("No weather data available")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Try searching for a city above to get started.")
                .font(.body)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 80)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.1))
        .background(.ultraThinMaterial)
        .cornerRadius(30)
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Keyboard Dismissal Helper
#if canImport(UIKit)
import UIKit
#endif

extension View {
    func hideKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
