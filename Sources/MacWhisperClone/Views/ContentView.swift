import SwiftUI

// MARK: - Content View

/// Main content view with sidebar navigation and detail panel.
struct ContentView: View {

    // MARK: Environment

    @EnvironmentObject var transcriptionViewModel: TranscriptionViewModel
    @EnvironmentObject var liveViewModel: LiveTranscriptionViewModel
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var settingsViewModel: SettingsViewModel

    // MARK: State

    @State private var sidebarSelection: SidebarItem? = .transcriptions
    @State private var showFileImporter = false
    @State private var showExportSheet = false
    @State private var selectedExportFormat: ExportFormat = .txt

    // MARK: Body

    var body: some View {
        NavigationSplitView {
            // Sidebar
            SidebarView(selection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } content: {
            // Content list
            switch sidebarSelection {
            case .transcriptions:
                TranscriptionListView(showFileImporter: $showFileImporter)
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320)
            case .live:
                LiveTranscriptionView(sidebarSelection: $sidebarSelection)
                    .navigationSplitViewColumnWidth(min: 400, ideal: 500)
            case .models:
                ModelListView()
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320)
            case .settings:
                SettingsView()
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320)
            case nil:
                EmptyView()
            }
        } detail: {
            // Detail panel - not shown for Live tab (it's self-contained)
            if sidebarSelection == .live {
                EmptyView()
            } else if let task = transcriptionViewModel.selectedTask {
                TranscriptionDetailView(task: task, showExportSheet: $showExportSheet)
            } else {
                EmptyDetailView()
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.audio, .mp3, .wav, .mpeg4Audio, .aiff],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                transcriptionViewModel.importFiles(urls: urls)
            case .failure(let error):
                transcriptionViewModel.showError(message: error.localizedDescription)
            }
        }
        .sheet(isPresented: $showExportSheet) {
            if let task = transcriptionViewModel.selectedTask {
                ExportSheetView(task: task)
                    .environmentObject(transcriptionViewModel)
            }
        }
        .alert("Error", isPresented: $transcriptionViewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(transcriptionViewModel.errorMessage ?? "An unknown error occurred")
        }
    }
}

// MARK: - Sidebar Item

enum SidebarItem: String, Hashable, CaseIterable {
    case transcriptions = "Transcriptions"
    case live = "Live"
    case models = "Models"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .transcriptions: return "waveform"
        case .live: return "mic.badge.xmark"
        case .models: return "cpu"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                ForEach(SidebarItem.allCases, id: \.self) { item in
                    NavigationLink(value: item) {
                        Label(item.rawValue, systemImage: item.icon)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Empty Detail View

struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No Transcription Selected")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Import an audio file or select a transcription from the list to get started.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
