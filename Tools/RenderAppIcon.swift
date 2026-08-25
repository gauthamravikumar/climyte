// RenderAppIcon.swift
//
// Regenerates the Climyte app icon in its three iOS appearances.
//
//   swift Tools/RenderAppIcon.swift climyte/Assets.xcassets/AppIcon.appiconset
//
// The mark is the app's own mechanic made visual: warm sky above the horizon,
// dusk below, and a sun whose colour inverts as it crosses the line — the same
// day/night switch the UI performs from the location's real sunrise and sunset.
//
// Kept outside climyte/ deliberately: that directory is a file-system
// synchronized group, so anything inside it would be compiled into the app.

import AppKit
import CoreGraphics
import Foundation

let outputDirectory = CommandLine.arguments[1]
let side: CGFloat = 1024

// MARK: - Geometry
//
// Shared by every appearance so the three variants stay in register.

let horizon: CGFloat = 380
let sunRadius: CGFloat = 268
let sunCenterY: CGFloat = 445 // ~62% of the disc above the horizon

// MARK: - Palettes

struct Palette {
    let sky: [CGColor]     // top of frame -> horizon
    let night: [CGColor]   // horizon -> bottom of frame
    let sunAbove: CGColor
    let sunBelow: CGColor
}

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
}

let palettes: [String: Palette] = [
    "light": Palette(
        sky: [rgb(0xFFC862), rgb(0xFF6B4A), rgb(0xE8456B)],
        night: [rgb(0x241650), rgb(0x120B2A)],
        sunAbove: rgb(0xFFF6E8),
        sunBelow: rgb(0xFFC862)
    ),
    // Deeper and less luminous so it doesn't glare on a dark home screen.
    "dark": Palette(
        sky: [rgb(0xC98F45), rgb(0xC9503A), rgb(0xA32F52)],
        night: [rgb(0x180E36), rgb(0x080418)],
        sunAbove: rgb(0xEADCC4),
        sunBelow: rgb(0xD9A445)
    ),
    // Greyscale; the system applies the user's tint to the luminance.
    "tinted": Palette(
        sky: [rgb(0xC4C4C4), rgb(0x9E9E9E), rgb(0x7A7A7A)],
        night: [rgb(0x3A3A3A), rgb(0x1C1C1C)],
        sunAbove: rgb(0xF7F7F7),
        sunBelow: rgb(0xC4C4C4)
    ),
]

// MARK: - Rendering

func verticalGradient(_ context: CGContext, _ colors: [CGColor], _ locations: [CGFloat],
                      from yStart: CGFloat, to yEnd: CGFloat) {
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors as CFArray,
                              locations: locations)!
    context.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: yStart),
                               end: CGPoint(x: 0, y: yEnd),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func render(_ palette: Palette) -> CGImage {
    let context = CGContext(data: nil, width: Int(side), height: Int(side),
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

    verticalGradient(context, palette.sky, [0, 0.6, 1], from: side, to: horizon)

    context.saveGState()
    context.clip(to: CGRect(x: 0, y: 0, width: side, height: horizon))
    verticalGradient(context, palette.night, [0, 1], from: horizon, to: 0)
    context.restoreGState()

    let disc = CGRect(x: side / 2 - sunRadius, y: sunCenterY - sunRadius,
                      width: sunRadius * 2, height: sunRadius * 2)

    // The inversion: the disc takes one colour above the horizon and another
    // below it, so a single shape carries both day and night.
    for (clip, color) in [
        (CGRect(x: 0, y: horizon, width: side, height: side - horizon), palette.sunAbove),
        (CGRect(x: 0, y: 0, width: side, height: horizon), palette.sunBelow),
    ] {
        context.saveGState()
        context.clip(to: clip)
        context.setFillColor(color)
        context.fillEllipse(in: disc)
        context.restoreGState()
    }

    return context.makeImage()!
}

for (name, palette) in palettes.sorted(by: { $0.key < $1.key }) {
    let image = render(palette)
    let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    let path = "\(outputDirectory)/AppIcon-\(name).png"
    try png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(png.count) bytes)")
}
