import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Main App Entry Point

@main
struct MacWhisperCloneApp: App {

    // MARK: State

    @StateObject private var modelManager = ModelManager()
    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var transcriptionViewModel: TranscriptionViewModel
    @StateObject private var liveTranscriptionViewModel: LiveTranscriptionViewModel

    // MARK: Initialization

    init() {
        // Ensure the app runs as a regular windowed app (not a background/accessory process)
        // This is needed when running via `swift run` without a proper .app bundle
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        let modelManager = ModelManager()
        _modelManager = StateObject(wrappedValue: modelManager)
        _settingsViewModel = StateObject(wrappedValue: SettingsViewModel())
        _transcriptionViewModel = StateObject(wrappedValue: TranscriptionViewModel(modelManager: modelManager))
        _liveTranscriptionViewModel = StateObject(wrappedValue: LiveTranscriptionViewModel(modelManager: modelManager))
    }

    // MARK: Scene

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(modelManager)
                .environmentObject(settingsViewModel)
                .environmentObject(transcriptionViewModel)
                .environmentObject(liveTranscriptionViewModel)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(settingsViewModel.theme.colorScheme)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))

        // Settings scene
        Settings {
            SettingsView()
                .environmentObject(settingsViewModel)
                .environmentObject(modelManager)
        }
    }
}

// MARK: - App Theme Extension

extension AppTheme {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
