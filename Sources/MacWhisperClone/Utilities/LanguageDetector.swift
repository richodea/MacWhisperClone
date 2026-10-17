import Foundation
import WhisperKit

// MARK: - Language Detector

/// Utility for detecting the spoken language of audio using WhisperKit.
/// Also provides human-readable names for Whisper language codes.
enum LanguageDetector {

    /// Mapping of Whisper language codes to human-readable names.
    /// Based on Whisper's supported languages.
    static let languageNames: [String: String] = [
        "en": "English",
        "zh": "Chinese",
        "es": "Spanish",
        "fr": "French",
        "de": "German",
        "it": "Italian",
        "ja": "Japanese",
        "ko": "Korean",
        "pt": "Portuguese",
        "ru": "Russian",
        "ar": "Arabic",
        "hi": "Hindi",
        "id": "Indonesian",
        "nl": "Dutch",
        "pl": "Polish",
        "sv": "Swedish",
        "tr": "Turkish",
        "uk": "Ukrainian",
        "vi": "Vietnamese",
        "th": "Thai",
        "cs": "Czech",
        "da": "Danish",
        "fi": "Finnish",
        "el": "Greek",
        "he": "Hebrew",
        "hu": "Hungarian",
        "no": "Norwegian",
        "ro": "Romanian",
        "sk": "Slovak",
        "ms": "Malay",
        "bn": "Bengali",
        "ca": "Catalan",
        "hr": "Croatian",
        "et": "Estonian",
        "bg": "Bulgarian",
        "af": "Afrikaans",
        "fa": "Persian",
        "ta": "Tamil",
        "ur": "Urdu",
        "lt": "Lithuanian",
        "lv": "Latvian",
        "sl": "Slovenian",
        "cy": "Welsh",
        "is": "Icelandic",
        "ga": "Irish",
        "mk": "Macedonian",
        "az": "Azerbaijani",
        "kk": "Kazakh",
        "te": "Telugu",
        "mr": "Marathi",
        "ne": "Nepali",
        "kn": "Kannada",
        "gu": "Gujarati",
        "pa": "Punjabi",
        "si": "Sinhala",
        "km": "Khmer",
        "sn": "Shona",
        "yo": "Yoruba",
        "so": "Somali",
        "sw": "Swahili",
        "tl": "Tagalog",
        "uz": "Uzbek",
        "mn": "Mongolian",
        "my": "Burmese",
        "la": "Lao",
        "jw": "Javanese",
        "su": "Sundanese",
        "yue": "Cantonese"
    ]

    /// Convert a Whisper language code to a human-readable name.
    /// Falls back to the uppercased code if unknown.
    static func displayName(for code: String) -> String {
        let normalized = code.lowercased()
        if let name = languageNames[normalized] {
            return name
        }
        return code.uppercased()
    }

    /// Detect the language of an audio file using WhisperKit.
    /// - Parameter audioPath: Path to the audio file (WAV, MP3, etc.)
    /// - Parameter whisperKit: An initialized WhisperKit instance with a multilingual model loaded.
    /// - Returns: The detected language code (e.g. "en", "id") and the full probability distribution.
    static func detect(
        audioPath: String,
        whisperKit: WhisperKit
    ) async throws -> (language: String, probabilities: [String: Float]) {
        let result = try await whisperKit.detectLanguage(audioPath: audioPath)
        return (language: result.language, probabilities: result.langProbs)
    }

    /// Detect the language of audio samples using WhisperKit.
    /// - Parameter audioArray: PCM float samples at 16kHz.
    /// - Parameter whisperKit: An initialized WhisperKit instance with a multilingual model loaded.
    /// - Returns: The detected language code and the full probability distribution.
    static func detect(
        audioArray: [Float],
        whisperKit: WhisperKit
    ) async throws -> (language: String, probabilities: [String: Float]) {
        let result = try await whisperKit.detectLangauge(audioArray: audioArray)
        return (language: result.language, probabilities: result.langProbs)
    }

    /// Get the top N candidate languages from a probability distribution.
    static func topLanguages(from probabilities: [String: Float], limit: Int = 3) -> [(code: String, name: String, probability: Float)] {
        probabilities
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (code: $0.key, name: displayName(for: $0.key), probability: $0.value) }
    }
}
