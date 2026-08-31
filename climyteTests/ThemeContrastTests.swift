//
//  ThemeContrastTests.swift
//  climyteTests
//

import XCTest
import SwiftUI
@testable import climyte

/// Guards the palette against WCAG AA.
///
/// Worth automating because of how the one failure here happened: the night
/// theme inherited the day theme's secondary grey unchanged, which measured
/// comfortably against white and 3.98:1 against near-black. Nothing about
/// reusing a colour across an inversion looks wrong in a diff.
@MainActor
final class ThemeContrastTests: XCTestCase {

    /// The floor for normal-sized text. Almost every style in the ramp is
    /// below the 18pt/14pt-bold threshold that would relax this to 3:1.
    private let minimumNormalText = 4.5

    func testSecondaryTextMeetsAAOnBothThemes() {
        for isNight in [true, false] {
            let theme = WeatherTheme.forIsNight(isNight)
            let ratio = contrast(theme.secondaryText, theme.background)

            XCTAssertGreaterThanOrEqual(
                ratio, minimumNormalText,
                "secondaryText on the \(isNight ? "night" : "day") theme is \(rounded(ratio)):1"
            )
        }
    }

    func testPrimaryTextMeetsAAOnBothThemes() {
        for isNight in [true, false] {
            let theme = WeatherTheme.forIsNight(isNight)
            let ratio = contrast(theme.primaryText, theme.background)

            XCTAssertGreaterThanOrEqual(
                ratio, minimumNormalText,
                "primaryText on the \(isNight ? "night" : "day") theme is \(rounded(ratio)):1"
            )
        }
    }

    /// Both themes should read with the same weight, which is the thing that
    /// silently stopped being true once and would not be noticed if it did
    /// again: each alone can pass while the pair feels inconsistent.
    func testBothThemesGiveSecondaryTextComparableWeight() {
        let night = WeatherTheme.forIsNight(true)
        let day = WeatherTheme.forIsNight(false)

        let difference = abs(contrast(night.secondaryText, night.background)
                             - contrast(day.secondaryText, day.background))

        XCTAssertLessThan(difference, 0.5,
                          "Day and night hierarchies have drifted apart by \(rounded(difference))")
    }

    // MARK: - Composited colours

    /// The token is not what the reader sees.
    ///
    /// The city strip faded `secondaryText` to 0.55 to mark the unselected
    /// entries, compositing it to 2.14:1 on white and 2.27:1 on black — the
    /// worst contrast in the app, under even the 3:1 floor for non-text. The
    /// tests above passed throughout, because they measure the colour the
    /// palette defines rather than the colour that reaches the screen.
    func testFadingSecondaryTextBelowFullOpacityBreaksIt() {
        for isNight in [true, false] {
            let theme = WeatherTheme.forIsNight(isNight)

            let faded = contrast(composite(theme.secondaryText, over: theme.background, alpha: 0.55),
                                 theme.background)
            XCTAssertLessThan(faded, 3.0,
                              "Kept as the record of why this fade cannot come back")

            // Even a gentle fade does not clear the bar for normal text.
            let gentle = contrast(composite(theme.secondaryText, over: theme.background, alpha: 0.9),
                                  theme.background)
            XCTAssertLessThan(gentle, minimumNormalText)
        }
    }

    /// The strip's two real states, at full opacity, in both themes.
    func testCityStripStatesMeetAA() {
        for isNight in [true, false] {
            let theme = WeatherTheme.forIsNight(isNight)

            XCTAssertGreaterThanOrEqual(contrast(theme.primaryText, theme.background),
                                        minimumNormalText, "Selected city")
            XCTAssertGreaterThanOrEqual(contrast(theme.secondaryText, theme.background),
                                        minimumNormalText, "Unselected city")
        }
    }

    /// Alpha-composites `color` onto `background`, as the renderer does.
    private func composite(_ color: Color, over background: Color, alpha: Double) -> Color {
        let (r, g, b) = components(color)
        let (br, bg, bb) = components(background)
        return Color(red: r * alpha + br * (1 - alpha),
                     green: g * alpha + bg * (1 - alpha),
                     blue: b * alpha + bb * (1 - alpha))
    }

    private func components(_ color: Color) -> (Double, Double, Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }

    // MARK: - Helpers

    private func rounded(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func contrast(_ a: Color, _ b: Color) -> Double {
        let (high, low) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (high + 0.05) / (low + 0.05)
    }

    /// WCAG relative luminance of the colour as it actually renders, taken
    /// through UIColor rather than from the hex literal — a test that reads
    /// the same source string the code does would pass even if `Color(hex:)`
    /// were parsing it wrongly.
    private func luminance(_ color: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)

        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }
}
