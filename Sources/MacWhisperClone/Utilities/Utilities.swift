import Foundation

// MARK: - Time Formatter

/// Utility for formatting timestamps and durations.
enum TimeFormatter {

    /// Format a timestamp as HH:MM:SS.mmm or MM:SS.mmm
    static func formatTimestamp(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let milliseconds = Int((time - Double(totalSeconds)) * 1000)

        if hours > 0 {
            return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
        } else {
            return String(format: "%02d:%02d,%03d", minutes, seconds, milliseconds)
        }
    }

    /// Format a timestamp for SRT subtitles: HH:MM:SS,mmm
    static func formatSRTTimestamp(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let milliseconds = Int((time - Double(totalSeconds)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }

    /// Format a timestamp for VTT subtitles: HH:MM:SS.mmm
    static func formatVTTTimestamp(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let milliseconds = Int((time - Double(totalSeconds)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
    }

    /// Format a duration as M:SS or H:MM:SS
    static func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    /// Format a duration with milliseconds: M:SS.mmm
    static func formatDurationPrecise(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let milliseconds = Int((duration - Double(totalSeconds)) * 1000)
        return String(format: "%d:%02d.%03d", minutes, seconds, milliseconds)
    }
}

// MARK: - File Paths

/// Manages file system paths for models, transcripts, and cache.
enum AppPaths {

    /// Application Support directory for this app
    static var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MacWhisperClone", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Directory for downloaded whisper models
    static var modelsDirectory: URL {
        let dir = appSupportDirectory.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Directory for saved transcription sessions
    static var transcriptsDirectory: URL {
        let dir = appSupportDirectory.appendingPathComponent("Transcripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Directory for temporary audio processing files
    static var cacheDirectory: URL {
        let dir = appSupportDirectory.appendingPathComponent("Cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Database file path
    static var databasePath: URL {
        appSupportDirectory.appendingPathComponent("macwhisperclone.sqlite")
    }

    /// Local path for a WhisperKit model folder.
    /// WhisperKit stores CoreML models as directories (not single files).
    static func modelPath(for modelID: String) -> URL {
        modelsDirectory.appendingPathComponent(modelID, isDirectory: true)
    }
}

// MARK: - Logger

/// Simple logging utility.
enum Logger {
    static func info(_ message: String, file: String = #fileID, line: Int = #line) {
        log(level: "INFO", message: message, file: file, line: line)
    }

    static func warning(_ message: String, file: String = #fileID, line: Int = #line) {
        log(level: "WARN", message: message, file: file, line: line)
    }

    static func error(_ message: String, file: String = #fileID, line: Int = #line) {
        log(level: "ERROR", message: message, file: file, line: line)
    }

    static func debug(_ message: String, file: String = #fileID, line: Int = #line) {
        #if DEBUG
        log(level: "DEBUG", message: message, file: file, line: line)
        #endif
    }

    private static func log(level: String, message: String, file: String, line: Int) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        print("[\(timestamp)] [\(level)] [\(fileName):\(line)] \(message)")
    }
}
