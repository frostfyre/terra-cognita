#!/usr/bin/env swift

// Renders the Terra Cognita app icon (orrery composition) at all the
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

/// Draws the Terra Cognita icon — a small orrery on a near-black ground:
/// a warm gold "sun" sphere at the centre, three concentric orbital
/// rings, and several planet-like bodies (pale gold, blue-grey,
/// lavender, dark) sitting on those rings, plus tiny port-dots that
/// stipple the orbits.
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
    let cornerRadius = s * 0.225
    ctx.beginPath()
    ctx.addPath(CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    ))
    ctx.clip()

    // --- Background radial gradient (near-black, warm-tinted core) ----
    let bg = CGGradient(colorsSpace: rgb, colors: [
        NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0).cgColor,
        NSColor(red: 0.02, green: 0.02, blue: 0.04, alpha: 1.0).cgColor
    ] as CFArray, locations: [0.0, 1.0])!
    ctx.drawRadialGradient(
        bg,
        startCenter: CGPoint(x: s * 0.5, y: s * 0.5),
        startRadius: 0,
        endCenter: CGPoint(x: s * 0.5, y: s * 0.5),
        endRadius: s * 0.78,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // --- Sparse star-field --------------------------------------------
    // Deterministic placements; the orrery rings sweep across the canvas
    // so we keep the field thin and biased toward the corners.
    let stars: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (0.08, 0.18, 0.0028, 0.45),
        (0.18, 0.86, 0.0022, 0.35),
        (0.90, 0.12, 0.0026, 0.45),
        (0.06, 0.62, 0.0020, 0.30),
        (0.94, 0.78, 0.0024, 0.40),
        (0.30, 0.05, 0.0018, 0.30),
        (0.82, 0.94, 0.0021, 0.32),
        (0.97, 0.45, 0.0022, 0.35),
        (0.04, 0.36, 0.0020, 0.28)
    ]
    for (x, y, r, a) in stars {
        ctx.setFillColor(NSColor(red: 1, green: 0.95, blue: 0.85, alpha: a).cgColor)
        let rad = s * r
        ctx.fillEllipse(in: CGRect(x: s * x - rad, y: s * y - rad,
                                   width: rad * 2, height: rad * 2))
    }

    // --- Orbital geometry --------------------------------------------
    // Rings are concentric on the sun. Radii are tuned so the outer
    // ring sits well inside the squircle (so iOS's corner mask doesn't
    // crop the planets).
    let centre = CGPoint(x: s * 0.50, y: s * 0.50)
    let ringRadii: [CGFloat] = [s * 0.18, s * 0.30, s * 0.42]

    // Draw the rings (thin warm-gold strokes, low opacity).
    ctx.setStrokeColor(NSColor(red: 0.92, green: 0.78, blue: 0.42, alpha: 0.55).cgColor)
    ctx.setLineWidth(max(s * 0.0035, 0.8))
    for r in ringRadii {
        ctx.strokeEllipse(in: CGRect(x: centre.x - r, y: centre.y - r,
                                     width: r * 2, height: r * 2))
    }

    // --- Port dots — tiny stipple along each ring --------------------
    // Each entry is (ringIndex, angleRadians, radiusFraction, opacity).
    let portDots: [(Int, CGFloat, CGFloat, CGFloat)] = [
        (0, 1.6, 0.005, 0.85),
        (0, 4.2, 0.004, 0.75),
        (1, 0.8, 0.005, 0.85),
        (1, 3.0, 0.004, 0.65),
        (1, 5.3, 0.004, 0.70),
        (2, 0.2, 0.005, 0.85),
        (2, 2.4, 0.004, 0.70),
        (2, 3.9, 0.005, 0.80),
        (2, 5.7, 0.004, 0.65)
    ]
    for (ringIdx, angle, radFrac, alpha) in portDots {
        let r = ringRadii[ringIdx]
        let cx = centre.x + cos(angle) * r
        let cy = centre.y + sin(angle) * r
        let rad = s * radFrac
        ctx.setFillColor(NSColor(red: 0.95, green: 0.85, blue: 0.55, alpha: alpha).cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - rad, y: cy - rad,
                                   width: rad * 2, height: rad * 2))
    }

    // --- Planets on the rings ----------------------------------------
    // Each planet is a shaded sphere; "light from upper-left" means the
    // inner gradient start is offset toward upper-left of the planet.
    struct Planet {
        let ring: Int        // index into ringRadii
        let angle: CGFloat   // radians (0 = right, π/2 = top)
        let radius: CGFloat  // as fraction of canvas
        let hi: NSColor
        let mid: NSColor
        let lo: NSColor
    }

    let cream  = (NSColor(red: 1.00, green: 0.95, blue: 0.78, alpha: 1),
                  NSColor(red: 0.92, green: 0.82, blue: 0.55, alpha: 1),
                  NSColor(red: 0.55, green: 0.45, blue: 0.25, alpha: 1))
    let slate  = (NSColor(red: 0.85, green: 0.88, blue: 0.92, alpha: 1),
                  NSColor(red: 0.68, green: 0.74, blue: 0.80, alpha: 1),
                  NSColor(red: 0.30, green: 0.34, blue: 0.42, alpha: 1))
    let lilac  = (NSColor(red: 0.82, green: 0.78, blue: 0.92, alpha: 1),
                  NSColor(red: 0.62, green: 0.55, blue: 0.78, alpha: 1),
                  NSColor(red: 0.30, green: 0.24, blue: 0.40, alpha: 1))
    let coal   = (NSColor(red: 0.42, green: 0.40, blue: 0.45, alpha: 1),
                  NSColor(red: 0.22, green: 0.20, blue: 0.24, alpha: 1),
                  NSColor(red: 0.08, green: 0.07, blue: 0.09, alpha: 1))

    let planets: [Planet] = [
        // Outer ring — pale gold upper-left (the "anchor" planet)
        Planet(ring: 2, angle: 2.45, radius: 0.052, hi: cream.0, mid: cream.1, lo: cream.2),
        // Outer ring — small dark planet lower-right
        Planet(ring: 2, angle: -0.55, radius: 0.030, hi: coal.0,  mid: coal.1,  lo: coal.2),
        // Outer ring — small slate planet lower-left
        Planet(ring: 2, angle: 3.55, radius: 0.026, hi: slate.0, mid: slate.1, lo: slate.2),
        // Middle ring — pale blue-grey upper-right
        Planet(ring: 1, angle: 0.55, radius: 0.045, hi: slate.0, mid: slate.1, lo: slate.2),
        // Middle ring — lilac at ~3 o'clock
        Planet(ring: 1, angle: -0.15, radius: 0.040, hi: lilac.0, mid: lilac.1, lo: lilac.2),
        // Inner ring — small cream tick upper area
        Planet(ring: 0, angle: 1.95, radius: 0.022, hi: cream.0, mid: cream.1, lo: cream.2),
    ]

    for p in planets {
        let r = ringRadii[p.ring]
        let cx = centre.x + cos(p.angle) * r
        let cy = centre.y + sin(p.angle) * r
        let pr = s * p.radius
        let rect = CGRect(x: cx - pr, y: cy - pr, width: pr * 2, height: pr * 2)

        // Subtle drop-shadow underneath the planet so it doesn't read flat.
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -pr * 0.18),
            blur: pr * 0.55,
            color: NSColor(white: 0, alpha: 0.55).cgColor
        )
        ctx.setFillColor(p.lo.cgColor)
        ctx.fillEllipse(in: rect)
        ctx.restoreGState()

        // Shaded body — radial gradient with light from upper-left.
        ctx.saveGState()
        ctx.addEllipse(in: rect)
        ctx.clip()
        let grad = CGGradient(colorsSpace: rgb, colors: [
            p.hi.cgColor, p.mid.cgColor, p.lo.cgColor
        ] as CFArray, locations: [0.0, 0.55, 1.0])!
        ctx.drawRadialGradient(
            grad,
            startCenter: CGPoint(x: cx - pr * 0.40, y: cy + pr * 0.40),
            startRadius: 0,
            endCenter: CGPoint(x: cx, y: cy),
            endRadius: pr * 1.10,
            options: []
        )
        ctx.restoreGState()

        // Specular highlight (tiny pale crescent on upper-left).
        ctx.saveGState()
        ctx.addEllipse(in: rect)
        ctx.clip()
        let hi = CGGradient(colorsSpace: rgb, colors: [
            NSColor(white: 1, alpha: 0.55).cgColor,
            NSColor(white: 1, alpha: 0.0).cgColor
        ] as CFArray, locations: [0.0, 1.0])!
        ctx.drawRadialGradient(
            hi,
            startCenter: CGPoint(x: cx - pr * 0.45, y: cy + pr * 0.45),
            startRadius: 0,
            endCenter: CGPoint(x: cx - pr * 0.30, y: cy + pr * 0.30),
            endRadius: pr * 0.55,
            options: []
        )
        ctx.restoreGState()
    }

    // --- Central sun -------------------------------------------------
    // Largest body in the composition. Warm gold with a soft halo so the
    // viewer's eye lands here first.
    let sunRadius = s * 0.12

    // Outer halo — broad, low-opacity gold glow.
    let sunHalo = CGGradient(colorsSpace: rgb, colors: [
        NSColor(red: 1.00, green: 0.82, blue: 0.45, alpha: 0.35).cgColor,
        NSColor(red: 1.00, green: 0.70, blue: 0.30, alpha: 0.00).cgColor
    ] as CFArray, locations: [0.0, 1.0])!
    ctx.drawRadialGradient(
        sunHalo,
        startCenter: centre, startRadius: 0,
        endCenter: centre, endRadius: sunRadius * 2.4,
        options: []
    )

    // Sun body — pale-cream highlight upper-left → warm gold → deep amber rim.
    let sunRect = CGRect(
        x: centre.x - sunRadius, y: centre.y - sunRadius,
        width: sunRadius * 2, height: sunRadius * 2
    )
    ctx.saveGState()
    ctx.addEllipse(in: sunRect)
    ctx.clip()
    let sunBody = CGGradient(colorsSpace: rgb, colors: [
        NSColor(red: 1.00, green: 0.96, blue: 0.82, alpha: 1.0).cgColor,
        NSColor(red: 0.96, green: 0.82, blue: 0.50, alpha: 1.0).cgColor,
        NSColor(red: 0.78, green: 0.58, blue: 0.28, alpha: 1.0).cgColor,
        NSColor(red: 0.42, green: 0.30, blue: 0.12, alpha: 1.0).cgColor
    ] as CFArray, locations: [0.0, 0.45, 0.85, 1.0])!
    ctx.drawRadialGradient(
        sunBody,
        startCenter: CGPoint(x: centre.x - sunRadius * 0.35,
                             y: centre.y + sunRadius * 0.40),
        startRadius: 0,
        endCenter: centre,
        endRadius: sunRadius * 1.05,
        options: []
    )
    ctx.restoreGState()

    // Sun rim — very faint warm glow just outside the body for separation.
    ctx.setStrokeColor(NSColor(red: 1.0, green: 0.85, blue: 0.55, alpha: 0.45).cgColor)
    ctx.setLineWidth(max(s * 0.003, 1.0))
    ctx.strokeEllipse(in: sunRect)

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
