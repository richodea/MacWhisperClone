import Foundation
import SwiftUI
import AVFoundation

// MARK: - Live Transcription Source

/// The audio source for live transcription.
enum LiveTranscriptionSource: String, CaseIterable, Identifiable {
    case microphone = "Microphone"
    case systemAudio = "System Audio"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .microphone: return "mic.fill"
        case .systemAudio: return "speaker.wave.2.fill"
        }
    }

    var description: String {
        switch self {
        case .microphone: return "Capture audio from your microphone"
        case .systemAudio: return "Capture audio from apps (Zoom, Meet, Teams, etc.)"
        }
    }
}

// MARK: - Live Transcription State

/// The state of a live transcription session.
enum LiveTranscriptionState: String {
    case idle
    case requestingPermission
    case loadingModel
    case listening
    case transcribing
    case stopped
    case error

    var displayName: String {
        switch self {
        case .idle: return "Ready"
        case .requestingPermission: return "Requesting Permission…"
        case .loadingModel: return "Loading Model…"
        case .listening: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .stopped: return "Stopped"
        case .error: return "Error"
        }
    }

    var isActive: Bool {
        switch self {
        case .listening, .transcribing, .loadingModel, .requestingPermission:
            return true
        default:
            return false
        }
    }
}

// MARK: - Live Transcription View Model

/// View model for live (real-time) transcription.
/// Manages audio capture (mic or system), streaming transcription, and state.
@MainActor
final class LiveTranscriptionViewModel: ObservableObject {

    // MARK: Published State

    @Published var state: LiveTranscriptionState = .idle
    @Published var source: LiveTranscriptionSource = .microphone
    @Published var segments: [TranscriptionSegment] = []
    @Published var partialText: String = ""
    @Published var errorMessage: String?
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0

    // MARK: Dependencies

    let modelManager: ModelManager
    let database = DatabaseManager.shared
    private let liveEngine = LiveTranscriptionEngine()
    private let recorder = AudioRecorder()
    private var systemCapture: SystemAudioCapture?

    // MARK: Private

    private var settings = TranscriptionSettings.default
    private var recordingStartTime: Date?
    private var timer: Timer?
    private var levelTimer: Timer?

    // MARK: Initialization

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    // MARK: - Computed Properties

    /// Full transcript text from all segments.
    var fullTranscriptText: String {
        segments.map { $0.text }.joined(separator: " ")
    }

    /// Whether live transcription is currently active.
    var isLive: Bool {
        state.isActive
    }

    // MARK: - Start / Stop

    /// Start live transcription.
    func startLiveTranscription() {
        guard state == .idle || state == .stopped || state == .error else { return }

        errorMessage = nil
        segments.removeAll()
        partialText = ""
        recordingDuration = 0
        liveEngine.reset()

        state = .requestingPermission

        Task {
            await requestPermissionAndStart()
        }
    }

    /// Stop live transcription and save the session.
    func stopLiveTranscription() {
        guard state.isActive else { return }

        // Stop audio capture
        if source == .microphone {
            recorder.stopRecording()
        } else {
            Task {
                await systemCapture?.stopCapture()
            }
        }

        // Stop timers
        timer?.invalidate()
        timer = nil
        levelTimer?.invalidate()
        levelTimer = nil

        // Finalize transcription
        liveEngine.finalize { [weak self] segments, isFinal, text in
            Task { @MainActor in
                guard let self else { return }
                self.segments = segments
                self.partialText = text
                self.state = .stopped

                // Save to database if we have segments
                if !segments.isEmpty {
                    self.saveLiveSession()
                }
            }
        }
    }

    /// Cancel live transcription without saving.
    func cancelLiveTranscription() {
        liveEngine.cancel()

        if source == .microphone {
            recorder.stopRecording()
        } else {
            Task {
                await systemCapture?.stopCapture()
            }
        }

        timer?.invalidate()
        timer = nil
        levelTimer?.invalidate()
        levelTimer = nil

        state = .stopped
    }

    // MARK: - Permission & Start

    private func requestPermissionAndStart() async {
        // Request appropriate permission
        let granted: Bool

        if source == .microphone {
            granted = await AudioRecorder.requestPermission()
        } else {
            if #available(macOS 13.0, *) {
                granted = await SystemAudioCapture.checkPermission()
            } else {
                await MainActor.run {
                    self.errorMessage = "System audio capture requires macOS 13.0 or later"
                    self.state = .error
                }
                return
            }
        }

        guard granted else {
            await MainActor.run {
                self.errorMessage = "Permission denied. Please grant access in System Settings > Privacy & Security."
                self.state = .error
            }
            return
        }

