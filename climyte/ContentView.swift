//
//  ContentView.swift
//  climyte
//
//  Created by Antigravity on 23/7/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = WeatherViewModel(citiesSources: .appGroup)
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

    /// The app's clock, so the theme turns on the same minute as everything
    /// else that knows day from night.
    @Environment(\.now) private var now

    private var isNight: Bool {
        viewModel.selectedEntry?.weather?.isNight(at: now) ?? false
    }

    /// The theme follows whichever city is on screen, so swiping from a
    /// daytime city to a night-time one inverts the whole app.
    private var theme: WeatherTheme {
        WeatherTheme.forIsNight(isNight)
    }

    var body: some View {
        ZStack {
            theme.background
                .ignoresSafeArea()
                .animation(themeAnimation, value: theme.background)

            if isSearching {
                // A row of its own here, beneath the results and riding up
                // with the keyboard. As an inset of the results it lost its
                // place each time they changed: the first letter typed swaps
                // the saved cities for results, and the letters after it
                // never reached the field.
                VStack(spacing: 0) {
                    searchOverlay
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .frame(maxHeight: .infinity, alignment: .top)

                    bottomBar
                }
            } else {
                pager
                    // An inset rather than a row of its own: the page scrolls
                    // on underneath the bar instead of stopping at it.
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        bottomBar
                    }
            }
        }
        // A tick as the page turns, by swipe or by tapping a name.
        .sensoryFeedback(.selection, trigger: viewModel.selectedCityKey)
        .task {
            await viewModel.loadWeatherOnLaunch()
        }
        // Returning to the app after the city's date has rolled over would
        // otherwise leave yesterday labelled "Today" until a manual refresh.
        .onChange(of: scenePhase) { previous, phase in
            guard phase == .active, previous != .active else { return }
            Task { await viewModel.refreshOnForeground() }
        }
        // And an app left open needs the same, without ever leaving it.
        .onChange(of: now) { _, now in
            Task { await viewModel.clockTicked(now) }
        }
    }

    /// Focused with an empty field shows the saved cities; typing searches.
    @ViewBuilder
    private var searchOverlay: some View {
        if !viewModel.hasSearchQuery {
            SavedCitiesView(
                entries: viewModel.entries,
                selectedKey: viewModel.selectedCityKey,
                theme: theme,
                canRemove: viewModel.canRemoveCities,
                locationAccessRefused: viewModel.locationAccessRefused,
                onSelect: { entry in
                    withAnimation(transitionAnimation) {
                        viewModel.selectEntry(entry)
                        isSearching = false
                    }
                },
                onDelete: viewModel.removeCities,
                onMove: viewModel.moveCities
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
            .transition(.opacity)
        }
    }

    private var pager: some View {
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
        // A paging TabView stops at the safe area, which left the page cut
        // off along the top of the bar. Taken to the screen's own edge, each
        // page's scroll view runs on beneath the glass.
        .ignoresSafeArea(.container, edges: .bottom)
    }

    // MARK: - Bottom bar

    /// One bar, two jobs: the city names while reading, the search field
    /// while searching. Search opens where the button that opened it was.
    private var bottomBar: some View {
        Group {
            if isSearching {
                SearchBarView(
                    query: $viewModel.searchQuery,
                    isSearching: $isSearching,
                    theme: theme
                )
            } else {
                cityBar
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        // Glass takes its light or dark from the environment, and the page's
        // theme follows the city's sun rather than the device's appearance.
        // Left alone, a night-time city on a phone in light mode got a pale
        // bar over a black page.
        .environment(\.colorScheme, isNight ? .dark : .light)
    }

    /// Search and the city names, floating on one capsule.
    private var cityBar: some View {
        HStack(spacing: 0) {
            // With one saved city there are no names to show, so the bar
            // says what it is for instead of holding a lone icon.
            if viewModel.entries.count > 1 {
                searchButton
                    .padding(.leading, 6)

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
                soloSearchButton
            }
        }
        .frame(minHeight: 52)
        // The names scroll; they must not draw past the capsule's ends.
        .clipShape(Capsule())
        .glassBackground(in: Capsule())
    }

    private func openSearch() {
        withAnimation(transitionAnimation) { isSearching = true }
    }

    private var searchGlyph: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: searchIcon, weight: .medium))
            .foregroundStyle(theme.secondaryText)
    }

    /// Opens search. In the bottom bar rather than the top, because it is
    /// tapped occasionally and the bottom edge is where a thumb already is.
    private var searchButton: some View {
        Button(action: openSearch) {
            searchGlyph
                // minWidth, not a fixed width: the glyph scales with the type
                // ramp and at the largest accessibility size it is bigger than
                // 44pt, so a fixed frame does not contain it — it overflows and
                // draws over whatever sits alongside. 44 is the floor for the
                // tap target, not a ceiling on the icon.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Search city")
    }

    private var soloSearchButton: some View {
        Button(action: openSearch) {
            HStack(spacing: 10) {
                searchGlyph
                    .accessibilityHidden(true)

                Text("Search city")
                    .font(.searchField)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 52)
            .contentShape(Capsule())
        }
    }
}

extension View {
    /// Liquid Glass where the system has it, and a thin material before it.
    ///
    /// The glass takes its tint from whatever is beneath it, which keeps the
    /// bar in the page's own black or white without a colour of its own.
    @ViewBuilder
    func glassBackground(in shape: some Shape) -> some View {
        // The glass API arrived with the iOS 26 SDK. An older Xcode, such as
        // the one CI builds with, has never heard of it, and takes the
        // material path at compile time rather than at run time.
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            // Behind the content rather than applied to it, so the glass is
            // never what hosts the search field.
            background { Color.clear.glassEffect(.regular, in: shape) }
        } else {
            background(.ultraThinMaterial, in: shape)
        }
        #else
        background(.ultraThinMaterial, in: shape)
        #endif
    }
}

#Preview {
    ContentView()
}
