import Foundation

// MARK: - Transcription Engine Protocol

/// Protocol defining the interface for all transcription engines (local and cloud).
protocol TranscriptionEngine: AnyObject {
    /// The type of this engine
    var engineType: TranscriptionEngineType { get }

    /// Whether this engine is ready to transcribe (model loaded, API key set, etc.)
    var isReady: Bool { get }

    /// Transcribe audio data, calling progress and completion handlers.
    /// - Parameters:
    ///   - audioData: PCM 16-bit mono audio samples at 16kHz
    ///   - settings: Transcription configuration
    ///   - progressHandler: Called with progress 0.0–1.0 and optional partial segments
    ///   - completion: Called with the final result or error
    func transcribe(
        audioData: [Float],
        settings: TranscriptionSettings,
        progressHandler: @escaping (Double, [TranscriptionSegment]?) -> Void,
        completion: @escaping (Result<TranscriptionResult, TranscriptionError>) -> Void
    )

    /// Cancel an in-progress transcription
    func cancel()

    /// Prepare the engine (load model, validate API key, etc.)
    func prepare() async throws
}

// MARK: - Transcription Error

/// Errors that can occur during transcription.
enum TranscriptionError: LocalizedError {
    case modelNotDownloaded(String)
    case modelLoadFailed(String)
    case audioProcessingFailed(String)
    case transcriptionFailed(String)
    case apiError(String)
    case invalidAPIKey
    case networkError(String)
    case cancelled
    case unsupportedFormat(String)
    case fileNotFound(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded(let model):
            return "Model '\(model)' has not been downloaded. Please download it first."
        case .modelLoadFailed(let detail):
            return "Failed to load model: \(detail)"
        case .audioProcessingFailed(let detail):
            return "Audio processing failed: \(detail)"
        case .transcriptionFailed(let detail):
            return "Transcription failed: \(detail)"
        case .apiError(let detail):
            return "API error: \(detail)"
        case .invalidAPIKey:
            return "Invalid or missing API key. Please configure it in Settings."
        case .networkError(let detail):
            return "Network error: \(detail)"
        case .cancelled:
            return "Transcription was cancelled."
        case .unsupportedFormat(let format):
            return "Unsupported audio format: \(format)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .unknown(let detail):
            return "An unknown error occurred: \(detail)"
        }
    }
}

// MARK: - Transcription Progress Update

/// Progress updates emitted during transcription.
enum TranscriptionProgress {
    case loadingModel
    case processingAudio
    case transcribing(progress: Double, segments: [TranscriptionSegment]?)
    case postProcessing
    case completed(TranscriptionResult)
    case failed(TranscriptionError)
}
