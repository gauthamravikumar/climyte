//
//  WidgetGlass.swift
//  climyteWidget
//

import SwiftUI
import WidgetKit

// Glass, drawn. A widget cannot blur what is behind it, so these are made of
// what makes glass read as glass: a gradient across the surface, a bright
// rim, a recessed groove and a shadow. The light stays on the objects; the
// widget's ground is never lit. In accented mode, where iOS supplies its own
// glass and tints by alpha, each falls back to a flat shape.

extension WeatherEntry {
    var isNight: Bool { weather?.isNight(at: date) ?? false }
}

/// The recessed track the day runs along.
struct GlassGroove: View {
    let isNight: Bool
    let isAccented: Bool

    var body: some View {
        if isAccented {
            Capsule().fill(.secondary.opacity(0.3))
        } else {
            Capsule().fill(
                (isNight ? Color.white.opacity(0.07) : Color.black.opacity(0.07))
                    .shadow(.inner(color: .black.opacity(isNight ? 0.7 : 0.22), radius: 1.5, y: 1))
                    .shadow(.inner(color: .white.opacity(isNight ? 0.10 : 0.9), radius: 0, y: -1))
            )
        }
    }
}

/// The run of light in the groove, from sunrise to sunset.
struct GlassFill: View {
    let isNight: Bool
    let isAccented: Bool

    var body: some View {
        if isAccented {
            Capsule().fill(.primary)
        } else {
            Capsule().fill(
                LinearGradient(colors: isNight ? [.white, Color(hex: "CFCFCB")]
                                               : [Color(hex: "4A4A4A"), Color(hex: "141414")],
                               startPoint: .top, endPoint: .bottom)
                    .shadow(.inner(color: .white.opacity(isNight ? 1 : 0.35), radius: 0, y: 1))
            )
        }
    }
}

/// The glass bead that marks now: clear by day, smoked at night.
struct GlassBead: View {
    let isNight: Bool
    let isAccented: Bool

    var body: some View {
        if isAccented {
            // One colour for everything here, so the bead cannot differ
            // from the fill in shade. A ring of it let the fill run straight
            // through; a solid dot cut out of the bar by a hairline gap stays
            // a separate thing. The cut needs the bar's compositingGroup.
            Circle()
                .fill(.primary)
                .padding(2.5)
                .background(Circle().fill(.black).blendMode(.destinationOut))
        } else {
            Circle()
                .fill(RadialGradient(
                    stops: isNight
                        ? [.init(color: Color(hex: "9A9CA3"), location: 0.12),
                           .init(color: Color(hex: "3B3D44"), location: 0.46),
                           .init(color: Color(hex: "16171B"), location: 1)]
                        : [.init(color: .white, location: 0.22),
                           .init(color: Color(hex: "F1F1F2"), location: 0.46),
                           .init(color: Color(hex: "CACACD"), location: 1)],
                    center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: 14))
                .overlay(Circle().strokeBorder(isNight ? Color.white.opacity(0.55)
                                                       : Color.black.opacity(0.28), lineWidth: 1))
                .shadow(color: .black.opacity(isNight ? 0.6 : 0.25), radius: 2, y: 2)
        }
    }
}

/// A pane of glass for a widget's last line.
struct GlassChip<Content: View>: View {
    let isNight: Bool
    let isAccented: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                if isAccented {
                    shape.strokeBorder(.secondary.opacity(0.5), lineWidth: 1)
                } else {
                    shape
                        .fill(LinearGradient(colors: isNight ? [.white.opacity(0.10), .white.opacity(0.05)]
                                                             : [.black.opacity(0.05), .black.opacity(0.08)],
                                             startPoint: .top, endPoint: .bottom)
                            .shadow(.inner(color: isNight ? .white.opacity(0.18) : .white, radius: 0, y: 1)))
                        .overlay(shape.strokeBorder(isNight ? Color.white.opacity(0.08)
                                                            : Color.black.opacity(0.08), lineWidth: 1))
                }
            }
    }
}
