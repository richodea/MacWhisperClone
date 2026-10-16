import Foundation
import SwiftUI

// MARK: - Settings View Model

/// Manages app settings and API keys.
@MainActor
final class SettingsViewModel: ObservableObject {

    // MARK: Published Properties

    @Published var openAIAPIKey: String = ""
    @Published var groqAPIKey: String = ""
    @Published var selectedEngine: TranscriptionEngineType = .whisperKit
    @Published var defaultLanguage: String = ""
    @Published var enableMetal: Bool = true
    @Published var enableWordTimestamps: Bool = true
    @Published var enableAutoSave: Bool = true
    @Published var theme: AppTheme = .system

    // MARK: Initialization

    init() {
        loadSettings()
    }

    // MARK: - Load / Save

    func loadSettings() {
        openAIAPIKey = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
        groqAPIKey = UserDefaults.standard.string(forKey: "groq_api_key") ?? ""
        selectedEngine = TranscriptionEngineType(rawValue: UserDefaults.standard.string(forKey: "selected_engine") ?? "") ?? .whisperKit
        defaultLanguage = UserDefaults.standard.string(forKey: "default_language") ?? ""
        enableMetal = UserDefaults.standard.object(forKey: "enable_metal") as? Bool ?? true
        enableWordTimestamps = UserDefaults.standard.object(forKey: "enable_word_timestamps") as? Bool ?? true
        enableAutoSave = UserDefaults.standard.object(forKey: "enable_autosave") as? Bool ?? true
        let themeRaw = UserDefaults.standard.string(forKey: "theme") ?? "system"
        theme = AppTheme(rawValue: themeRaw) ?? .system
    }

    func saveSettings() {
        UserDefaults.standard.set(openAIAPIKey, forKey: "openai_api_key")
        UserDefaults.standard.set(groqAPIKey, forKey: "groq_api_key")
        UserDefaults.standard.set(selectedEngine.rawValue, forKey: "selected_engine")
        UserDefaults.standard.set(defaultLanguage, forKey: "default_language")
        UserDefaults.standard.set(enableMetal, forKey: "enable_metal")
        UserDefaults.standard.set(enableWordTimestamps, forKey: "enable_word_timestamps")
        UserDefaults.standard.set(enableAutoSave, forKey: "enable_autosave")
        UserDefaults.standard.set(theme.rawValue, forKey: "theme")
        Logger.info("Settings saved")
    }
}

// MARK: - App Theme

enum AppTheme: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}

// MARK: - Supported Languages

enum SupportedLanguage: String, CaseIterable, Identifiable {
    case auto = "Auto-detect"
    case en = "English"
    case zh = "Chinese"
    case es = "Spanish"
    case fr = "French"
    case de = "German"
    case it = "Italian"
    case ja = "Japanese"
    case ko = "Korean"
    case pt = "Portuguese"
    case ru = "Russian"
    case ar = "Arabic"
    case hi = "Hindi"
    case id = "Indonesian"
    case nl = "Dutch"
    case pl = "Polish"
    case sv = "Swedish"
    case tr = "Turkish"
    case uk = "Ukrainian"
    case vi = "Vietnamese"

    var id: String { rawValue }

    /// whisper.cpp language code
    var code: String {
        switch self {
        case .auto: return ""
        default: return String(rawValue.prefix(2))
        }
    }
}
