import Foundation

/// Pentatonic-mapped scoring for the chime sonifier.
///
/// Pentatonic C major (C-D-E-G-A) is the safe scale for graph
/// sonification — every interval inside it is consonant, so any
/// random subset of node types ringing together sounds intentional.
/// Each node type maps to one pitch class as its "voice," so over
/// time a listener learns the vocabulary by ear:
///
///   * concept     → C  (root)
///   * person      → E  (third)
///   * institution → G  (fifth)
///   * event       → A  (sixth)
///   * work        → D  (second)
///   * unknown     → C  (falls back to root, never silent)
///
/// Octave is a parameter so the *connected*-node chimes can sit in
/// the C5-A5 range while the *selected*-node foundation tone sits an
/// octave or two lower for separation.
enum ChimeScale {
    /// MIDI note for the given node type at the given octave.
    /// `octave` follows scientific notation: C4 = middle C = MIDI 60.
    static func midiNote(forType type: String?, octave: Int = 5) -> Int {
        let pitchClass: Int
        switch type?.lowercased() {
        case "concept":     pitchClass = 0   // C
        case "person":      pitchClass = 4   // E
        case "institution": pitchClass = 7   // G
        case "event":       pitchClass = 9   // A
        case "work":        pitchClass = 2   // D
        default:            pitchClass = 0   // C — unknown types fall to root
        }
        // MIDI: C-1 = 0, so C(n) = 12 * (n + 1).
        return 12 * (octave + 1) + pitchClass
    }

    /// Foundation tone for the *selected* node — a low root that
    /// anchors the chord under the connected-node chimes. C3 = MIDI 48
    /// sits well below the C5-A5 chime range.
    static let selectionRootMIDI: Int = 48

    /// Overflow pad note when the connected count exceeds the soft
    /// cap. A deep, slow-decay root reinforces "the network extends
    /// past what you can hear individually" without adding more
    /// pitches that fight the chord. C2 = MIDI 36.
    static let padMIDI: Int = 36
}
