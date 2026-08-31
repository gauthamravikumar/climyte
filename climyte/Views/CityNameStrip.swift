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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                // Unrequested auto-scroll: jump rather than glide when the
                // reader has asked for less motion.
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    proxy.scrollTo(key, anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo(selectedKey, anchor: .center)
            }
        }
    }

    static func position(of entry: CityEntry, in entries: [CityEntry]) -> String {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return "" }
        return String(localized: "\(index + 1) of \(entries.count)")
    }

    private func label(for entry: CityEntry) -> some View {
        let isSelected = entry.id == selectedKey

        return HStack(spacing: 5) {
            if entry.isCurrentLocation {
                Image(systemName: "location.fill")
                    // Scales with the label beside it; at 8pt fixed it stayed
                    // a speck next to text three times its size.
                    .font(.system(size: 8, weight: .semibold))
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }

            Text(entry.city.name)
                .font(isSelected ? .cityStripActive : .cityStrip)
                .lineLimit(1)
                .fixedSize()
        }
        // No opacity on the unselected state. Fading secondaryText to 0.55
        // composited it to #B1B1B1 on white and #4D4D4F on black — 2.14:1 and
        // 2.27:1, the worst contrast in the app and under even the 3:1 floor
        // for non-text. The weight and colour difference already distinguish
        // the current city; the fade only made the others hard to read.
        .foregroundColor(isSelected ? theme.primaryText : theme.secondaryText)
        // Without a minimum the target is only as wide as the name, so short
        // ones like "Oslo" fell well under 44pt and the gaps between entries
        // were dead space rather than shared target area.
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(entry.city.name)
        // The strip replaces the page dots, so it is the only thing that can
        // say where the reader is. Without this a VoiceOver user hears five
        // city names and no indication of how many there are or which is
        // showing.
        .accessibilityValue(Self.position(of: entry, in: entries))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
