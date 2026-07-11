// shotkit — tiny CLI for driving app-window screenshots.
//   shotkit info                       → "windowID x y w h" of the app's main window
//   shotkit press <x> <y> <holdMs>     → synthetic left mouse press-hold-release (global coords)
//   shotkit click <x> <y>              → quick click
//   shotkit flatten <in> <out> <W> <H> <rrggbb> → center image on opaque canvas, strip alpha
import AppKit
import CoreGraphics

let args = CommandLine.arguments

func mainWindow() -> (CGWindowID, CGRect)? {
    let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return nil }
    var best: (CGWindowID, CGRect)? = nil
    for w in list {
        guard let owner = w[kCGWindowOwnerName as String] as? String,
              owner.hasPrefix("Terra Cognita"),
              (w[kCGWindowLayer as String] as? Int) == 0,
              let num = w[kCGWindowNumber as String] as? UInt32,
              let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
        let frame = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        // pick the largest window (skips tooltips/panels)
        if best == nil || frame.width * frame.height > best!.1.width * best!.1.height {
            best = (num, frame)
        }
    }
    return best
}

func post(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p,
            mouseButton: .left)?.post(tap: .cghidEventTap)
}

switch args.count > 1 ? args[1] : "" {
case "info":
    guard let (id, f) = mainWindow() else { fputs("no window\n", stderr); exit(1) }
    print("\(id) \(Int(f.origin.x)) \(Int(f.origin.y)) \(Int(f.width)) \(Int(f.height))")
case "press":
    let p = CGPoint(x: Double(args[2])!, y: Double(args[3])!)
    let hold = UInt32(args[4])! * 1000
    post(.mouseMoved, p)
    usleep(80_000)
    post(.leftMouseDown, p)
    usleep(hold)
    post(.leftMouseUp, p)
case "click":
    let p = CGPoint(x: Double(args[2])!, y: Double(args[3])!)
    post(.mouseMoved, p); usleep(60_000)
    post(.leftMouseDown, p); usleep(90_000)
    post(.leftMouseUp, p)
case "flatten":
    let inURL = URL(fileURLWithPath: args[2]), outURL = URL(fileURLWithPath: args[3])
    let W = Int(args[4])!, H = Int(args[5])!
    let hex = UInt32(args[6], radix: 16)!
    guard let src = NSImage(contentsOf: inURL),
          let srcRep = src.representations.first as? NSBitmapImageRep else {
        fputs("cannot read \(args[2])\n", stderr); exit(1)
    }
    let sw = srcRep.pixelsWide, sh = srcRep.pixelsHigh
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(red: CGFloat((hex >> 16) & 0xff) / 255,
                             green: CGFloat((hex >> 8) & 0xff) / 255,
                             blue: CGFloat(hex & 0xff) / 255, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    // cover: scale to fill the canvas, center-cropping any overshoot
    var dw = CGFloat(sw), dh = CGFloat(sh)
    let scale = max(CGFloat(W) / dw, CGFloat(H) / dh)
    dw *= scale; dh *= scale
    let origin = CGPoint(x: (CGFloat(W) - dw) / 2, y: (CGFloat(H) - dh) / 2)
    ctx.interpolationQuality = .high
    ctx.draw(srcRep.cgImage!, in: CGRect(origin: origin, size: CGSize(width: dw, height: dh)))
    let out = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! out.representation(using: .png, properties: [:])!.write(to: outURL)
    print("flattened \(sw)x\(sh) → \(W)x\(H)")
case "patch":
    // patch <in> <out> <x> <y> <w> <h> <dx> <dy> — overwrite rect with pixels copied from (x+dx, y+dy)
    let inURL = URL(fileURLWithPath: args[2]), outURL = URL(fileURLWithPath: args[3])
    let x = Int(args[4])!, y = Int(args[5])!, w = Int(args[6])!, h = Int(args[7])!
    let dx = Int(args[8])!, dy = Int(args[9])!
    guard let src = NSImage(contentsOf: inURL),
          let rep = src.representations.first as? NSBitmapImageRep,
          let cg = rep.cgImage else { fputs("cannot read\n", stderr); exit(1) }
    let W = rep.pixelsWide, H = rep.pixelsHigh
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
    // crop the donor region (top-left coords) and draw it over the target rect
    if let donor = cg.cropping(to: CGRect(x: x + dx, y: y + dy, width: w, height: h)) {
        ctx.draw(donor, in: CGRect(x: CGFloat(x), y: CGFloat(H - y - h), width: CGFloat(w), height: CGFloat(h)))
    }
    let out = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! out.representation(using: .png, properties: [:])!.write(to: outURL)
    print("patched \(w)x\(h) at (\(x),\(y))")
default:
    fputs("usage: shotkit info|press|click|flatten|patch …\n", stderr); exit(64)
}
