#!/usr/bin/env swift

// Renders the Terra Cognita app icon (concept #1, "Terra") at all the
// sizes the macOS and iOS asset catalogs need, plus writes a
// Contents.json for each.
//
//   swift scripts/render_icon.swift
//
// Output:
//   Apps/TerraCognita-macOS/Assets.xcassets/AppIcon.appiconset/*.png
//   Apps/TerraCognita-iOS/Assets.xcassets/AppIcon.appiconset/*.png

import AppKit
import CoreGraphics
import Foundation

// MARK: - Drawing

/// Draws the Terra icon — tilted globe with meridian lines, an
/// illuminated gold point in the upper-right quadrant, a faint outer
/// "noosphere" ring, and a deep indigo radial background.
func renderTerraIcon(size: Int) -> Data {
    let s = CGFloat(size)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { fatalError("bitmap rep") }

    let prev = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    defer { NSGraphicsContext.current = prev }
    let ctx = NSGraphicsContext.current!.cgContext
    let rgb = CGColorSpaceCreateDeviceRGB()

    // --- Rounded background --------------------------------------------
    // iOS/macOS will further round their AppIcon, but a subtle radius on
    // the bitmap helps the corners blend on macOS where it ships as-is.
    let cornerRadius = s * 0.225
    ctx.beginPath()
    ctx.addPath(CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    ))
    ctx.clip()

    // --- Background radial gradient (deep indigo → near-black) --------
    let bg = CGGradient(colorsSpace: rgb, colors: [
        NSColor(red: 0.14, green: 0.15, blue: 0.24, alpha: 1.0).cgColor,
        NSColor(red: 0.03, green: 0.04, blue: 0.08, alpha: 1.0).cgColor
    ] as CFArray, locations: [0.0, 1.0])!
    ctx.drawRadialGradient(
        bg,
        startCenter: CGPoint(x: s * 0.5, y: s * 0.5),
        startRadius: 0,
        endCenter: CGPoint(x: s * 0.5, y: s * 0.5),
        endRadius: s * 0.72,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // --- Sparse star-field -------------------------------------------
    // Deterministic placements so every render produces the same icon.
    let stars: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (0.12, 0.18, 0.0035, 0.55),
        (0.22, 0.85, 0.0025, 0.40),
        (0.86, 0.12, 0.0030, 0.50),
        (0.08, 0.62, 0.0022, 0.35),
        (0.92, 0.78, 0.0028, 0.45),
        (0.32, 0.08, 0.0020, 0.30),
        (0.78, 0.92, 0.0023, 0.38),
        (0.50, 0.10, 0.0018, 0.32),
        (0.95, 0.45, 0.0024, 0.40)
    ]
    for (x, y, r, a) in stars {
        ctx.setFillColor(NSColor(red: 1, green: 0.95, blue: 0.85, alpha: a).cgColor)
        let rad = s * r
        ctx.fillEllipse(in: CGRect(x: s * x - rad, y: s * y - rad,
                                   width: rad * 2, height: rad * 2))
    }

    // --- Outer "noosphere" ring --------------------------------------
    ctx.setStrokeColor(NSColor(red: 0.85, green: 0.72, blue: 0.40, alpha: 0.30).cgColor)
    ctx.setLineWidth(max(s * 0.003, 1.0))
    ctx.strokeEllipse(in: CGRect(
        x: s * 0.07, y: s * 0.07,
        width: s * 0.86, height: s * 0.86
    ))

    // --- Sphere -------------------------------------------------------
    let sphereRect = CGRect(
        x: s * 0.13, y: s * 0.13,
        width: s * 0.74, height: s * 0.74
    )

    // Sphere body with off-centre radial gradient (light from upper-left).
    ctx.saveGState()
    ctx.addEllipse(in: sphereRect)
    ctx.clip()
    let sphere = CGGradient(colorsSpace: rgb, colors: [
        NSColor(red: 0.26, green: 0.30, blue: 0.46, alpha: 1.0).cgColor,
        NSColor(red: 0.10, green: 0.12, blue: 0.20, alpha: 1.0).cgColor,
        NSColor(red: 0.04, green: 0.05, blue: 0.10, alpha: 1.0).cgColor
    ] as CFArray, locations: [0.0, 0.7, 1.0])!
    ctx.drawRadialGradient(
        sphere,
        startCenter: CGPoint(x: s * 0.38, y: s * 0.65),
        startRadius: 0,
        endCenter: CGPoint(x: s * 0.5, y: s * 0.5),
        endRadius: s * 0.42,
        options: []
    )
    ctx.restoreGState()

    // --- Meridian lines (longitude + equator) ------------------------
    ctx.saveGState()
    ctx.addEllipse(in: sphereRect)
    ctx.clip()
    ctx.setStrokeColor(NSColor(red: 0.55, green: 0.65, blue: 0.85, alpha: 0.32).cgColor)
    ctx.setLineWidth(max(s * 0.003, 0.8))
    // Longitude arcs — ellipses of decreasing horizontal radius.
    for i in 0..<5 {
        let scale = 1.0 - CGFloat(i) * 0.22
        let rect = CGRect(
            x: s * 0.5 - sphereRect.width * 0.5 * scale,
            y: sphereRect.minY,
            width: sphereRect.width * scale,
            height: sphereRect.height
        )
        ctx.strokeEllipse(in: rect)
    }
    // Equator (a tall ellipse foreshortened so it reads as horizontal).
    ctx.setStrokeColor(NSColor(red: 0.55, green: 0.65, blue: 0.85, alpha: 0.40).cgColor)
    ctx.strokeEllipse(in: CGRect(
        x: sphereRect.minX,
        y: s * 0.5 - sphereRect.height * 0.10,
        width: sphereRect.width,
        height: sphereRect.height * 0.20
    ))
    // One tilted latitude line above
    ctx.strokeEllipse(in: CGRect(
        x: sphereRect.minX + s * 0.02,
        y: s * 0.5 + sphereRect.height * 0.10,
        width: sphereRect.width - s * 0.04,
        height: sphereRect.height * 0.16
    ))
    ctx.restoreGState()

    // --- Subtle sphere rim highlight ---------------------------------
    ctx.setStrokeColor(NSColor(red: 0.85, green: 0.90, blue: 1.0, alpha: 0.18).cgColor)
    ctx.setLineWidth(max(s * 0.005, 1.0))
    ctx.strokeEllipse(in: sphereRect)

    // --- Illuminated point: "explored territory" ---------------------
    // Upper-right of the sphere, with a layered halo.
    let star = CGPoint(x: s * 0.65, y: s * 0.70)

    // Outer halo
    let halo = CGGradient(colorsSpace: rgb, colors: [
        NSColor(red: 1.0, green: 0.85, blue: 0.45, alpha: 0.60).cgColor,
        NSColor(red: 1.0, green: 0.75, blue: 0.30, alpha: 0.0).cgColor
    ] as CFArray, locations: [0.0, 1.0])!
    ctx.drawRadialGradient(
        halo,
        startCenter: star, startRadius: 0,
        endCenter: star, endRadius: s * 0.12,
        options: []
    )

    // Inner halo
    let innerHalo = CGGradient(colorsSpace: rgb, colors: [
        NSColor(red: 1.0, green: 0.95, blue: 0.75, alpha: 0.85).cgColor,
        NSColor(red: 1.0, green: 0.90, blue: 0.55, alpha: 0.0).cgColor
    ] as CFArray, locations: [0.0, 1.0])!
    ctx.drawRadialGradient(
        innerHalo,
        startCenter: star, startRadius: 0,
        endCenter: star, endRadius: s * 0.05,
        options: []
    )

    // Star core
    ctx.setFillColor(NSColor(red: 1.0, green: 0.98, blue: 0.92, alpha: 1.0).cgColor)
    let coreR = s * 0.015
    ctx.fillEllipse(in: CGRect(
        x: star.x - coreR, y: star.y - coreR,
        width: coreR * 2, height: coreR * 2
    ))

    // --- Encode to PNG -----------------------------------------------
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("PNG encoding failed")
    }
    return data
}