        // Load model
        await MainActor.run {
            self.state = .loadingModel
        }

        let modelID = modelManager.selectedModelID
        do {
            try await liveEngine.loadModel(modelID)
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load model: \(error.localizedDescription)"
                self.state = .error
            }
            return
        }

        // Start audio capture
        await MainActor.run {
            self.startAudioCapture()
        }
    }

    // MARK: - Audio Capture

    private func startAudioCapture() {
        recordingStartTime = Date()
        state = .listening

        // Start duration timer
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }

        // Start audio level monitoring
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                // Simulate audio level (would need actual metering from AVAudioEngine)
                self?.updateAudioLevel()
            }
        }

        // Start recording based on source
        if source == .microphone {
            startMicrophoneCapture()
        } else {
            startSystemAudioCapture()
        }
    }

    private func startMicrophoneCapture() {
        do {
            try recorder.startRecording { [weak self] samples, timestamp in
                guard let self else { return }
                self.handleAudioChunk(samples: samples, timestamp: timestamp)
            }
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            state = .error
        }
    }

    private func startSystemAudioCapture() {
        guard #available(macOS 13.0, *) else {
            errorMessage = "System audio capture requires macOS 13.0 or later"
            state = .error
            return
        }

        let capture = SystemAudioCapture()
        systemCapture = capture

        Task {
            do {
                try await capture.startCapture { [weak self] samples, timestamp in
                    guard let self else { return }
                    self.handleAudioChunk(samples: samples, timestamp: timestamp)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to capture system audio: \(error.localizedDescription)"
                    self.state = .error
                }
            }
        }
    }

    // MARK: - Chunk Handling

    private func handleAudioChunk(samples: [Float], timestamp: TimeInterval) {
        guard state.isActive else { return }

        // Update state to transcribing
        Task { @MainActor in
            if self.state == .listening {
                self.state = .transcribing
            }
        }

        // Transcribe the chunk
        liveEngine.transcribeChunk(
            samples: samples,
            timestamp: timestamp,
            settings: settings
        ) { [weak self] segments, isFinal, partialText in
            Task { @MainActor in
                guard let self else { return }
                self.segments = segments
                self.partialText = partialText

                // Return to listening state after transcription
                if !isFinal && self.state == .transcribing {
                    self.state = .listening
                }
            }
        }
    }

    // MARK: - Audio Level

    private func updateAudioLevel() {
        // Simple audio level simulation based on recorder state
        if recorder.isRecording {
            // In a real implementation, we'd read the actual audio level from the engine
            audioLevel = Float.random(in: 0.1...0.4)
        } else {
            audioLevel = 0
        }
    }

    // MARK: - Save Session

    private func saveLiveSession() {
        guard !segments.isEmpty else { return }

        // Create a virtual audio file for the live session
        let audioFile = AudioFile(
            url: URL(fileURLWithPath: "/dev/null"),
            name: "Live Transcription - \(Date().formatted(date: .abbreviated, time: .shortened))",
            duration: recordingDuration,
            sampleRate: 16000,
            channels: 1
        )

        let result = TranscriptionResult(
            segments: segments,
            detectedLanguage: settings.language ?? "auto",
            modelUsed: modelManager.selectedModelID,
            engineUsed: .whisperKit,
            processingTime: recordingDuration,
            audioDuration: recordingDuration
        )

        do {
            _ = try database.saveSession(audioFile: audioFile, result: result)
            Logger.info("Live transcription session saved (\(segments.count) segments)")
        } catch {
            Logger.error("Failed to save live session: \(error.localizedDescription)")
        }
    }

    // MARK: - Settings

    /// Update transcription settings.
    func updateSettings(_ newSettings: TranscriptionSettings) {
        settings = newSettings
    }

    /// Update the audio source.
    func setSource(_ newSource: LiveTranscriptionSource) {
        guard !state.isActive else { return }
        source = newSource
    }

    // MARK: - Export

    /// Export the live transcript to a file.
    func exportTranscript(format: ExportFormat) throws -> URL {
        let result = TranscriptionResult(
            segments: segments,
            detectedLanguage: settings.language ?? "auto",
            modelUsed: modelManager.selectedModelID,
            engineUsed: .whisperKit,
            processingTime: recordingDuration,
            audioDuration: recordingDuration
        )

        let fileName = "Live Transcription - \(Date().formatted(date: .abbreviated, time: .shortened))"

        return try TranscriptExporter.exportToFile(
            result,
            to: format,
            fileName: fileName
        )
    }
}
