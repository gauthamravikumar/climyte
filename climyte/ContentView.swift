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
                        .font(.custom("ManropeExtraLight-SemiBold", size: 17))
                        .foregroundColor(.white.opacity(0.6))
                    Text("Try typing another city name.")
                        .font(.custom("ManropeExtraLight-Regular", size: 15))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.searchResults) { result in
                            Button(action: {
                                withAnimation {
                                    viewModel.selectCity(result)
                                    isSearching = false
                                    hideKeyboard()
                                }
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(result.name)
                                            .font(.custom("ManropeExtraLight-SemiBold", size: 17))
                                            .foregroundColor(.white)
                                        
                                        Text([result.admin1, result.country].compactMap { $0 }.joined(separator: ", "))
                                            .font(.custom("ManropeExtraLight-Regular", size: 15))
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                    Spacer()
                                    Image(systemName: "mappin.circle.fill")
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
    
    // MARK: - Main Weather Fullscreen Layout
    private func mainWeatherLayout(_ weather: CityWeather) -> some View {
        VStack(spacing: 32) {
            // City metadata
            VStack(spacing: 6) {
                Text(weather.city.name)
                    .font(.custom("ManropeExtraLight-Bold", size: 34))
                    .foregroundColor(.white)
                    .shadow(radius: 2)
                
                Text(weather.city.country)
                    .font(.custom("ManropeExtraLight-Medium", size: 15))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Condition details
            VStack(spacing: 4) {
                Text(String(format: "%.0f°", weather.temperature))
                    .font(.custom("ManropeExtraLight-Regular", size: 84))
                    .foregroundColor(.white)
                    .shadow(radius: 2)
                
                Text(weather.condition.description)
                    .font(.custom("ManropeExtraLight-SemiBold", size: 20))
                    .foregroundColor(.white)
                
                Text(String(format: "Feels like %.0f°", weather.feelsLike))
                    .font(.custom("ManropeExtraLight-Regular", size: 15))
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
    
    // MARK: - Hourly Forecast View
    private func hourlyForecastSection(_ weather: CityWeather) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hourly Forecast")
                .font(.custom("ManropeExtraLight-Bold", size: 12))
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
                                    .font(.custom("ManropeExtraLight-Bold", size: 10))
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
                .font(.custom("ManropeExtraLight-Medium", size: 12))
                .foregroundColor(.white.opacity(0.8))
            
            Image(systemName: hour.condition.iconName)
                .font(.system(size: 20))
                .symbolRenderingMode(.multicolor)
            
            Text(String(format: "%.0f°", hour.temperature))
                .font(.custom("ManropeExtraLight-Bold", size: 14))
                .foregroundColor(.white)
        }
        .frame(width: 50)
    }
    
    // MARK: - Empty State View
    private var noWeatherDataView: some View {
        VStack(spacing: 20) {
            Image(systemName: "cloud.sun.rain.fill")
                .font(.system(size: 70))
                .symbolRenderingMode(.multicolor)
            
            Text("No weather data available")
                .font(.custom("ManropeExtraLight-Bold", size: 22))
                .foregroundColor(.white)
            
            Text("Try searching for a city above to get started.")
                .font(.custom("ManropeExtraLight-Regular", size: 17))
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
