import Foundation

// MARK: - Export Format

/// Supported export formats for transcription results.
enum ExportFormat: String, CaseIterable, Identifiable {
    case txt = "Plain Text"
    case srt = "SubRip Subtitle"
    case vtt = "WebVTT"
    case json = "JSON"
    case csv = "CSV"
    case whisper = "Whisper Session"

    var id: String { rawValue }

    /// File extension for this format
    var fileExtension: String {
        switch self {
        case .txt: return "txt"
        case .srt: return "srt"
        case .vtt: return "vtt"
        case .json: return "json"
        case .csv: return "csv"
        case .whisper: return "whisper"
        }
    }

    /// UTI type identifier
    var uti: String {
        switch self {
        case .txt: return "public.plain-text"
        case .srt: return "public.srt"
        case .vtt: return "org.webmproject.webvtt"
        case .json: return "public.json"
        case .csv: return "public.comma-separated-values-text"
        case .whisper: return "com.macwhisperclone.whisper"
        }
    }

    var icon: String {
        switch self {
        case .txt: return "doc.text"
        case .srt: return "captions.bubble"
        case .vtt: return "captions.bubble"
        case .json: return "curlybraces"
        case .csv: return "tablecells"
        case .whisper: return "waveform"
        }
    }
}

// MARK: - Transcription Task State

/// The state of a transcription task.
enum TranscriptionTaskState: String, Codable {
    case pending
    case loadingModel
    case processingAudio
    case transcribing
    case postProcessing
    case completed
    case failed
    case cancelled

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .loadingModel: return "Loading Model…"
        case .processingAudio: return "Processing Audio…"
        case .transcribing: return "Transcribing…"
        case .postProcessing: return "Post-Processing…"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    var isRunning: Bool {
        switch self {
        case .pending, .loadingModel, .processingAudio, .transcribing, .postProcessing:
            return true
        default:
            return false
        }
    }
}

// MARK: - Transcription Task

/// A transcription task that tracks the full lifecycle of a transcription operation.
struct TranscriptionTask: Identifiable, Codable {
    let id: UUID
    var audioFile: AudioFile
    var modelID: String
    var engineType: TranscriptionEngineType
    var state: TranscriptionTaskState
    var progress: Double
    var result: TranscriptionResult?
    var errorMessage: String?
    var createdAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        audioFile: AudioFile,
        modelID: String,
        engineType: TranscriptionEngineType,
        state: TranscriptionTaskState = .pending,
        progress: Double = 0,
        result: TranscriptionResult? = nil,
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.audioFile = audioFile
        self.modelID = modelID
        self.engineType = engineType
        self.state = state
        self.progress = progress
        self.result = result
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

// MARK: - Transcription Settings

/// Configuration settings for a transcription operation.
struct TranscriptionSettings: Codable {
    var language: String?           // nil = auto-detect
    var translateToEnglish: Bool    // Translate non-English to English
    var wordTimestamps: Bool        // Include word-level timestamps
    var enableDiarization: Bool     // Speaker identification
    var maxSegmentLength: Int       // Max characters per segment
    var temperature: Float          // Sampling temperature (0 = greedy)
    var speedUp: Bool               // Enable speed-up optimization
    var useMetal: Bool              // Use Metal GPU acceleration

    static let `default` = TranscriptionSettings(
        language: nil,
        translateToEnglish: false,
        wordTimestamps: true,
        enableDiarization: false,
        maxSegmentLength: 0,
        temperature: 0,
        speedUp: false,
        useMetal: true
    )
}
