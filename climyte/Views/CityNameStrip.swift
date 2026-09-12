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
    /// SF Symbols sized in points ignore Dynamic Type entirely: at
    /// accessibility sizes this was a speck beside text three times its
    /// height. @ScaledMetric keeps the drawn size at the default setting
    /// and grows it with everything else.
    @ScaledMetric(relativeTo: .caption) private var locationIcon: CGFloat = 8

    let entries: [CityEntry]
    let selectedKey: String
    let theme: WeatherTheme
    let onSelect: (CityEntry) -> Void

    /// Room at the leading edge. Defaults to the screen margin; the search
    /// button sits in that margin, so when it is present this drops to zero
    /// rather than indenting the first city name twice over.
    var leadingInset: CGFloat = 24

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The strip's visible width, measured, because the room after the last
    /// name depends on it.
    @State private var viewportWidth: CGFloat = 0

    /// Room after the last name. At accessibility sizes it is wide enough for
    /// any name — the last one included — to be scrolled to the leading edge.
    ///
    /// Without it the scroll view clamps at the end of its content, and the
    /// name before the last is left straddling the edge beside the search
    /// button: "urne  Singapore" rather than "Singapore". That read as a name
    /// missing its first letters. Empty room past the end is the lesser evil;
    /// a clipped word reads as a different word.
    ///
    /// The viewport less 44 — the narrowest a name's target can be — is enough
    /// for even the narrowest last name to reach the leading edge.
    private var trailingRoom: CGFloat {
        guard typeSize.isAccessibilitySize else { return 24 }
        return max(viewportWidth - 44, 24)
    }

    /// Centring shows the names either side of you, which is the whole reason
    /// this strip is set in type rather than dots. But once a single name is
    /// wider than the screen — a long one at an accessibility size — centring
    /// it scrolls past its own beginning, so the reader sees the middle of a
    /// word. Past that threshold, start of the name wins.
    private var scrollAnchor: UnitPoint {
        typeSize.isAccessibilitySize ? .leading : .center
    }

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
                .padding(.leading, leadingInset)
                .padding(.trailing, trailingRoom)
                .padding(.vertical, 12)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
            // The room above only exists once the width is known, which is
            // after the first scroll has already happened — and clamped.
            .onChange(of: viewportWidth) { _, _ in
                proxy.scrollTo(selectedKey, anchor: scrollAnchor)
            }
            // Keep the current city in view when it changes by swipe as well
            // as by tap, otherwise the strip and the page disagree.
            .onChange(of: selectedKey) { _, key in
                // Unrequested auto-scroll: jump rather than glide when the
                // reader has asked for less motion.
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    proxy.scrollTo(key, anchor: scrollAnchor)
                }
            }
            .onAppear {
                proxy.scrollTo(selectedKey, anchor: scrollAnchor)
            }
            // A type-size change re-lays out every entry, which leaves the
            // strip scrolled to wherever the old widths happened to put it —
            // showing names either side of a city that is not the live page.
            .onChange(of: typeSize) { _, _ in
                proxy.scrollTo(selectedKey, anchor: scrollAnchor)
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
                    .font(.system(size: locationIcon, weight: .semibold))
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
