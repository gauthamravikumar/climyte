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

    /// The theme follows whichever city is on screen, so swiping from a
    /// daytime city to a night-time one inverts the whole app.
    private var theme: WeatherTheme {
        viewModel.selectedEntry?.weather?.theme ?? WeatherTheme.forIsNight(false)
    }

    var body: some View {
        ZStack {
            theme.background
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: theme.background)

            VStack(spacing: 16) {
                SearchBarView(
                    query: $viewModel.searchQuery,
                    isSearching: $isSearching,
                    theme: theme
                )
                .padding(.horizontal, 24)
                .padding(.top, 16)

                if isSearching {
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
                    withAnimation {
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
                    withAnimation {
                        viewModel.selectCity(result)
                        isSearching = false
                    }
                },
                onRetry: viewModel.retrySearch
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
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

            if viewModel.entries.count > 1 {
                CityNameStrip(
                    entries: viewModel.entries,
                    selectedKey: viewModel.selectedCityKey,
                    theme: theme,
                    onSelect: { entry in
                        withAnimation { viewModel.selectEntry(entry) }
                    }
                )
            }
        }
    }
}

#Preview {
    ContentView()
}
