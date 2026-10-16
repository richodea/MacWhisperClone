import Foundation
import WhisperKit

// MARK: - Live Transcription Engine

/// Handles streaming transcription by processing audio chunks sequentially.
/// Each chunk is transcribed independently and results are merged into a
/// continuous transcript with proper timestamp offsets.
///
/// This engine maintains a persistent WhisperKit instance for low-latency
/// repeated transcription (model stays loaded between chunks).
final class LiveTranscriptionEngine {

    // MARK: Types

    /// Called whenever new transcription segments are available.
    /// - Parameters:
    ///   - segments: Newly transcribed segments (with absolute timestamps)
    ///   - isFinal: Whether this is the final update (recording stopped)
    ///   - partialText: The current partial text being transcribed
    typealias ResultHandler = (
        _ segments: [TranscriptionSegment],
        _ isFinal: Bool,
        _ partialText: String
    ) -> Void

    // MARK: Properties

    private var whisperKit: WhisperKit?
    private var modelID: String?
    private var isCancelled = false

    /// Offset to add to segment timestamps (accumulated from previous chunks)
    private var timeOffset: TimeInterval = 0

    /// All confirmed segments across all chunks
    private var allSegments: [TranscriptionSegment] = []

    /// The last partial text (from the most recent chunk's last segment)
    private var lastPartialText: String = ""

    // MARK: Initialization

    init() {}

    // MARK: - Model Loading

    /// Load a WhisperKit model for live transcription.
    /// The model stays loaded for subsequent chunks.
    /// - Parameter modelID: The WhisperKit model variant (e.g., "openai_whisper-tiny")
    func loadModel(_ modelID: String) async throws {
        if self.modelID == modelID && whisperKit != nil {
            return // Already loaded
        }

        Logger.info("LiveTranscriptionEngine loading model: \(modelID)")

        self.whisperKit = try await WhisperKit(
            model: modelID,
            downloadBase: AppPaths.modelsDirectory
        )
        self.modelID = modelID

        Logger.info("LiveTranscriptionEngine model loaded: \(modelID)")
    }

    var isModelLoaded: Bool {
        whisperKit != nil && modelID != nil
    }

    // MARK: - Streaming Transcription

    /// Transcribe a single chunk of audio samples.
    /// Results are accumulated and merged with previous chunks.
    /// - Parameters:
    ///   - samples: Float32 PCM samples at 16kHz, mono
    ///   - timestamp: The absolute timestamp of this chunk
    ///   - settings: Transcription settings
    ///   - resultHandler: Called with updated segments
    func transcribeChunk(
        samples: [Float],
        timestamp: TimeInterval,
        settings: TranscriptionSettings,
        resultHandler: @escaping ResultHandler
    ) {
        guard !isCancelled else { return }
        guard let whisperKit = whisperKit else {
            resultHandler([], false, "")
            return
        }

        Task {
            do {
                // Write chunk to temp WAV file
                let tempURL = AppPaths.cacheDirectory.appendingPathComponent("live_chunk_\(UUID().uuidString).wav")
                let wavData = AudioProcessor.convertFloatSamplesToWAV(samples)
                try wavData.write(to: tempURL)

                defer {
                    try? FileManager.default.removeItem(at: tempURL)
                }

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

                // Transcribe this chunk
                let results = try await whisperKit.transcribe(
                    audioPath: tempURL.path,
                    decodeOptions: decodeOptions
                )

                if self.isCancelled { return }

                // Process results
                guard let wkResult = results.first else {
                    await MainActor.run {
                        resultHandler(self.allSegments, false, "")
                    }
                    return
                }

                // Convert segments with timestamp offset
                let newSegments: [TranscriptionSegment] = wkResult.segments.enumerated().map { index, segment in
                    let words: [TranscriptionWord]? = segment.words?.map { wt in
                        TranscriptionWord(
                            word: wt.word,
                            startTime: TimeInterval(wt.start) + timestamp,
                            endTime: TimeInterval(wt.end) + timestamp,
                            probability: wt.probability
                        )
                    }

                    return TranscriptionSegment(
                        index: self.allSegments.count + index,
                        startTime: TimeInterval(segment.start) + timestamp,
                        endTime: TimeInterval(segment.end) + timestamp,
                        text: segment.text,
                        words: words
                    )
                }

                // Merge: replace last segment if it was partial (overlapping chunk)
                if !self.allSegments.isEmpty && !newSegments.isEmpty {
                    // Check if the last segment overlaps with the first new segment
                    let lastSegment = self.allSegments.last!
                    let firstNew = newSegments.first!

                    if firstNew.startTime < lastSegment.endTime {
                        // Overlap detected - replace the last segment with the new one
                        // (the new chunk has more context, so it's likely more accurate)
                        self.allSegments.removeLast()
                    }
                }

                self.allSegments.append(contentsOf: newSegments)

                // Update partial text (last segment text)
                self.lastPartialText = newSegments.last?.text ?? ""

                await MainActor.run {
                    resultHandler(self.allSegments, false, self.lastPartialText)
                }

            } catch {
                Logger.error("Live transcription chunk failed: \(error.localizedDescription)")
                await MainActor.run {
                    resultHandler(self.allSegments, false, "")
                }
            }
        }
    }

    /// Finalize the transcription (called when recording stops).
    /// Returns the complete transcript.
    /// - Parameter resultHandler: Called with final segments
    func finalize(resultHandler: @escaping ResultHandler) {
        let finalText = allSegments.map { $0.text }.joined(separator: " ")
        Task { @MainActor in
            resultHandler(self.allSegments, true, finalText)
        }
    }

    // MARK: - Cancel & Reset

    /// Cancel any in-progress transcription.
    func cancel() {
        isCancelled = true
        Logger.info("LiveTranscriptionEngine cancelled")
    }

    /// Reset the engine for a new session.
    /// Keeps the model loaded but clears accumulated segments.
    func reset() {
        isCancelled = false
        allSegments.removeAll()
        lastPartialText = ""
        timeOffset = 0
        Logger.info("LiveTranscriptionEngine reset")
    }

    /// Get all accumulated segments.
    var segments: [TranscriptionSegment] {
        allSegments
    }

    /// Get the full transcript text.
    var fullText: String {
        allSegments.map { $0.text }.joined(separator: " ")
    }
}
