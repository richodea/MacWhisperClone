import Foundation

// MARK: - Whisper Model

/// Represents a WhisperKit model that can be downloaded and used for transcription.
/// WhisperKit uses CoreML-optimized models hosted on HuggingFace.
struct WhisperModel: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var size: String
    var downloadURL: URL
    var localPath: URL?
    var isDownloaded: Bool
    var isDownloading: Bool
    var downloadProgress: Double
    var parameters: String
    var description: String

    init(
        id: String,
        name: String,
        size: String,
        downloadURL: URL,
        localPath: URL? = nil,
        isDownloaded: Bool = false,
        isDownloading: Bool = false,
        downloadProgress: Double = 0,
        parameters: String,
        description: String
    ) {
        self.id = id
        self.name = name
        self.size = size
        self.downloadURL = downloadURL
        self.localPath = localPath
        self.isDownloaded = isDownloaded
        self.isDownloading = isDownloading
        self.downloadProgress = downloadProgress
        self.parameters = parameters
        self.description = description
    }

    /// All available WhisperKit models from HuggingFace (argmaxinc/whisperkit-coreml)
    static let availableModels: [WhisperModel] = [
        WhisperModel(
            id: "openai_whisper-tiny",
            name: "Tiny",
            size: "~70 MB",
            downloadURL: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml")!,
            parameters: "39M",
            description: "Fastest, lowest accuracy. Good for quick drafts."
        ),
        WhisperModel(
            id: "openai_whisper-tiny.en",
            name: "Tiny (English)",
            size: "~70 MB",
            downloadURL: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml")!,
            parameters: "39M",
            description: "Fastest, English-only. Good for quick drafts."
        ),
        WhisperModel(
            id: "openai_whisper-base",
            name: "Base",
            size: "~140 MB",
            downloadURL: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml")!,
            parameters: "74M",
            description: "Fast, reasonable accuracy for clear audio."
        ),
        WhisperModel(
            id: "openai_whisper-base.en",
            name: "Base (English)",
            size: "~140 MB",
            downloadURL: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml")!,
            parameters: "74M",
            description: "Fast, English-only. Reasonable accuracy."
        ),
        WhisperModel(
            id: "openai_whisper-small",
            name: "Small",
            size: "~460 MB",
            downloadURL: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml")!,
            parameters: "244M",
            description: "Balanced speed and accuracy. Recommended for most use cases."
        ),
        WhisperModel(
            id: "openai_whisper-small.en",
            name: "Small (English)",
            size: "~460 MB",
            downloadURL: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml")!,
            parameters: "244M",
            description: "Balanced, English-only. Recommended for English audio."
        ),
        WhisperModel(
            id: "openai_whisper-medium",
            name: "Medium",
            size: "~1.5 GB",
            downloadURL: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml")!,
            parameters: "769M",
            description: "High accuracy, slower. Good for important transcriptions."
        ),
        WhisperModel(
            id: "openai_whisper-medium.en",
            name: "Medium (English)",
            size: "~1.5 GB",
            downloadURL: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml")!,
            parameters: "769M",
            description: "High accuracy, English-only. Slower."
        ),
        WhisperModel(
            id: "openai_whisper-large-v2",
            name: "Large v2",
            size: "~3.1 GB",
            downloadURL: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml")!,
            parameters: "1550M",
            description: "High accuracy multilingual model."
        ),
        WhisperModel(
            id: "openai_whisper-large-v3",
            name: "Large v3",
            size: "~3.1 GB",
            downloadURL: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml")!,
            parameters: "1550M",
            description: "Best accuracy, slowest. For professional use."
        ),
        WhisperModel(
            id: "openai_whisper-large-v3-turbo",
            name: "Large v3 Turbo",
            size: "~1.5 GB",
            downloadURL: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml")!,
            parameters: "809M",
            description: "Near large-v3 quality at 8x speed. Recommended for best balance."
        ),
        WhisperModel(
            id: "openai_whisper-large-v3-turbo.en",
            name: "Large v3 Turbo (English)",
            size: "~1.5 GB",
            downloadURL: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml")!,
            parameters: "809M",
            description: "Near large-v3 quality, English-only. Fast and accurate."
        ),
        WhisperModel(
            id: "distil-whisper/distil-large-v3",
            name: "Distil Large v3",
            size: "~1.5 GB",
            downloadURL: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml")!,
            parameters: "756M",
            description: "Distilled large-v3. Faster with minimal accuracy loss."
        ),
    ]

    /// Default model for new users
    static let defaultModelID = "openai_whisper-base"
}

// MARK: - Model Download State

/// Tracks the state of a model download operation.
enum ModelDownloadState: Equatable {
    case idle
    case downloading(progress: Double)
    case completed
    case failed(String)
}
