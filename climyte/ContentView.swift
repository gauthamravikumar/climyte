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

    /// The bar, the search field and its close button are named in here,
    /// so the glass can change shape between them.
    @Namespace private var glass

    /// How far up from the screen's bottom edge the bar reaches.
    @State private var barClearance: CGFloat = 0

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
                // Stretched to the screen's edge, this sees how much of the
                // bottom the bar and the home indicator take.
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: {
                    barClearance = $0
                }

            if isSearching {
                searchOverlay
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                pager
            }
        }
        // One bar under reading and searching alike, so opening search
        // reshapes the same glass instead of swapping one bar for another.
        // An inset of this stack, which never changes, and not of the
        // results: as an inset of the results it lost its place each time
        // they changed — the first letter typed swaps the saved cities for
        // results, and the letters after it never reached the field. The
        // page still scrolls on underneath the bar; search results stop at
        // it, and it rides up with the keyboard.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
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
        // Tapping a widget opens the page for the city it shows.
        .onOpenURL { url in
            guard viewModel.showCity(linkedBy: url) else { return }
            isSearching = false
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
                // The pager below is taken past the bar, so a page never
                // learns the bar is there, and its last row stopped under the
                // glass where it could not be scrolled into view. The room is
                // added to the end of the page's content instead.
                .contentMargins(.bottom, barClearance, for: .scrollContent)
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
                    theme: theme,
                    glass: glass
                )
            } else {
                cityBar
            }
        }
        .glassGroup()
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
        .glassBackground(in: Capsule(), id: GlassID.bar, namespace: glass)
    }

    private func openSearch() {
        withAnimation(transitionAnimation) { isSearching = true }
    }

    private var searchGlyph: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: searchIcon, weight: .medium))
            .foregroundStyle(theme.barSecondaryText)
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
                    .foregroundStyle(theme.barSecondaryText)
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

/// Names for the pieces of glass in the bottom bar. The city bar and the
/// search field share one, so one becomes the other.
enum GlassID {
    static let bar = "bar"
    static let close = "close"
}

extension View {
    /// Liquid Glass where the system has it, and a thin material before it.
    ///
    /// The glass takes its tint from whatever is beneath it, which keeps the
    /// bar in the page's own black or white without a colour of its own.
    /// Pieces given the same `id` within one `glassGroup()` change shape
    /// into each other as they come and go.
    @ViewBuilder
    func glassBackground(in shape: some Shape, id: String, namespace: Namespace.ID) -> some View {
        // The glass API arrived with the iOS 26 SDK. An older Xcode, such as
        // the one CI builds with, has never heard of it, and takes the
        // material path at compile time rather than at run time.
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            // On the content itself, so the content is drawn on the glass. As
            // a layer behind it, inside a glass group, the group drew the glass
            // over the names and washed them out.
            glassEffect(.regular, in: shape)
                .glassEffectID(id, in: namespace)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
        #else
        background(.ultraThinMaterial, in: shape)
        #endif
    }

    /// Glass that sits together goes in one container, as Apple asks: the
    /// pieces are drawn in a single pass, they can blend, and only inside
    /// one can they change shape into each other. Before iOS 26 there is
    /// nothing to group.
    @ViewBuilder
    func glassGroup() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer { self }
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#Preview {
    ContentView()
}
