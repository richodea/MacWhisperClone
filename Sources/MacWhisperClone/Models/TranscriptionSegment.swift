import Foundation

// MARK: - Transcription Segment

/// Represents a single segment of transcribed audio with timing information.
struct TranscriptionSegment: Identifiable, Codable, Hashable {
    let id: UUID
    var index: Int
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var speaker: String?
    var words: [TranscriptionWord]?
    var isConfirmed: Bool

    init(
        id: UUID = UUID(),
        index: Int,
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        speaker: String? = nil,
        words: [TranscriptionWord]? = nil,
        isConfirmed: Bool = true
    ) {
        self.id = id
        self.index = index
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.speaker = speaker
        self.words = words
        self.isConfirmed = isConfirmed
    }

    /// Formatted start time as MM:SS.mmm
    var formattedStartTime: String {
        TimeFormatter.formatTimestamp(startTime)
    }

    /// Formatted end time as MM:SS.mmm
    var formattedEndTime: String {
        TimeFormatter.formatTimestamp(endTime)
    }

    /// Duration of this segment
    var duration: TimeInterval {
        endTime - startTime
    }
}

// MARK: - Transcription Word

/// Represents a single word with timing for word-level alignment.
struct TranscriptionWord: Identifiable, Codable, Hashable {
    let id: UUID
    var word: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var probability: Float

    init(
        id: UUID = UUID(),
        word: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        probability: Float = 1.0
    ) {
        self.id = id
        self.word = word
        self.startTime = startTime
        self.endTime = endTime
        self.probability = probability
    }
}

// MARK: - Transcription Result

/// Complete transcription result containing all segments and metadata.
struct TranscriptionResult: Codable {
    var segments: [TranscriptionSegment]
    var detectedLanguage: String
    var modelUsed: String
    var engineUsed: TranscriptionEngineType
    var processingTime: TimeInterval
    var audioDuration: TimeInterval

    init(
        segments: [TranscriptionSegment],
        detectedLanguage: String,
        modelUsed: String,
        engineUsed: TranscriptionEngineType,
        processingTime: TimeInterval,
        audioDuration: TimeInterval
    ) {
        self.segments = segments
        self.detectedLanguage = detectedLanguage
        self.modelUsed = modelUsed
        self.engineUsed = engineUsed
        self.processingTime = processingTime
        self.audioDuration = audioDuration
    }

    /// Full transcript as plain text
    var fullText: String {
        segments.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Total number of words across all segments
    var wordCount: Int {
        segments.reduce(0) { $0 + $1.text.split(separator: " ").count }
    }
}
