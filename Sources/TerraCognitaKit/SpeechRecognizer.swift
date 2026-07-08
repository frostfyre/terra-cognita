import Foundation
#if canImport(Speech)
import Speech
import AVFoundation
#endif

/// On-device speech-to-text wrapper for the Capture flow.
///
/// Always opts into `requiresOnDeviceRecognition = true` — the heritage
/// atlas is personal data, so audio never leaves the device. Streams
/// partial transcripts as the user speaks so the UI can render them
/// live.
///
/// Gated on `canImport(Speech)` (the SwiftPM exec on a stripped-down
/// macOS may not link the framework) and `@available(macOS 26, iOS 26,
/// *)` because the on-device recognizer's reliability on older OSes is
/// inconsistent.
@MainActor
final class SpeechRecognizer: ObservableObject {

    enum AvailabilityState: Equatable {
        case ready
        case awaitingPermission
        case denied(String)
        case unsupported(String)
    }

    @Published private(set) var transcript: String = ""
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var availability: AvailabilityState = .unsupported(
        "Voice capture requires macOS 26 or iOS 26."
    )

    /// Refresh permission + recognizer state. Call once before recording.
    func prepare() async {
        #if canImport(Speech)
        if #available(macOS 26, iOS 26, *) {
            await refreshAvailability()
        }
        #endif
    }

    /// Start streaming partial transcripts into `transcript`. No-op if
    /// the recognizer isn't ready.
    func start() {
        #if canImport(Speech)
        if #available(macOS 26, iOS 26, *) {
            startInternal()
        }
        #endif
    }

    /// Stop the recording session and finalize the transcript.
    func stop() {
        #if canImport(Speech)
        if #available(macOS 26, iOS 26, *) {
            stopInternal()
        }
        #endif
    }

    /// Reset the transcript (e.g. when the Capture sheet opens fresh).
    func clear() {
        transcript = ""
    }

    // MARK: - Speech-framework backing

    #if canImport(Speech)
    private let recognizer = SFSpeechRecognizer(locale: .current)
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    @available(macOS 26, iOS 26, *)
    private func refreshAvailability() async {
        guard let recognizer, recognizer.isAvailable else {
            availability = .unsupported("Speech recognizer not available on this device.")
            return
        }
        // Per-app speech permission. The callback fires on a background
        // queue, so the closure must be `@Sendable` — without that it
        // inherits `@MainActor` from this function and trips the Swift
        // 6 isolation assert.
        let speechStatus = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                cont.resume(returning: status)
            }
        }
        switch speechStatus {
        case .authorized: break
        case .denied:     availability = .denied("Speech recognition is denied. Enable it in Settings.");       return
        case .restricted: availability = .denied("Speech recognition is restricted on this device.");           return
        case .notDetermined: availability = .awaitingPermission; return
        @unknown default:    availability = .denied("Unknown speech-permission status."); return
        }
        // Microphone permission.
        let micGranted = await requestMicrophonePermission()
        guard micGranted else {
            availability = .denied("Microphone access is denied. Enable it in Settings.")
            return
        }
        availability = .ready
    }

    @available(macOS 26, iOS 26, *)
    private func requestMicrophonePermission() async -> Bool {
        #if os(iOS)
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { @Sendable granted in
                cont.resume(returning: granted)
            }
        }
        #else
        // macOS — AVCaptureDevice authorization.
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized: return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
        #endif
    }

    @available(macOS 26, iOS 26, *)
    private func startInternal() {
        guard availability == .ready, let recognizer, !isRecording else { return }

        // Reconfigure the audio session each recording (iOS) — keeps
        // playback from other apps unaffected after we stop.
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true
        self.request = req

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        // Capture `req` directly + mark the closure @Sendable so it
        // doesn't inherit @MainActor isolation from this function —
        // the audio engine fires the callback on its own real-time
        // thread, which trips Swift 6's isolation assert otherwise.
        // `SFSpeechAudioBufferRecognitionRequest.append(_:)` is
        // documented as thread-safe.
        nonisolated(unsafe) let request = req
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            availability = .denied("Couldn't start audio engine: \(error.localizedDescription)")
            return
        }

        isRecording = true
        // The recognitionTask callback also fires off-main; hop back to
        // the main actor explicitly before touching @Published state.
        task = recognizer.recognitionTask(with: req) { @Sendable [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let hasError = error != nil
            Task { @MainActor [weak self] in
                if let transcript { self?.transcript = transcript }
                if hasError || isFinal { self?.cleanupTask() }
            }
        }
    }

    @available(macOS 26, iOS 26, *)
    private func stopInternal() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        // The task's completion handler will drive cleanupTask() and
        // flip isRecording = false once SFSpeechRecognizer finalizes.
        isRecording = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func cleanupTask() {
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
    }
    #endif
}
