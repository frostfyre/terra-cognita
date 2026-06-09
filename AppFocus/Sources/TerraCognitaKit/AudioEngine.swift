import Foundation
import AVFoundation

/// Process-wide audio engine for the chime sonifier. One `AVAudioEngine`
/// + a pool of `AVAudioPlayerNode`s, each fed pre-rendered procedural
/// chime buffers (sine fundamental + harmonics + exponential decay
/// envelope). Procedural so we ship without external sample assets;
/// real sampled instruments (singing bowls / glass / prepared piano
/// per the audio design memo) can swap in later by replacing
/// `makeChimeBuffer` with sample-file loads.
///
/// Lifecycle is **lazy**: the engine + iOS `AVAudioSession` don't
/// activate until the first chime is scheduled, honoring the
/// "don't grab audio silently" promise. Caller never has to call
/// `startIfNeeded()` — `schedule(...)` does it on demand.
@MainActor
final class AudioEngine {
    static let shared = AudioEngine()

    /// Pool of player nodes — one chime at a time per player, cycled
    /// round-robin. Sized a little above the chime soft cap so we
    /// don't reuse mid-decay players during a single selection's
    /// stagger window.
    private static let poolSize = 24

    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private var playerPool: [AVAudioPlayerNode] = []
    private var poolIndex = 0
    private var bufferCache: [Int: AVAudioPCMBuffer] = [:]
    private var isStarted = false

    private init() {
        // 44.1 kHz stereo float — plenty for chime content, and the
        // engine resamples to the device's output rate cheaply.
        format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let mixer = engine.mainMixerNode
        for _ in 0..<Self.poolSize {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: mixer, format: format)
            playerPool.append(player)
        }
    }

    /// Schedule a chime to ring at `delay` seconds from now, panned
    /// to `pan` (-1 = hard left, 1 = hard right) at `velocity` (0..1).
    /// First call activates the engine + session.
    func schedule(midiNote: Int, velocity: Float, pan: Float, delay: TimeInterval) {
        if delay > 0 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.fireNow(midiNote: midiNote, velocity: velocity, pan: pan)
            }
        } else {
            fireNow(midiNote: midiNote, velocity: velocity, pan: pan)
        }
    }

    private func fireNow(midiNote: Int, velocity: Float, pan: Float) {
        startIfNeeded()
        guard isStarted, let buffer = buffer(for: midiNote) else { return }
        let player = checkOutPlayer()
        player.pan = pan
        player.volume = velocity
        // `.interrupts` so a reused player cuts off any in-flight chime
        // cleanly instead of queueing — the pool is sized to avoid this
        // in normal use, but on a Goliath-hub selection it keeps the
        // tail clean.
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func startIfNeeded() {
        guard !isStarted else { return }
        configureSession()
        do {
            try engine.start()
            isStarted = true
        } catch {
            // Audio is a polish feature — never block the app. The
            // engine stays un-started; subsequent schedules will retry
            // on next selection.
        }
    }

    private func configureSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        // `.ambient` + `mixWithOthers` so we coexist with whatever the
        // user is already playing (Spotify, podcast, etc.) instead of
        // ducking or interrupting it. This is the "don't grab audio
        // silently" promise from the design memo.
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
    }

    private func checkOutPlayer() -> AVAudioPlayerNode {
        let player = playerPool[poolIndex]
        poolIndex = (poolIndex + 1) % Self.poolSize
        return player
    }

    private func buffer(for midiNote: Int) -> AVAudioPCMBuffer? {
        if let cached = bufferCache[midiNote] { return cached }
        guard let buffer = makeChimeBuffer(midiNote: midiNote) else { return nil }
        bufferCache[midiNote] = buffer
        return buffer
    }

    /// Procedural wind-chime tone: soft tinkle attack, long gentle
    /// decay, harmonic stack with slight inharmonicity that gives
    /// real bells / chimes their glassy character (perfectly integer
    /// partials sound synthetic — small offsets read as "physical").
    /// Cached per-pitch so we only render each MIDI note once.
    private func makeChimeBuffer(midiNote: Int) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let duration: Double = 4.0  // long ring-out — wind chimes don't snap off
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        let freq = midiNoteToFrequency(midiNote)
        let attack = 0.025   // 25 ms — soft tinkle, not a strike
        let decay = 2.6      // 2.6 s exponential — sits in the background, drifts out

        // 5-partial stack with gentle taper toward the upper harmonics
        // and small inharmonic offsets (1.0, 2.01, 3.04, 4.07, 5.11)
        // that give the tone its glassy, slightly-detuned character.
        // Volume halved from the previous synth bell so it sits as
        // texture rather than feature.
        let partials: [(ratio: Double, weight: Double)] = [
            (1.00, 1.00),
            (2.01, 0.35),
            (3.04, 0.18),
            (4.07, 0.08),
            (5.11, 0.04),
        ]
        let weightSum = partials.map(\.weight).reduce(0, +)
        let headroom = 0.18

        guard let channels = buffer.floatChannelData else { return nil }
        let channelCount = Int(format.channelCount)
        for ch in 0..<channelCount {
            let ptr = channels[ch]
            for n in 0..<Int(frameCount) {
                let t = Double(n) / sampleRate
                let env: Double = t < attack ? (t / attack) : exp(-(t - attack) / decay)
                var s = 0.0
                for partial in partials {
                    s += sin(2 * .pi * freq * partial.ratio * t) * partial.weight
                }
                ptr[n] = Float(env * (s / weightSum) * headroom)
            }
        }
        return buffer
    }

    private func midiNoteToFrequency(_ midi: Int) -> Double {
        440.0 * pow(2.0, Double(midi - 69) / 12.0)
    }
}
