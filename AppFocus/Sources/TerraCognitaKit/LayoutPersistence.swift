import Foundation
import CoreGraphics

/// Snapshot of the canvas view state that survives across launches.
///
/// We persist three things:
///   - The force-directed layout result (so the second launch doesn't have
///     to recompute it and the graph reads the same)
///   - Manually pinned node positions (the user's deliberate placements)
///   - Scale + offset (so the user returns to where they were looking)
struct PersistedLayout: Codable, Equatable {
    var positions: [String: Point] = [:]
    var pinned: [String: Point] = [:]
    var scale: Double = 1
    var offsetX: Double = 0
    var offsetY: Double = 0

    struct Point: Codable, Equatable {
        var x: Double
        var y: Double
        init(_ p: CGPoint) {
            self.x = Double(p.x); self.y = Double(p.y)
        }
        var cg: CGPoint { CGPoint(x: x, y: y) }
    }

    var cgPositions: [String: CGPoint] {
        positions.mapValues(\.cg)
    }

    var cgPinned: [String: CGPoint] {
        pinned.mapValues(\.cg)
    }
}

/// File-backed load/save for `PersistedLayout`. Stored at
/// `~/Library/Application Support/AppFocus/layout.json` — directory
/// name kept at the original "AppFocus" so existing user layouts
/// survive the project rename to Terra Cognita.
enum LayoutPersistence {
    private static var fileURL: URL? {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dir = appSupport.appendingPathComponent("AppFocus", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("layout.json")
    }

    static func load() -> PersistedLayout? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PersistedLayout.self, from: data)
    }

    static func save(_ snapshot: PersistedLayout) {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    static func clear() {
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
    }
}
