//
//  SearchBarView.swift
//  climyte
//

import SwiftUI

struct SearchBarView: View {
    /// SF Symbols sized in points ignore Dynamic Type entirely: at
    /// accessibility sizes this was a speck beside text three times its
    /// height. @ScaledMetric keeps the drawn size at the default setting
    /// and grows it with everything else.
    @ScaledMetric(relativeTo: .body) private var clearIcon: CGFloat = 16

    /// SF Symbols sized in points ignore Dynamic Type entirely: at
    /// accessibility sizes this was a speck beside text three times its
    /// height. @ScaledMetric keeps the drawn size at the default setting
    /// and grows it with everything else.
    @ScaledMetric(relativeTo: .body) private var searchIcon: CGFloat = 16

    @Binding var query: String
    @Binding var isSearching: Bool
    let theme: WeatherTheme

    @FocusState private var isFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(theme.secondaryText)
                    .font(.system(size: searchIcon))
                    .accessibilityHidden(true)

                // No string title: an empty literal is still extracted as a
                // localizable key, and an empty row in the catalog is a
                // question for whoever translates it. The label is supplied
                // by accessibilityLabel below, and the visible placeholder by
                // the overlay.
                TextField(text: $query) { EmptyView() }
                    .focused($isFocused)
                    .font(.searchField)
                    .foregroundColor(theme.primaryText)
                    // The built-in placeholder takes its colour from the
                    // device's light/dark appearance rather than from the
                    // theme, so on a night-themed city it rendered near-black
                    // on near-black — measured at 1.13:1. Drawing it here ties
                    // it to the same palette as everything else on screen.
                    .overlay(alignment: .leading) {
                        if query.isEmpty {
                            Text("Search city")
                                .font(.searchField)
                                .foregroundColor(theme.secondaryText)
                                // At accessibility sizes this truncated to
                                // "Searc…", leaving an unexplained empty field
                                // for exactly the readers who need the hint.
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("Search city")
                    .accentColor(theme.primaryText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .submitLabel(.search)

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(theme.secondaryText)
                            .font(.system(size: clearIcon, weight: .medium))
                            // A 16pt glyph is roughly 13pt of actual ink. The
                            // frame and hit shape give it the 44pt target the
                            // glyph alone never had — as a floor, not a fixed
                            // size, since past AX-L the glyph outgrows 44pt and
                            // a fixed frame would let it draw over Cancel.
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Clear search")
                }

                if isSearching {
                    Button("Cancel") {
                        query = ""
                        isFocused = false
                    }
                    .font(.searchCancel)
                    .foregroundColor(theme.primaryText)
                    // A control label is not prose: broken across two lines it
                    // rendered as "Canc" / "el", which reads as a fault rather
                    // than as a button.
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    // The label alone is a 15pt-tall target. Every other
                    // control in the app carries this floor; this one was
                    // missed. minHeight, not a fixed frame, so the label can
                    // still grow past 44pt with the type ramp.
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .padding(.leading, 4)
                }
            }

            ThemeDivider(theme: theme)
        }
        .padding(.horizontal, 4)
        // The bar is only built once search is open, and it is opened by a
        // button elsewhere on screen — so it has to take focus itself. Without
        // this, tapping the magnifier gave you a field you then had to tap
        // again before you could type into it.
        .onAppear { isFocused = true }
        .onChange(of: isFocused) { _, focused in
            withAnimation(reduceMotion ? nil : .default) { isSearching = focused }
        }
        // The parent dismisses search by setting the binding (after picking a
        // city, say). Without this, focus stays on the field while isSearching
        // is false, and the next tap can't change isFocused — so onChange never
        // fires and the search bar goes dead until relaunch.
        .onChange(of: isSearching) { _, searching in
            if !searching { isFocused = false }
        }
    }
}
