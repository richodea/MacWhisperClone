import SwiftUI

// MARK: - Settings View

/// App settings for engine selection, API keys, and preferences.
struct SettingsView: View {

    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var modelManager: ModelManager

    @State private var selectedLanguage = SupportedLanguage.auto

    var body: some View {
        Form {
            // Transcription Engine
            Section("Transcription Engine") {
                Picker("Engine", selection: $settingsViewModel.selectedEngine) {
                    ForEach(TranscriptionEngineType.allCases, id: \.self) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }

                if settingsViewModel.selectedEngine.isLocal {
                    HStack {
                        Text("Active Model")
                        Spacer()
                        if let model = modelManager.selectedModel {
                            Text(model.name)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("None")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // API Keys
            if settingsViewModel.selectedEngine.requiresAPIKey {
                Section("API Configuration") {
                    switch settingsViewModel.selectedEngine {
                    case .openAI:
                        SecureField("OpenAI API Key", text: $settingsViewModel.openAIAPIKey)
                            .textFieldStyle(.roundedBorder)
                        Link("Get API Key",
                             destination: URL(string: "https://platform.openai.com/api-keys")!)
                    case .groq:
                        SecureField("Groq API Key", text: $settingsViewModel.groqAPIKey)
                            .textFieldStyle(.roundedBorder)
                        Link("Get API Key",
                             destination: URL(string: "https://console.groq.com/keys")!)
                    default:
                        Text("Configure API key in Settings")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Language
            Section("Language") {
                Picker("Default Language", selection: $selectedLanguage) {
                    ForEach(SupportedLanguage.allCases) { lang in
                        Text(lang.rawValue).tag(lang)
                    }
                }
                Toggle("Translate to English", isOn: .constant(false))
            }

            // Transcription Options
            Section("Transcription Options") {
                Toggle("Metal GPU Acceleration", isOn: $settingsViewModel.enableMetal)
                Toggle("Word-level Timestamps", isOn: $settingsViewModel.enableWordTimestamps)
                Toggle("Auto-save Transcriptions", isOn: $settingsViewModel.enableAutoSave)

                HStack {
                    Text("Temperature")
                    Spacer()
                    Slider(value: .constant(0), in: 0...1, step: 0.1)
                        .frame(width: 150)
                    Text("0.0")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 30)
                }
            }

            // Appearance
            Section("Appearance") {
                Picker("Theme", selection: $settingsViewModel.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
            }

            // About
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Engine")
                    Spacer()
                    Text("whisper.cpp")
                        .foregroundStyle(.secondary)
                }
                Link("GitHub", destination: URL(string: "https://github.com/ggerganov/whisper.cpp")!)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: settingsViewModel.openAIAPIKey) { _, _ in settingsViewModel.saveSettings() }
        .onChange(of: settingsViewModel.groqAPIKey) { _, _ in settingsViewModel.saveSettings() }
        .onChange(of: settingsViewModel.selectedEngine) { _, _ in settingsViewModel.saveSettings() }
        .onChange(of: settingsViewModel.theme) { _, _ in settingsViewModel.saveSettings() }
        .onChange(of: settingsViewModel.enableMetal) { _, _ in settingsViewModel.saveSettings() }
        .onChange(of: settingsViewModel.enableWordTimestamps) { _, _ in settingsViewModel.saveSettings() }
        .onChange(of: settingsViewModel.enableAutoSave) { _, _ in settingsViewModel.saveSettings() }
        .onChange(of: settingsViewModel.defaultLanguage) { _, _ in settingsViewModel.saveSettings() }
        .onChange(of: selectedLanguage) { _, newValue in
            settingsViewModel.defaultLanguage = newValue.code
        }
        .onAppear {
            // Sync picker with stored default language
            if let lang = SupportedLanguage.allCases.first(where: { $0.code == settingsViewModel.defaultLanguage }) {
                selectedLanguage = lang
            }
        }
    }
}
