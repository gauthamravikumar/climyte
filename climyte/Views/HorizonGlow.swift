//
//  HorizonGlow.swift
//  climyte
//

import SwiftUI

/// Light on the background, coming from where the city's sun actually is.
///
/// The app already inverts between day and night for the city on screen rather
/// than for the phone; this turns that switch into a continuum. The glow sits
/// at the sun's horizontal position, warms as the sun drops towards either
/// horizon, and goes out when it sets — so a screen that is dark at 3am in
/// Reykjavík now says why, instead of simply being black.
struct HorizonGlow: View {
    let weather: CityWeather?
    let theme: WeatherTheme

    var body: some View {
        TimelineView(.everyMinute) { context in
            let days = weather?.solarDays ?? []
            let light = SolarPosition.horizonLight(at: context.date, in: days)
            let elevation = SolarPosition.elevation(at: context.date, in: days)

            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    theme.background

                    if let light {
                        let alpha = peakOpacity(elevation) * light.intensity
                        RadialGradient(
                            colors: [tint(elevation: elevation).opacity(alpha),
                                     tint(elevation: elevation).opacity(alpha * 0.42),
                                     theme.background.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: geometry.size.width * 0.78
                        )
                        .frame(width: geometry.size.width * 1.55,
                               height: geometry.size.width * 1.05)
                        // Centred on the sun, sunk below the edge so only the
                        // top of the light reaches the screen.
                        .offset(x: (light.position - 0.5) * geometry.size.width,
                                y: geometry.size.width * 0.42)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .ignoresSafeArea()
        }
    }

    /// Warm at the horizons, close to daylight overhead — the same shift the
    /// sky makes.
    private func tint(elevation: Double) -> Color {
        Color(hue: 0.075 + 0.03 * elevation,
              saturation: 0.62 - 0.34 * elevation,
              brightness: 1.0)
    }

    /// A white ground shows colour far more readily than a near-black one, so
    /// the same light has to be dialled back in the day theme or it reads as a
    /// stain on paper rather than as light.
    /// Capped so the light can never cost the text its contrast.
    ///
    /// These are not taste. Secondary text sits at 4.81:1 on white and 4.85:1
    /// on the night ground, and warming the ground eats into both. Measured
    /// against the real rendered pixels, 0.16 in the day theme dropped the
    /// bottom of the screen to 4.44:1 — under the floor, right where the city
    /// strip's unselected names sit. These are the largest values that still
    /// clear 4.5:1 at full strength.
    private func peakOpacity(_ elevation: Double) -> Double {
        let base = theme.isNight ? 0.052 : 0.104
        // Strongest at the horizon, where the light is longest and warmest.
        return base * (1 - 0.45 * elevation)
    }
}
