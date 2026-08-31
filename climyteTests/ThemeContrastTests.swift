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
