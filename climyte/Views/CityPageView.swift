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

    @State private var position = ScrollPosition(edge: .top)

    /// Where the big temperature ends, measured down the page.
    @State private var readingBottom: CGFloat = .infinity

    /// Once the name and the reading have scrolled away, the page could be
    /// any city's. A small capsule then keeps both in view.
    @State private var showsCompactHeader = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                content
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .coordinateSpace(.named(Self.space))
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > readingBottom
        } action: { _, scrolledPast in
            withAnimation(reduceMotion ? nil : .snappy) { showsCompactHeader = scrolledPast }
        }
        .refreshable {
            await onRefresh()
        }
        // The page stopped in a hard line under the status bar, slicing
        // through whatever was scrolling past it, and at large text sizes
        // showed through the bottom bar behind the city names. It now eases
        // out at the top and dims as it passes under the bar.
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 16)
                Color.black
                LinearGradient(colors: [.black, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 110)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        // Outside the mask, so the fade at the top of the page leaves it whole.
        .overlay(alignment: .top) {
            if showsCompactHeader, let weather = entry.weather {
                compactHeader(weather)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // Each page shows its own city's units, so this is set per page
        // rather than once for the whole app.
        .environment(\.unitSystem, entry.city.unitSystem)
    }

    @ViewBuilder
    private var content: some View {
        if entry.isLoading && entry.weather == nil {
            PageSkeleton(cityName: entry.city.name, theme: theme)
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
            .foregroundStyle(theme.secondaryText)
            .tint(theme.secondaryText)
            .frame(minHeight: 44, alignment: .leading)
    }

    /// The page's own coordinates, so the reading can say where it ends.
    nonisolated static let space = "cityPage"

    /// The name and the reading, small, under the status bar. Tapping it
    /// goes back to the top, where both are full size again.
    private func compactHeader(_ weather: CityWeather) -> some View {
        let temperature = entry.city.unitSystem.temperature(weather.temperature)
        return Button {
            withAnimation(reduceMotion ? nil : .smooth) { position.scrollTo(edge: .top) }
        } label: {
            HStack(spacing: 8) {
                Text(entry.city.name)
                    .font(.compactCity)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                Text(temperature)
                    .font(.compactTemperature)
                    .foregroundStyle(theme.barSecondaryText)
                    .fixedSize()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 36)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassBackground(in: Capsule())
        .environment(\.colorScheme, theme.colorScheme)
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .accessibilityLabel(Text("\(entry.city.name), \(temperature)"))
        .accessibilityHint(Text("Scrolls to the top"))
    }

    private func weatherLayout(_ weather: CityWeather) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            CurrentConditionsView(
                weather: weather,
                theme: theme,
                isUsingCurrentLocation: entry.isCurrentLocation,
                // The big temperature, not the whole header: on a short page
                // the condition line below it never leaves the screen, and
                // the capsule never came.
                onReadingBottom: { readingBottom = $0 }
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
