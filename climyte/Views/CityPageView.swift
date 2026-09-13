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
            // A refresh can fail while cached data is still on screen, and a
            // saved forecast can be days old — say so, and say how old what
            // they're looking at is.
            if StaleDataNotice.isShown(errorMessage: entry.errorMessage,
                                       fetchedAt: entry.lastUpdated,
                                       isRefreshing: entry.isLoading) {
                StaleDataNotice(
                    message: entry.errorMessage ?? "",
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
    private var attribution: some View {
        // Two links rather than one: CC BY asks for the source to be named
        // and the licence indicated by hyperlink, and a licence you cannot
        // read is a poor indication of it. `tint` because a link left to
        // itself renders in the system accent, which is the only colour the
        // app does not have.
        Text("[Weather from Open-Meteo](https://open-meteo.com) · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)")
            .font(.credit)
            .foregroundColor(theme.secondaryText)
            .tint(theme.secondaryText)
            .frame(minHeight: 44, alignment: .leading)
    }

    private func weatherLayout(_ weather: CityWeather) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            CurrentConditionsView(
                weather: weather,
                theme: theme,
                isUsingCurrentLocation: entry.isCurrentLocation
            )

            // A saved forecast old enough for its hours and days to have
            // passed has nothing left for these to show. A heading over
            // nothing, or last Tuesday standing in for the week, is worse
            // than no section at all.
            if !weather.hourlyForecasts.isEmpty {
                HourlyForecastView(hours: weather.hourlyForecasts, theme: theme)
            }

            if weather.coversToday {
                SunArcView(weather: weather, theme: theme)
            }

            if !weather.dailyForecasts.isEmpty {
                DailyForecastView(forecasts: weather.dailyForecasts, theme: theme)
            }

            WeatherDetailsView(weather: weather, theme: theme)

            attribution
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
