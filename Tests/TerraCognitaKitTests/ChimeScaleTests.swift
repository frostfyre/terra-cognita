import Testing
@testable import TerraCognitaKit

/// Lock down the pentatonic vocabulary for chime sonification. Type →
/// pitch-class mapping is product-design surface — changing it remaps
/// what the user has learned to associate with each node type, so the
/// table should only move with intent, not by accident.
@Suite("ChimeScale type → MIDI mapping")
struct ChimeScaleTests {

    @Test("concept maps to C in the given octave")
    func conceptIsC() {
        // C5 = MIDI 72; C4 = MIDI 60.
        #expect(ChimeScale.midiNote(forType: "concept", octave: 5) == 72)
        #expect(ChimeScale.midiNote(forType: "concept", octave: 4) == 60)
    }

    @Test("person maps to E (third)")
    func personIsE() {
        // E5 = MIDI 76 (C5 + 4 semitones).
        #expect(ChimeScale.midiNote(forType: "person", octave: 5) == 76)
    }

    @Test("institution maps to G (fifth)")
    func institutionIsG() {
        // G5 = MIDI 79 (C5 + 7 semitones).
        #expect(ChimeScale.midiNote(forType: "institution", octave: 5) == 79)
    }

    @Test("event maps to A (sixth)")
    func eventIsA() {
        // A5 = MIDI 81 (C5 + 9 semitones).
        #expect(ChimeScale.midiNote(forType: "event", octave: 5) == 81)
    }

    @Test("work maps to D (second)")
    func workIsD() {
        // D5 = MIDI 74 (C5 + 2 semitones).
        #expect(ChimeScale.midiNote(forType: "work", octave: 5) == 74)
    }

    @Test("unknown type falls back to C — never silent")
    func unknownIsC() {
        #expect(ChimeScale.midiNote(forType: nil, octave: 5) == 72)
        #expect(ChimeScale.midiNote(forType: "", octave: 5) == 72)
        #expect(ChimeScale.midiNote(forType: "wibble", octave: 5) == 72)
    }

    @Test("type matching is case-insensitive")
    func caseInsensitive() {
        #expect(ChimeScale.midiNote(forType: "Person", octave: 5) == 76)
        #expect(ChimeScale.midiNote(forType: "INSTITUTION", octave: 5) == 79)
    }

    @Test("selection root + pad sit below the chime range")
    func anchorsAreLow() {
        // Foundation = C3 (48), pad = C2 (36). The chime range for
        // connected nodes lives at octave 5 (MIDI 72-81). Both
        // anchors must be well below to keep the chord separated.
        #expect(ChimeScale.selectionRootMIDI == 48)
        #expect(ChimeScale.padMIDI == 36)
        #expect(ChimeScale.selectionRootMIDI < 72)
        #expect(ChimeScale.padMIDI < ChimeScale.selectionRootMIDI)
    }
}
