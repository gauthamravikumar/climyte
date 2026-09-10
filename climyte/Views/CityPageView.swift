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

            HourlyForecastView(hours: weather.hourlyForecasts, theme: theme)

            // Between the 24-hour strip and the sun arc, so the page reads in
            // order of how far ahead it looks: now, two hours, a day, today's
            // light, a week.
            if let outlook = weather.rainOutlook {
                RainOutlookView(
                    cityName: entry.city.name,
                    outlook: outlook,
                    timeZone: weather.timeZone,
                    theme: theme
                )
            }

            SunArcView(weather: weather, theme: theme)

            DailyForecastView(forecasts: weather.dailyForecasts, theme: theme)

            WeatherDetailsView(weather: weather, theme: theme)

            attribution
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
