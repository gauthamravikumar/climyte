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
            
            
            // Major Temp + H/L Details
            HStack(alignment: .center, spacing: 16) {
                Text(String(format: "%.0f°", weather.temperature))
                    .font(.custom("ManropeExtraLight-Regular", size: 100))
                    .foregroundColor(currentTheme.primaryText)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "H:%.0f°", weather.maxTemp))
                        .font(.custom("ManropeExtraLight-Medium", size: 14))
                        .foregroundColor(currentTheme.secondaryText)
                    
                    Text(String(format: "L:%.0f°", weather.minTemp))
                        .font(.custom("ManropeExtraLight-Medium", size: 14))
                        .foregroundColor(currentTheme.secondaryText)
                }
            }
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
            
            // 7-Day Forecast Section
            dailyForecastSection(weather)
            
            // Details Grid Section
            detailsSection(weather)
        }
        .padding(.vertical, 10)
    }
    
    // MARK: - Hourly Forecast View
    private func hourlyForecastSection(_ weather: CityWeather) -> some View {
        let hours = weather.hourlyForecasts
        let temperatures = hours.map { $0.temperature }
        let minTemp = temperatures.min() ?? 0
        let maxTemp = temperatures.max() ?? 1
        let tempRange = max(maxTemp - minTemp, 1)
        
        let columnWidth: CGFloat = 65
        let chartHeight: CGFloat = 45
        let chartPadding: CGFloat = 8
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("HOURLY")
                .font(.custom("ManropeExtraLight-Bold", size: 12))
                .foregroundColor(currentTheme.secondaryText)
                .padding(.horizontal, 4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 12) {
                    ZStack(alignment: .topLeading) {
                        Path { path in
                            for (index, hour) in hours.enumerated() {
                                let x = CGFloat(index) * columnWidth + (columnWidth / 2)
                                let y = yCoordinate(for: hour.temperature, minTemp: minTemp, tempRange: tempRange, chartHeight: chartHeight, chartPadding: chartPadding)
                                if index == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .stroke(currentTheme.secondaryText.opacity(0.3), lineWidth: 1.5)
                        
                        ForEach(0..<hours.count, id: \.self) { index in
                            let hour = hours[index]
                            let x = CGFloat(index) * columnWidth + (columnWidth / 2)
                            let y = yCoordinate(for: hour.temperature, minTemp: minTemp, tempRange: tempRange, chartHeight: chartHeight, chartPadding: chartPadding)
                            
                            Circle()
                                .fill(currentTheme.primaryText)
                                .frame(width: 5, height: 5)
                                .position(x: x, y: y)
                        }
                    }
                    .frame(width: CGFloat(hours.count) * columnWidth, height: chartHeight)
                    
                    HStack(spacing: 0) {
                        ForEach(hours) { hour in
                            VStack(spacing: 6) {
                                Text(String(format: "%.0f°", hour.temperature))
                                    .font(.custom("ManropeExtraLight-Bold", size: 14))
                                    .foregroundColor(currentTheme.primaryText)
                                
                                Text(hour.time)
                                    .font(.custom("ManropeExtraLight-Medium", size: 12))
                                    .foregroundColor(currentTheme.secondaryText)
                            }
                            .frame(width: columnWidth)
                        }
                    }
                }
            }
        }
    }
    
    private func yCoordinate(for temp: Double, minTemp: Double, tempRange: Double, chartHeight: CGFloat, chartPadding: CGFloat) -> CGFloat {
        let relativeValue = (temp - minTemp) / tempRange
        return chartHeight - chartPadding - CGFloat(relativeValue) * (chartHeight - 2 * chartPadding)
    }
    
    // MARK: - Daily Forecast View
    private func dailyForecastSection(_ weather: CityWeather) -> some View {
        let weekMin = weather.dailyForecasts.map { $0.minTemp }.min() ?? 0
        let weekMax = weather.dailyForecasts.map { $0.maxTemp }.max() ?? 100
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("THIS WEEK")
                .font(.custom("ManropeExtraLight-Bold", size: 12))
                .foregroundColor(currentTheme.secondaryText)
                .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                ForEach(weather.dailyForecasts) { forecast in
                    HStack {
                        Text(forecast.day)
                            .font(.custom("ManropeExtraLight-Bold", size: 16))
                            .foregroundColor(currentTheme.primaryText)
                            .frame(width: 60, alignment: .leading)
                        
                        Spacer()
                        
                        Text(String(format: "%.0f°", forecast.minTemp))
                            .font(.custom("ManropeExtraLight-Medium", size: 16))
                            .foregroundColor(currentTheme.secondaryText)
                            .frame(width: 30, alignment: .trailing)
                        
                        Spacer()
                        
                        TempBarView(
                            minTemp: forecast.minTemp,
                            maxTemp: forecast.maxTemp,
                            weekMin: weekMin,
                            weekMax: weekMax,
                            theme: currentTheme
                        )
                        .frame(width: 120)
                        
                        Spacer()
                        
                        Text(String(format: "%.0f°", forecast.maxTemp))
                            .font(.custom("ManropeExtraLight-Bold", size: 16))
                            .foregroundColor(currentTheme.primaryText)
                            .frame(width: 30, alignment: .trailing)
                    }
                    .padding(.vertical, 14)
                    
                    Divider()
                        .background(currentTheme.dividerColor)
                }
            }
        }
    }
    
    // MARK: - Details Grid
    private func detailsSection(_ weather: CityWeather) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DETAILS")
                .font(.custom("ManropeExtraLight-Bold", size: 12))
                .foregroundColor(currentTheme.secondaryText)
                .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                detailRow(label: "Sunrise", value: weather.sunriseFormatted)
                detailRow(label: "Sunset", value: weather.sunsetFormatted)
                detailRow(label: "Wind", value: String(format: "%.0f km/h", weather.windSpeed))
                detailRow(label: "Humidity", value: "\(weather.humidity)%")
                detailRow(label: "UV index", value: formatUVIndex(weather.uvIndex))
            }
        }
    }
    
    private func detailRow(label: String, value: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.custom("ManropeExtraLight-Medium", size: 15))
                    .foregroundColor(currentTheme.secondaryText)
                
                Spacer()
                
                Text(value)
                    .font(.custom("ManropeExtraLight-Bold", size: 15))
                    .foregroundColor(currentTheme.primaryText)
            }
            .padding(.vertical, 14)
            
            Divider()
                .background(currentTheme.dividerColor)
        }
    }
    
    private func formatUVIndex(_ val: Double) -> String {
        let category: String
        if val <= 2 { category = "Low" }
        else if val <= 5 { category = "Moderate" }
        else if val <= 7 { category = "High" }
        else if val <= 10 { category = "Very High" }
        else { category = "Extreme" }
        return "\(String(format: "%.0f", val)) · \(category)"
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

// MARK: - Custom Temperature range progress bar View
struct TempBarView: View {
    let minTemp: Double
    let maxTemp: Double
    let weekMin: Double
    let weekMax: Double
    let theme: WeatherTheme
    
    var body: some View {
        GeometryReader { geo in
            let range = max(weekMax - weekMin, 1)
            let left = CGFloat((minTemp - weekMin) / range) * geo.size.width
            let right = CGFloat((maxTemp - weekMin) / range) * geo.size.width
            let width = max(right - left, 3)
            
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.dividerColor)
                    .frame(height: 4)
                
                Capsule()
                    .fill(theme.primaryText)
                    .frame(width: width, height: 4)
                    .offset(x: left)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 4)
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