// MARK: - Asset catalog writing

struct IconSize {
    let pixels: Int
    let filename: String
    /// Contents.json idiom + size + scale.
    let idiom: String
    let sizeStr: String
    let scale: String
}

let projectRoot = FileManager.default.currentDirectoryPath
let macIconset = "\(projectRoot)/Apps/TerraCognita-macOS/Assets.xcassets/AppIcon.appiconset"
let iosIconset = "\(projectRoot)/Apps/TerraCognita-iOS/Assets.xcassets/AppIcon.appiconset"

// macOS asset catalog needs 10 image entries (5 sizes × 1x/2x).
let macSizes: [IconSize] = [
    IconSize(pixels: 16,   filename: "icon_16x16.png",       idiom: "mac", sizeStr: "16x16",   scale: "1x"),
    IconSize(pixels: 32,   filename: "icon_16x16@2x.png",    idiom: "mac", sizeStr: "16x16",   scale: "2x"),
    IconSize(pixels: 32,   filename: "icon_32x32.png",       idiom: "mac", sizeStr: "32x32",   scale: "1x"),
    IconSize(pixels: 64,   filename: "icon_32x32@2x.png",    idiom: "mac", sizeStr: "32x32",   scale: "2x"),
    IconSize(pixels: 128,  filename: "icon_128x128.png",     idiom: "mac", sizeStr: "128x128", scale: "1x"),
    IconSize(pixels: 256,  filename: "icon_128x128@2x.png",  idiom: "mac", sizeStr: "128x128", scale: "2x"),
    IconSize(pixels: 256,  filename: "icon_256x256.png",     idiom: "mac", sizeStr: "256x256", scale: "1x"),
    IconSize(pixels: 512,  filename: "icon_256x256@2x.png",  idiom: "mac", sizeStr: "256x256", scale: "2x"),
    IconSize(pixels: 512,  filename: "icon_512x512.png",     idiom: "mac", sizeStr: "512x512", scale: "1x"),
    IconSize(pixels: 1024, filename: "icon_512x512@2x.png",  idiom: "mac", sizeStr: "512x512", scale: "2x")
]

