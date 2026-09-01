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

    /// The theme change is a half-second crossfade of the entire screen
    /// between near-white and near-black. That is exactly the kind of
    /// large-area luminance flash Reduce Motion exists to suppress, and it
    /// fires on every swipe between a daytime and a night-time city.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.scenePhase) private var scenePhase

    /// Scales with the type ramp, like every other icon in the app.
    @ScaledMetric(relativeTo: .body) private var searchIcon: CGFloat = 17

    private var themeAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.5)
    }

    private var transitionAnimation: Animation? {
        reduceMotion ? nil : .default
    }

    /// The theme follows whichever city is on screen, so swiping from a
    /// daytime city to a night-time one inverts the whole app.
    private var theme: WeatherTheme {
        viewModel.selectedEntry?.weather?.theme ?? WeatherTheme.forIsNight(false)
    }

    var body: some View {
        ZStack {
            theme.background
                .ignoresSafeArea()
                .animation(themeAnimation, value: theme.background)

            VStack(spacing: 16) {
                // The field only exists while it is being used. Kept on screen
                // permanently it cost about 63 points at the top — and, worse,
                // pushed the city name a third of the way down the page, so the
                // thing the screen is about was never the first thing on it.
                if isSearching {
                    SearchBarView(
                        query: $viewModel.searchQuery,
                        isSearching: $isSearching,
                        theme: theme
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                    searchOverlay
                        .padding(.horizontal, 24)
                    Spacer(minLength: 0)
                } else {
                    pager
                }
            }
        }
        .task {
            await viewModel.loadWeatherOnLaunch()
        }
        // Returning to the app after the city's date has rolled over would
        // otherwise leave yesterday labelled "Today" until a manual refresh.
        .onChange(of: scenePhase) { previous, phase in
            guard phase == .active, previous != .active else { return }
            Task { await viewModel.refreshOnForeground() }
        }
    }

    /// Focused with an empty field shows the saved cities; typing searches.
    @ViewBuilder
    private var searchOverlay: some View {
        if viewModel.searchQuery.isEmpty {
            SavedCitiesView(
                entries: viewModel.entries,
                selectedKey: viewModel.selectedCityKey,
                theme: theme,
                canRemove: viewModel.canRemoveCities,
                onSelect: { entry in
                    withAnimation(transitionAnimation) {
                        viewModel.selectEntry(entry)
                        isSearching = false
                    }
                },
                onDelete: viewModel.removeCities
            )
            .transition(.opacity)
        } else {
            SearchResultsView(
                state: viewModel.searchState,
                theme: theme,
                onSelect: { result in
                    withAnimation(transitionAnimation) {
                        viewModel.selectCity(result)
                        isSearching = false
                    }
                },
                onRetry: viewModel.retrySearch
            )
            // Reduce Motion keeps the fade and drops the positional slide.
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
        }
    }

    /// Opens search. Collapsed to an icon, in the bottom bar rather than the
    /// top, because it is tapped occasionally and the bottom edge is where a
    /// thumb already is.
    private var searchButton: some View {
        Button {
            withAnimation(transitionAnimation) { isSearching = true }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: searchIcon, weight: .medium))
                .foregroundColor(theme.secondaryText)
                // The 44pt target the glyph alone would not have.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Search city")
    }

    private var pager: some View {
        VStack(spacing: 0) {
            TabView(selection: $viewModel.selectedCityKey) {
                ForEach(viewModel.entries) { entry in
                    CityPageView(
                        entry: entry,
                        theme: theme,
                        onRefresh: { await viewModel.refresh(cityKey: entry.id) }
                    )
                    .tag(entry.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Always present, unlike the strip beside it: with one saved city
            // there are no names to show, but search still has to be reachable.
            HStack(spacing: 0) {
                searchButton
                    .padding(.leading, 12)

                if viewModel.entries.count > 1 {
                    CityNameStrip(
                        entries: viewModel.entries,
                        selectedKey: viewModel.selectedCityKey,
                        theme: theme,
                        onSelect: { entry in
                            withAnimation(transitionAnimation) { viewModel.selectEntry(entry) }
                        },
                        leadingInset: 0
                    )
                } else {
                    Spacer()
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
