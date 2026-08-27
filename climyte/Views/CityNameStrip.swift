//
//  CityNameStrip.swift
//  climyte
//

import SwiftUI

/// The page indicator, set in type rather than dots.
///
/// Dots say only "there are five of these and you're on the second". Names say
/// what is either side of you, and can be tapped to jump — so the indicator
/// earns its space instead of just marking position.
struct CityNameStrip: View {
    let entries: [CityEntry]
    let selectedKey: String
    let theme: WeatherTheme
    let onSelect: (CityEntry) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(entries) { entry in
                        Button {
                            onSelect(entry)
                        } label: {
                            label(for: entry)
                        }
                        .buttonStyle(.plain)
                        .id(entry.id)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            // Keep the current city in view when it changes by swipe as well
            // as by tap, otherwise the strip and the page disagree.
            .onChange(of: selectedKey) { _, key in
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(key, anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo(selectedKey, anchor: .center)
            }
        }
    }

    private func label(for entry: CityEntry) -> some View {
        let isSelected = entry.id == selectedKey

        return HStack(spacing: 5) {
            if entry.isCurrentLocation {
                Image(systemName: "location.fill")
                    .font(.system(size: 8))
                    .accessibilityHidden(true)
            }

            Text(entry.city.name)
                .font(isSelected ? .cityStripActive : .cityStrip)
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundColor(isSelected ? theme.primaryText : theme.secondaryText)
        .opacity(isSelected ? 1 : 0.55)
        .contentShape(Rectangle())
        .accessibilityLabel(entry.city.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
