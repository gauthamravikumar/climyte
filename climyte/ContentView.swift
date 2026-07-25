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
    
    private var currentTheme: WeatherTheme {
        viewModel.activeWeather?.theme ?? WeatherTheme.forIsNight(false)
    }
    
    var body: some View {
        ZStack {
            // Fullscreen theme-driven background
            currentTheme.background
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: currentTheme.background)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    // Header Search Bar
                    searchBarView
                    
                    if isSearching && !viewModel.searchQuery.isEmpty {
                        searchResultsView
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        if viewModel.isLoading && viewModel.activeWeather == nil {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                .scaleEffect(1.5)
                                .padding(.top, 80)
                        } else if let activeWeather = viewModel.activeWeather {
                            // Minimal Weather Layout
                            mainWeatherLayout(activeWeather)
                                .transition(.opacity)
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
            await viewModel.loadWeatherOnLaunch()
        }
    }
    
    // MARK: - Search Bar View
    private var searchBarView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(currentTheme.secondaryText)
                    .font(.system(size: 16))
                
                TextField("Search city", text: $viewModel.searchQuery, onEditingChanged: { editing in
                    withAnimation {
                        isSearching = editing
                    }
                })
                .font(.custom("ManropeExtraLight-Medium", size: 16))
                .foregroundColor(currentTheme.primaryText)
                .accentColor(currentTheme.primaryText)
                
                if !viewModel.searchQuery.isEmpty {
                    Button(action: {
                        viewModel.searchQuery = ""
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(currentTheme.secondaryText)
                            .font(.system(size: 16, weight: .medium))
                    }
                }
                
                if isSearching {
                    Button("Cancel") {
                        withAnimation {
                            viewModel.searchQuery = ""
                            isSearching = false
                            hideKeyboard()
                        }
                    }
                    .font(.custom("ManropeExtraLight-SemiBold", size: 15))
                    .foregroundColor(currentTheme.primaryText)
                    .padding(.leading, 4)
                }
            }
            
            Rectangle()
                .fill(currentTheme.dividerColor)
                .frame(height: 1)
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Search Results
    private var searchResultsView: some View {
        VStack(spacing: 0) {
            if viewModel.searchResults.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 24))
                        .foregroundColor(currentTheme.secondaryText)
                    Text("No matches")
                        .font(.custom("ManropeExtraLight-SemiBold", size: 16))
                        .foregroundColor(currentTheme.secondaryText)
                }
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.searchResults) { result in
                            Button(action: {
                                withAnimation {
                                    viewModel.selectCity(result)
                                    isSearching = false
                                    hideKeyboard()
                                }
                            }) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(result.name)
                                        .font(.custom("ManropeExtraLight-Bold", size: 18))
                                        .foregroundColor(currentTheme.primaryText)
                                    
                                    Spacer()
                                    
                                    Text([result.admin1, result.country].compactMap { $0 }.joined(separator: ", "))
                                        .font(.custom("ManropeExtraLight-Medium", size: 15))
                                        .foregroundColor(currentTheme.secondaryText)
                                }
                                .padding(.vertical, 18)
                                .contentShape(Rectangle())
                            }
                            
                            Divider()
                                .background(currentTheme.dividerColor)
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Main Weather Layout
    private func mainWeatherLayout(_ weather: CityWeather) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // City metadata + Local Time
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if viewModel.isUsingCurrentLocation {
                            Image(systemName: "location.fill")
                                .font(.system(size: 14))
                                .foregroundColor(currentTheme.primaryText.opacity(0.8))
                        }
                        Text(weather.city.name)
                            .font(.custom("ManropeExtraLight-Bold", size: 28))
                            .foregroundColor(currentTheme.primaryText)
                    }
                }
                
                Spacer()
                
                Text(getCityLocalTime(utcOffsetSeconds: weather.utcOffsetSeconds))
                    .font(.custom("ManropeExtraLight-Medium", size: 18))
                    .foregroundColor(currentTheme.secondaryText)
            }
            
            
            // Major Temp
            Text(String(format: "%.0f°", weather.temperature))
                .font(.custom("ManropeExtraLight-Regular", size: 100))
                .foregroundColor(currentTheme.primaryText)
                .padding(.vertical, -10)
            
            // Condition description
            Text("\(weather.condition.description) · feels like \(String(format: "%.0f°", weather.feelsLike))")
                .font(.custom("ManropeExtraLight-Medium", size: 16))
                .foregroundColor(currentTheme.secondaryText)
            
            Divider()
                .background(currentTheme.dividerColor)
                .padding(.vertical, 8)
            
            // Hourly Forecast
            hourlyForecastSection(weather)
        }
        .padding(.vertical, 10)
    }
    
    // MARK: - Hourly Forecast View
    private func hourlyForecastSection(_ weather: CityWeather) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                let todayHours = weather.hourlyForecasts.filter { !$0.isTomorrow }
                let tomorrowHours = weather.hourlyForecasts.filter { $0.isTomorrow }
                
                // Render Today's Hours
                HStack(spacing: 20) {
                    ForEach(todayHours) { hour in
                        hourlyCell(hour)
                    }
                }
                
                if !todayHours.isEmpty && !tomorrowHours.isEmpty {
                    // Minimal separator for Tomorrow
                    HStack(spacing: 20) {
                        Spacer().frame(width: 4)
                        
                        VStack(spacing: 4) {
                            Text("Tomorrow")
                                .font(.custom("ManropeExtraLight-Bold", size: 10))
                                .foregroundColor(currentTheme.secondaryText.opacity(0.7))
                            
                            Rectangle()
                                .fill(currentTheme.dividerColor)
                                .frame(width: 1, height: 35)
                        }
                        
                        Spacer().frame(width: 4)
                    }
                }
                
                // Render Tomorrow's Hours
                HStack(spacing: 20) {
                    ForEach(tomorrowHours) { hour in
                        hourlyCell(hour)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    private func hourlyCell(_ hour: HourlyForecast) -> some View {
        VStack(spacing: 8) {
            Text(hour.time)
                .font(.custom("ManropeExtraLight-Medium", size: 13))
                .foregroundColor(currentTheme.secondaryText)
            
            Text(String(format: "%.0f°", hour.temperature))
                .font(.custom("ManropeExtraLight-Bold", size: 15))
                .foregroundColor(currentTheme.primaryText)
        }
        .frame(width: 50)
    }
    
    // MARK: - Helper Local Time Method
    private func getCityLocalTime(utcOffsetSeconds: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        formatter.timeZone = TimeZone(secondsFromGMT: utcOffsetSeconds) ?? TimeZone.current
        return formatter.string(from: Date())
    }
    
    // MARK: - Empty State View
    private var noWeatherDataView: some View {
        VStack(spacing: 20) {
            Image(systemName: "cloud.sun.rain.fill")
                .font(.system(size: 60))
                .symbolRenderingMode(.multicolor)
            
            Text("No weather data available")
                .font(.custom("ManropeExtraLight-Bold", size: 20))
                .foregroundColor(currentTheme.primaryText)
            
            Text("Try searching for a city above to get started.")
                .font(.custom("ManropeExtraLight-Regular", size: 16))
                .foregroundColor(currentTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 80)
        .frame(maxWidth: .infinity)
        .background(currentTheme.primaryText.opacity(0.02))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(currentTheme.dividerColor, lineWidth: 1)
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
