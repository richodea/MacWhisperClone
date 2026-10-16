import Foundation

// MARK: - Transcript Exporter

/// Handles exporting transcription results to various formats.
enum TranscriptExporter {

    // MARK: - Export

    /// Export a transcription result to the specified format.
    /// - Parameters:
    ///   - result: The transcription result to export
    ///   - format: The target export format
    ///   - audioFileName: Original audio file name (for naming the output)
    /// - Returns: The exported content as a String
    static func export(_ result: TranscriptionResult, to format: ExportFormat) -> String {
        switch format {
        case .txt:
            return exportToTXT(result)
        case .srt:
            return exportToSRT(result)
        case .vtt:
            return exportToVTT(result)
        case .json:
            return exportToJSON(result)
        case .csv:
            return exportToCSV(result)
        case .whisper:
            return exportToWhisperSession(result)
        }
    }

    /// Export to a file on disk.
    static func exportToFile(
        _ result: TranscriptionResult,
        to format: ExportFormat,
        fileName: String,
        directory: URL? = nil
    ) throws -> URL {
        let content = export(result, to: format)
        let outputDir = directory ?? AppPaths.transcriptsDirectory
        let fileURL = outputDir.appendingPathComponent("\(fileName).\(format.fileExtension)")

        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        Logger.info("Exported to \(fileURL.path)")
        return fileURL
    }

    // MARK: - TXT

    /// Export as plain text.
    static func exportToTXT(_ result: TranscriptionResult) -> String {
        result.fullText
    }

    // MARK: - SRT

    /// Export as SubRip subtitle format.
    static func exportToSRT(_ result: TranscriptionResult) -> String {
        var output = ""

        for (index, segment) in result.segments.enumerated() {
            output += "\(index + 1)\n"
            output += "\(TimeFormatter.formatSRTTimestamp(segment.startTime)) --> \(TimeFormatter.formatSRTTimestamp(segment.endTime))\n"
            output += "\(segment.text)\n"
            if segment.speaker != nil {
                output = output.trimmingCharacters(in: .newlines) + "\n"
            }
            output += "\n"
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - VTT

    /// Export as WebVTT subtitle format.
    static func exportToVTT(_ result: TranscriptionResult) -> String {
        var output = "WEBVTT\n\n"

        for segment in result.segments {
            output += "\(TimeFormatter.formatVTTTimestamp(segment.startTime)) --> \(TimeFormatter.formatVTTTimestamp(segment.endTime))\n"
            if let speaker = segment.speaker {
                output += "<v \(speaker)>\(segment.text)\n"
            } else {
                output += "\(segment.text)\n"
            }
            output += "\n"
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - JSON

    /// Export as JSON with full metadata.
    static func exportToJSON(_ result: TranscriptionResult) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        struct JSONExport: Codable {
            let text: String
            let language: String
            let model: String
            let engine: String
            let duration: TimeInterval
            let processingTime: TimeInterval
            let segments: [SegmentData]

            struct SegmentData: Codable {
                let id: Int
                let start: TimeInterval
                let end: TimeInterval
                let text: String
                let speaker: String?
                let words: [WordData]?
            }

            struct WordData: Codable {
                let word: String
                let start: TimeInterval
                let end: TimeInterval
                let probability: Float
            }
        }

        let export = JSONExport(
            text: result.fullText,
            language: result.detectedLanguage,
            model: result.modelUsed,
            engine: result.engineUsed.rawValue,
            duration: result.audioDuration,
            processingTime: result.processingTime,
            segments: result.segments.map { seg in
                JSONExport.SegmentData(
                    id: seg.index,
                    start: seg.startTime,
                    end: seg.endTime,
                    text: seg.text,
                    speaker: seg.speaker,
                    words: seg.words?.map { word in
                        JSONExport.WordData(
                            word: word.word,
                            start: word.startTime,
                            end: word.endTime,
                            probability: word.probability
                        )
                    }
                )
            }
        )

        guard let data = try? encoder.encode(export),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        return json
    }

    // MARK: - CSV

    /// Export as CSV with segment-level data.
    static func exportToCSV(_ result: TranscriptionResult) -> String {
        var output = "Index,Start,End,Duration,Text,Speaker\n"

        for segment in result.segments {
            let start = TimeFormatter.formatTimestamp(segment.startTime)
            let end = TimeFormatter.formatTimestamp(segment.endTime)
            let duration = String(format: "%.3f", segment.duration)
            let text = csvEscape(segment.text)
            let speaker = csvEscape(segment.speaker ?? "")

            output += "\(segment.index),\(start),\(end),\(duration),\(text),\(speaker)\n"
        }

        return output
    }

    // MARK: - Whisper Session

    /// Export as native Whisper session format (JSON with full metadata).
    static func exportToWhisperSession(_ result: TranscriptionResult) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]

        struct WhisperSession: Codable {
            let version: Int
            let createdAt: Date
            let result: TranscriptionResult
        }

        let session = WhisperSession(
            version: 1,
            createdAt: Date(),
            result: result
        )

        // Use ISO8601 date encoding
        let config = JSONEncoder.DateEncodingStrategy.iso8601
        encoder.dateEncodingStrategy = config

        guard let data = try? encoder.encode(session),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        return json
    }

    // MARK: - Helpers

    /// Escape a string for CSV format.
    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
