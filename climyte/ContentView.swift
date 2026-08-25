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

    private var theme: WeatherTheme {
        viewModel.activeWeather?.theme ?? WeatherTheme.forIsNight(false)
    }

    var body: some View {
        ZStack {
            theme.background
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: theme.background)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    SearchBarView(
                        query: $viewModel.searchQuery,
                        isSearching: $isSearching,
                        theme: theme
                    )

                    content
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
            .refreshable {
                await viewModel.fetchWeatherForActiveCity()
            }
        }
        .task {
            await viewModel.loadWeatherOnLaunch()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isSearching && !viewModel.searchQuery.isEmpty {
            SearchResultsView(
                results: viewModel.searchResults,
                theme: theme,
                onSelect: { result in
                    withAnimation {
                        viewModel.selectCity(result)
                        isSearching = false
                    }
                }
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else if viewModel.isLoading && viewModel.activeWeather == nil {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: theme.primaryText))
                .scaleEffect(1.5)
                .padding(.top, 80)
        } else if let weather = viewModel.activeWeather {
            // A refresh can fail while stale data is still on screen.
            if let message = viewModel.errorMessage {
                StaleDataNotice(message: message, theme: theme)
            }

            weatherLayout(weather)
                .transition(.opacity)
        } else if let message = viewModel.errorMessage {
            WeatherErrorView(message: message, theme: theme) {
                Task { await viewModel.fetchWeatherForActiveCity() }
            }
        } else {
            NoWeatherDataView(theme: theme)
        }
    }

    private func weatherLayout(_ weather: CityWeather) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            CurrentConditionsView(
                weather: weather,
                theme: theme,
                isUsingCurrentLocation: viewModel.isUsingCurrentLocation
            )

            ThemeDivider(theme: theme)
                .padding(.vertical, 8)

            HourlyForecastView(hours: weather.hourlyForecasts, theme: theme)

            DailyForecastView(forecasts: weather.dailyForecasts, theme: theme)

            WeatherDetailsView(weather: weather, theme: theme)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ContentView()
}