// iOS uses the "single-size" 1024×1024 marketing icon — Xcode generates
// the smaller sizes automatically on modern toolchains.
let iosSizes: [IconSize] = [
    IconSize(pixels: 1024, filename: "icon_1024.png", idiom: "universal", sizeStr: "1024x1024", scale: "1x")
]

func writeIcons(at dir: String, sizes: [IconSize]) {
    let fm = FileManager.default
    try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

    for entry in sizes {
        let data = renderTerraIcon(size: entry.pixels)
        let url = URL(fileURLWithPath: "\(dir)/\(entry.filename)")
        try! data.write(to: url)
        print("  wrote \(entry.filename) (\(entry.pixels)px)")
    }

    // Contents.json
    let images: [[String: String]] = sizes.map { entry in
        if entry.idiom == "universal" {
            return [
                "idiom": "universal",
                "platform": "ios",
                "size": entry.sizeStr,
                "filename": entry.filename
            ]
        } else {
            return [
                "idiom": entry.idiom,
                "size": entry.sizeStr,
                "scale": entry.scale,
                "filename": entry.filename
            ]
        }
    }
    let contents: [String: Any] = [
        "images": images,
        "info": ["version": 1, "author": "xcode"]
    ]
    let json = try! JSONSerialization.data(
        withJSONObject: contents,
        options: [.prettyPrinted, .sortedKeys]
    )
    try! json.write(to: URL(fileURLWithPath: "\(dir)/Contents.json"))
    print("  wrote Contents.json")

    // Parent Assets.xcassets needs a Contents.json too.
    let parent = URL(fileURLWithPath: dir).deletingLastPathComponent()
    let parentJSON: [String: Any] = ["info": ["version": 1, "author": "xcode"]]
    let parentData = try! JSONSerialization.data(
        withJSONObject: parentJSON,
        options: [.prettyPrinted, .sortedKeys]
    )
    try! parentData.write(to: parent.appendingPathComponent("Contents.json"))
}

print("Rendering macOS AppIcon set…")
writeIcons(at: macIconset, sizes: macSizes)
print("Rendering iOS AppIcon set…")
writeIcons(at: iosIconset, sizes: iosSizes)
print("Done.")
