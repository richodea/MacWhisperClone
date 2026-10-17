import Foundation
import AVFoundation
import WhisperKit

// MARK: - WhisperKit Engine

/// Local transcription engine using WhisperKit (Apple Silicon native).
/// WhisperKit uses CoreML models optimized for Apple Silicon with Metal GPU acceleration.
/// This replaces the previous whisper.cpp / Apple Speech framework implementation.
final class WhisperKitEngine: TranscriptionEngine {

    // MARK: Properties

    let engineType: TranscriptionEngineType = .whisperKit

    private var currentModelID: String?
    private var whisperKit: WhisperKit?
    private var isCancelled = false

    var isReady: Bool {
        currentModelID != nil
    }

    // MARK: Initialization

    init() {}

    deinit {
        cancel()
    }

    // MARK: - TranscriptionEngine Protocol

    func prepare() async throws {
        // WhisperKit does not require special authorization.
        // Model loading happens lazily during transcription.
    }

    func transcribe(
        audioData: [Float],
        settings: TranscriptionSettings,
        progressHandler: @escaping (Double, [TranscriptionSegment]?) -> Void,
        completion: @escaping (Result<TranscriptionResult, TranscriptionError>) -> Void
    ) {
        isCancelled = false

        let modelID = currentModelID
        let audioDuration = Double(audioData.count) / 16000.0

        Task {
            let startTime = Date()

            do {
                // Validate model ID
                guard let modelID else {
                    await MainActor.run {
                        completion(.failure(.modelNotDownloaded("No model selected")))
                    }
                    return
                }

                // Initialize WhisperKit if needed (downloads model on first use)
                if self.whisperKit == nil {
                    await MainActor.run {
                        progressHandler(0.05, nil)
                    }

                    Logger.info("Loading WhisperKit model: \(modelID)")
                    self.whisperKit = try await WhisperKit(
                        model: modelID,
                        downloadBase: AppPaths.modelsDirectory
                    )
                }

                guard let whisperKit = self.whisperKit else {
                    await MainActor.run {
                        completion(.failure(.modelLoadFailed("Failed to initialize WhisperKit")))
                    }
                    return
                }

                if self.isCancelled {
                    await MainActor.run {
                        completion(.failure(.cancelled))
                    }
                    return
                }

                // Write float samples to a temp WAV file (WhisperKit reads from file path)
                await MainActor.run {
                    progressHandler(0.1, nil)
                }

                let tempURL = AppPaths.cacheDirectory.appendingPathComponent("temp_audio_\(UUID().uuidString).wav")
                let wavData = AudioProcessor.convertFloatSamplesToWAV(audioData)
                try wavData.write(to: tempURL)

                defer {
                    try? FileManager.default.removeItem(at: tempURL)
                }

                Logger.info("Starting WhisperKit transcription of \(audioData.count) samples")

                // Build decoding options
                let language = settings.language?.isEmpty == false ? settings.language : nil
                let task: DecodingTask = settings.translateToEnglish ? .translate : .transcribe

                let decodeOptions = DecodingOptions(
                    task: task,
                    language: language,
                    temperature: settings.temperature,
                    detectLanguage: language == nil,
                    wordTimestamps: settings.wordTimestamps
                )

                await MainActor.run {
                    progressHandler(0.15, nil)
                }

                // Transcribe - returns array of WhisperKit TranscriptionResult
                let results = try await whisperKit.transcribe(
                    audioPath: tempURL.path,
                    decodeOptions: decodeOptions
                )

                if self.isCancelled {
                    await MainActor.run {
                        completion(.failure(.cancelled))
                    }
                    return
                }

                // Get the first result (single file transcription)
                guard let wkResult = results.first else {
                    await MainActor.run {
                        completion(.failure(.transcriptionFailed("No transcription result returned")))
                    }
                    return
                }

                // Convert WhisperKit segments to our TranscriptionSegment
                let segments: [TranscriptionSegment] = wkResult.segments.enumerated().map { index, segment in
                    let words: [TranscriptionWord]? = segment.words?.map { wt in
                        TranscriptionWord(
                            word: wt.word,
                            startTime: TimeInterval(wt.start),
                            endTime: TimeInterval(wt.end),
                            probability: wt.probability
                        )
                    }

                    return TranscriptionSegment(
                        index: index,
                        startTime: TimeInterval(segment.start),
                        endTime: TimeInterval(segment.end),
                        text: segment.text,
                        words: words
                    )
                }

                let processingTime = Date().timeIntervalSince(startTime)

                let transcriptionResult = TranscriptionResult(
                    segments: segments,
                    detectedLanguage: wkResult.language,
                    modelUsed: modelID,
                    engineUsed: .whisperKit,
                    processingTime: processingTime,
                    audioDuration: audioDuration
                )

                Logger.info("WhisperKit transcription completed in \(TimeFormatter.formatDuration(processingTime)), \(segments.count) segments")

                await MainActor.run {
                    progressHandler(1.0, segments)
                    completion(.success(transcriptionResult))
                }

            } catch {
                Logger.error("WhisperKit transcription failed: \(error.localizedDescription)")
                await MainActor.run {
                    completion(.failure(.transcriptionFailed(error.localizedDescription)))
                }
            }
        }
    }

    func cancel() {
        isCancelled = true
        Logger.info("WhisperKit transcription cancelled")
    }

    // MARK: - Language Detection

    /// Detect the spoken language of an audio file using WhisperKit.
    /// Requires a multilingual model (e.g., "openai_whisper-large-v3", not ".en" variants).
    /// - Parameter audioData: PCM float samples at 16kHz.
    /// - Returns: The detected language code (e.g., "en", "id") and probability distribution.
    func detectLanguage(
        audioData: [Float]
    ) async throws -> (language: String, probabilities: [String: Float]) {
        guard let modelID = currentModelID else {
            throw TranscriptionError.modelNotDownloaded("No model selected")
        }

        // Initialize WhisperKit if needed
        if self.whisperKit == nil {
            Logger.info("Loading WhisperKit model for language detection: \(modelID)")
            self.whisperKit = try await WhisperKit(
                model: modelID,
                downloadBase: AppPaths.modelsDirectory
            )
        }

        guard let whisperKit = self.whisperKit else {
            throw TranscriptionError.modelLoadFailed("Failed to initialize WhisperKit")
        }

        // Write samples to temp WAV (detectLanguage takes a file path)
        let tempURL = AppPaths.cacheDirectory.appendingPathComponent("lang_detect_\(UUID().uuidString).wav")
        let wavData = AudioProcessor.convertFloatSamplesToWAV(audioData)
        try wavData.write(to: tempURL)

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        Logger.info("Detecting language from \(audioData.count) samples")
        let result = try await LanguageDetector.detect(
            audioPath: tempURL.path,
            whisperKit: whisperKit
        )

        let displayName = LanguageDetector.displayName(for: result.language)
        Logger.info("Detected language: \(displayName) (\(result.language))")

        return result
    }

    // MARK: - Model Management

    /// Set the model to use for transcription.
    /// The actual model is loaded lazily on first transcription.
    /// - Parameter modelID: The WhisperKit model variant (e.g., "openai_whisper-tiny")
    func loadModel(_ modelID: String) throws {
        if currentModelID != modelID {
            currentModelID = modelID
            whisperKit = nil  // Force re-initialization with new model
            Logger.info("Model selected: \(modelID)")
        }
    }
}
