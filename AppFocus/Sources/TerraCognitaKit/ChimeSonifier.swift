import Foundation

/// Composes a chime score for a node selection and dispatches it
/// through `AudioEngine`. Stateless — call `fire(...)` whenever
/// `selectedNodeID` changes to a non-nil value.
///
/// Score shape (from the audio design memo):
///
///   1. **Foundation chime** — one low root tone for the selected
///      node, fires immediately. Anchors the chord.
///   2. **Connected-node chimes** — one per neighbor, pitch from
///      type (`ChimeScale.midiNote`), pan deterministically spread
///      across the stereo field, staggered evenly over
///      `staggerWindow`. Capped at `softCap` to avoid fatigue on
///      Goliath hubs.
///   3. **Overflow pad** — if neighbor count exceeded the cap, one
///      sustained deep-root tone blooms a quarter-window in so the
///      network's bulk is *felt* without adding more chime fatigue.
///
/// Caller doesn't need to pre-sort `connected`; we hash-sort
/// internally for deterministic stagger order. Real screen X comes
/// later when canvas-positions get wired through; for v1 a stable
/// per-id ordering is plenty.
@MainActor
enum ChimeSonifier {
    /// Maximum connected-node chimes per selection. Above this, the
    /// remainder collapse into a single overflow pad.
    static let softCap = 20

    /// Total time over which connected-node chimes stagger, in seconds.
    /// 2 s reads as "wind through the chimes" — slow enough that each
    /// pitch lands distinct, fast enough to register as one event.
    static let staggerWindow: TimeInterval = 2.0

    /// Velocity tiers — kept close together and quiet so the chord
    /// sits as background texture, not as a feature demanding the
    /// user's attention. Tighten/loosen the spread to taste.
    static let foundationVelocity: Float = 0.50
    static let chimeVelocity: Float = 0.40
    static let padVelocity: Float = 0.20

    /// Fire a chime for `selected` and each of its `connected` neighbors.
    /// `enabled` is the per-atlas opt-in flag (`AtlasConfig.audio.chimeEnabled`);
    /// when false this returns before touching the audio engine, so the
    /// system audio session stays untouched until the user opts in for
    /// the active atlas.
    static func fire(selected: Node, connected: [Node], enabled: Bool) {
        guard enabled else { return }

        // 1. Foundation: a single deep root for the selected node,
        //    centered in the mix.
        AudioEngine.shared.schedule(
            midiNote: ChimeScale.selectionRootMIDI,
            velocity: foundationVelocity,
            pan: 0,
            delay: 0
        )

        // Deterministic left-to-right ordering by FNV-1a hash of id.
        // Same selection → same chime sequence, run to run.
        let ordered = connected.sorted { idHash($0.id) < idHash($1.id) }
        let voiced = Array(ordered.prefix(softCap))

        // 2. Connected-node chimes — evenly staggered, pan spread.
        let count = voiced.count
        if count > 0 {
            let step = staggerWindow / TimeInterval(count)
            for (i, node) in voiced.enumerated() {
                let midi = ChimeScale.midiNote(forType: node.type)
                // Pan ∈ [-0.8, 0.8] — leave headroom from hard L/R so
                // AirPods spatial mix has room to breathe.
                let normalized = count > 1 ? (Double(i) / Double(count - 1)) * 2 - 1 : 0
                let pan = Float(normalized * 0.8)
                let delay = step * TimeInterval(i)
                AudioEngine.shared.schedule(
                    midiNote: midi,
                    velocity: chimeVelocity,
                    pan: pan,
                    delay: delay
                )
            }
        }

        // 3. Overflow pad — only when we capped any neighbors.
        if connected.count > softCap {
            AudioEngine.shared.schedule(
                midiNote: ChimeScale.padMIDI,
                velocity: padVelocity,
                pan: 0,
                delay: staggerWindow * 0.25
            )
        }
    }

    /// Single root chime — audio identity signature for the app's
    /// cold-start moment. Fires once when the splash dissolves so
    /// the first thing the user hears is the same root tone that
    /// anchors every subsequent selection chord. No-op when the
    /// per-atlas chime preference is off.
    static func fireLaunchTone(enabled: Bool) {
        guard enabled else { return }
        AudioEngine.shared.schedule(
            midiNote: ChimeScale.selectionRootMIDI,
            velocity: foundationVelocity,
            pan: 0,
            delay: 0
        )
    }

    /// FNV-1a 64-bit. Stable across runs (unlike Swift's hashValue)
    /// so a given graph state always sonifies identically.
    private static func idHash(_ id: String) -> UInt64 {
        var h: UInt64 = 14_695_981_039_346_656_037
        for byte in id.utf8 {
            h ^= UInt64(byte)
            h &*= 1_099_511_628_211
        }
        return h
    }
}

