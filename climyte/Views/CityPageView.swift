//
//  CityPageView.swift
//  climyte
//

import SwiftUI

/// One city's worth of weather — a single page in the pager.
///
/// Owns its own ScrollView so each page scrolls and refreshes independently.
struct CityPageView: View {
    let entry: CityEntry
    let theme: WeatherTheme
    let onRefresh: () async -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                content
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .refreshable {
            await onRefresh()
        }
        // Each page shows its own city's units, so this is set per page
        // rather than once for the whole app.
        .environment(\.unitSystem, entry.city.unitSystem)
    }

    @ViewBuilder
    private var content: some View {
        if entry.isLoading && entry.weather == nil {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: theme.primaryText))
                .scaleEffect(1.5)
                .padding(.top, 80)
        } else if let weather = entry.weather {
            // A refresh can fail while cached data is still on screen — say so,
            // and say how old what they're looking at is.
            if let message = entry.errorMessage {
                StaleDataNotice(
                    message: message,
                    fetchedAt: entry.lastUpdated,
                    theme: theme
                )
            }

            weatherLayout(weather)
                .transition(.opacity)
        } else if let message = entry.errorMessage {
            WeatherErrorView(message: message, theme: theme) {
                Task { await onRefresh() }
            }
        } else {
            NoWeatherDataView(theme: theme)
        }
    }

    /// Open-Meteo's data is CC-BY, which asks for the source to be named where
    /// the data is shown. At the foot of the page: you meet it if you read to
    /// the end, which is where a credit belongs, and it costs the forecast
    /// above it nothing.
    @ViewBuilder
    private var attribution: some View {
        if let url = URL(string: "https://open-meteo.com") {
            Link(destination: url) {
                Text("Weather from Open-Meteo")
                    .font(.credit)
                    .foregroundColor(theme.secondaryText)
                    // The same 44pt floor every other control carries. The
                    // extra height falls into the padding at the page's foot.
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityHint("Opens open-meteo.com")
        }
    }

    private func weatherLayout(_ weather: CityWeather) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            CurrentConditionsView(
                weather: weather,
                theme: theme,
                isUsingCurrentLocation: entry.isCurrentLocation
            )

            HourlyForecastView(hours: weather.hourlyForecasts, theme: theme)

            SunArcView(weather: weather, theme: theme)

            DailyForecastView(forecasts: weather.dailyForecasts, theme: theme)

            WeatherDetailsView(weather: weather, theme: theme)

            attribution
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
