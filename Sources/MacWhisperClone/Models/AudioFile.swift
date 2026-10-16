import Foundation

// MARK: - Audio File

/// Represents an audio file that can be transcribed.
struct AudioFile: Identifiable, Codable, Hashable {
    let id: UUID
    var url: URL
    var name: String
    var fileExtension: String
    var fileSize: Int64
    var duration: TimeInterval?
    var sampleRate: Double?
    var channels: Int?

    init(
        id: UUID = UUID(),
        url: URL,
        name: String? = nil,
        fileExtension: String? = nil,
        fileSize: Int64? = nil,
        duration: TimeInterval? = nil,
        sampleRate: Double? = nil,
        channels: Int? = nil
    ) {
        self.id = id
        self.url = url
        self.name = name ?? url.deletingPathExtension().lastPathComponent
        self.fileExtension = fileExtension ?? url.pathExtension
        self.fileSize = fileSize ?? (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        self.duration = duration
        self.sampleRate = sampleRate
        self.channels = channels
    }

    /// Supported audio file extensions
    static let supportedExtensions: Set<String> = [
        "wav", "mp3", "m4a", "aiff", "aif",
        "caf", "ogg", "mp4", "mov", "m4v",
        "flac", "aac"
    ]

    /// Check if a URL points to a supported audio file
    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Formatted file size (e.g., "12.3 MB")
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    /// Formatted duration (e.g., "1:23")
    var formattedDuration: String {
        guard let duration else { return "--:--" }
        return TimeFormatter.formatDuration(duration)
    }
}

// MARK: - Audio Source

/// The source of audio input for transcription.
enum AudioSource: Codable, Hashable {
    case file(AudioFile)
    case microphone
    case systemAudio
    case youtube(URL)
}

// MARK: - Transcription Engine Type

/// Identifies which transcription engine was used.
enum TranscriptionEngineType: String, Codable, CaseIterable {
    case whisperCPP = "whisper.cpp"
    case whisperKit = "WhisperKit"
    case openAI = "OpenAI Whisper API"
    case groq = "Groq Whisper"
    case assemblyAI = "AssemblyAI"
    case deepgram = "Deepgram"
    case revAI = "RevAI"
    case speechmatics = "Speechmatics"
    case gladia = "Gladia"
    case corti = "Corti"
    case voxtral = "Voxtral"
    case argmax = "Argmax"
    case volcengine = "Volcengine"

    var displayName: String {
        rawValue
    }

    var isLocal: Bool {
        switch self {
        case .whisperCPP, .whisperKit:
            return true
        default:
            return false
        }
    }

    var requiresAPIKey: Bool {
        !isLocal
    }
}
