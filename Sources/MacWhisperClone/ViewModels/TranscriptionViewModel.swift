import Foundation
import SwiftUI

// MARK: - Transcription View Model

/// Main view model managing the transcription lifecycle and state.
@MainActor
final class TranscriptionViewModel: ObservableObject {

    // MARK: Published State

    @Published var tasks: [TranscriptionTask] = []
    @Published var selectedTaskID: UUID?
    @Published var settings = TranscriptionSettings.default
    @Published var isImporting = false
    @Published var errorMessage: String?
    @Published var showError = false

    // MARK: Dependencies

    let modelManager: ModelManager
    let database = DatabaseManager.shared
    private var whisperEngine: WhisperKitEngine?
    private var cloudEngine: TranscriptionEngine?

    // MARK: Initialization

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
        loadSavedSessions()
    }

    // MARK: - File Import

    /// Import audio files from file picker.
    func importFiles(urls: [URL]) {
        for url in urls {
            guard AudioFile.isSupported(url) else {
                Logger.warning("Unsupported file format: \(url.lastPathComponent)")
                showError(message: "Unsupported format: \(url.pathExtension)")
                continue
            }

            // Get audio metadata
            let audioFile: AudioFile
            if let info = AudioProcessor.getAudioInfo(url) {
                audioFile = AudioFile(
                    url: url,
                    duration: info.duration,
                    sampleRate: info.sampleRate,
                    channels: info.channels
                )
            } else {
                audioFile = AudioFile(url: url)
            }

            let task = TranscriptionTask(
                audioFile: audioFile,
                modelID: modelManager.selectedModelID,
                engineType: .whisperKit
            )

            tasks.insert(task, at: 0)
            selectedTaskID = task.id

            Logger.info("Imported: \(audioFile.name) (\(audioFile.formattedFileSize))")
        }
    }

    // MARK: - Transcription

    /// Start transcribing a task.
    func startTranscription(taskID: UUID) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return }

        let task = tasks[taskIndex]
        let audioFile = task.audioFile
        let modelID = task.modelID
        let engineType = task.engineType

        // Update task state
        tasks[taskIndex].state = .processingAudio
        tasks[taskIndex].progress = 0
        tasks[taskIndex].errorMessage = nil

        // Load and convert audio
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let (samples, duration) = try AudioProcessor.loadAudioAsPCMFloat(audioFile.url)

                Task { @MainActor in
                    self.tasks[taskIndex].state = .loadingModel
                    self.tasks[taskIndex].audioFile.duration = duration

                    // Get or create engine
                    let engine = try self.getEngine(for: engineType, modelID: modelID)

                    // Update state
                    self.tasks[taskIndex].state = .transcribing

                    // Start transcription
                    engine.transcribe(
                        audioData: samples,
                        settings: self.settings,
                        progressHandler: { progress, segments in
                            if let taskIdx = self.tasks.firstIndex(where: { $0.id == taskID }) {
                                self.tasks[taskIdx].progress = progress
                                if let segments {
                                    // Update with partial segments for live preview
                                    if self.tasks[taskIdx].result == nil {
                                        self.tasks[taskIdx].result = TranscriptionResult(
                                            segments: segments,
                                            detectedLanguage: "",
                                            modelUsed: modelID,
                                            engineUsed: engineType,
                                            processingTime: 0,
                                            audioDuration: duration
                                        )
                                    } else {
                                        self.tasks[taskIdx].result?.segments = segments
                                    }
                                }
                            }
                        },
                        completion: { result in
                            if let taskIdx = self.tasks.firstIndex(where: { $0.id == taskID }) {
                                switch result {
                                case .success(let transcriptionResult):
                                    self.tasks[taskIdx].state = .completed
                                    self.tasks[taskIdx].progress = 1.0
                                    self.tasks[taskIdx].result = transcriptionResult
                                    self.tasks[taskIdx].completedAt = Date()

                                    // Save to database
                                    do {
                                        _ = try self.database.saveSession(
                                            audioFile: audioFile,
                                            result: transcriptionResult
                                        )
                                    } catch {
                                        Logger.error("Failed to save session: \(error.localizedDescription)")
                                    }

                                    Logger.info("Transcription completed: \(audioFile.name)")

                                case .failure(let error):
                                    self.tasks[taskIdx].state = .failed
                                    self.tasks[taskIdx].errorMessage = error.localizedDescription
                                    Logger.error("Transcription failed: \(error.localizedDescription)")
                                }
                            }
                        }
                    )
                }
            } catch {
                Task { @MainActor in
                    if let taskIdx = self.tasks.firstIndex(where: { $0.id == taskID }) {
                        self.tasks[taskIdx].state = .failed
                        self.tasks[taskIdx].errorMessage = error.localizedDescription
                    }
                    self.showError(message: error.localizedDescription)
                }
            }
        }
    }

    /// Cancel an in-progress transcription.
    func cancelTranscription(taskID: UUID) {
        whisperEngine?.cancel()
        cloudEngine?.cancel()

        if let index = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[index].state = .cancelled
        }
    }

    /// Delete a task from the list.
    func deleteTask(taskID: UUID) {
        tasks.removeAll { $0.id == taskID }
        if selectedTaskID == taskID {
            selectedTaskID = tasks.first?.id
        }
    }

    // MARK: - Engine Management

    /// Get or create the appropriate transcription engine.
    private func getEngine(for type: TranscriptionEngineType, modelID: String) throws -> TranscriptionEngine {
        switch type {
        case .whisperKit:
            if whisperEngine == nil {
                whisperEngine = WhisperKitEngine()
            }
            try whisperEngine!.loadModel(modelID)
            return whisperEngine!

        case .openAI:
            let apiKey = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
            let engine = OpenAIWhisperEngine(apiKey: apiKey)
            cloudEngine = engine
            return engine

        case .groq:
            let apiKey = UserDefaults.standard.string(forKey: "groq_api_key") ?? ""
            let engine = GroqWhisperEngine(apiKey: apiKey)
            cloudEngine = engine
            return engine

        default:
            // For other cloud providers, fall back to OpenAI-compatible
            let apiKey = UserDefaults.standard.string(forKey: "\(type.rawValue.lowercased)_api_key") ?? ""
            let endpoint = URL(string: "https://api.example.com/v1/audio/transcriptions")!
            let engine = OpenAICompatibleEngine(endpoint: endpoint, apiKey: apiKey)
            cloudEngine = engine
            return engine
        }
    }

    // MARK: - Saved Sessions

    /// Load previously saved transcription sessions from the database.
    private func loadSavedSessions() {
        do {
            let sessions = try database.loadAllSessions()
            for session in sessions {
                let segments = (try? database.loadSegments(for: session.uuid)) ?? []

                let transcriptionSegments = segments.map { record in
                    TranscriptionSegment(
                        index: record.segmentIndex,
                        startTime: record.startTime,
                        endTime: record.endTime,
                        text: record.text,
                        speaker: record.speaker
                    )
                }

                let result = TranscriptionResult(
                    segments: transcriptionSegments,
                    detectedLanguage: session.detectedLanguage,
                    modelUsed: session.modelID,
                    engineUsed: TranscriptionEngineType(rawValue: session.engineType) ?? .whisperKit,
                    processingTime: session.processingTime,
                    audioDuration: session.audioDuration
                )

                let audioFile = AudioFile(
                    url: URL(fileURLWithPath: session.audioFilePath),
                    name: session.audioFileName,
                    duration: session.audioDuration
                )

                let task = TranscriptionTask(
                    id: UUID(uuidString: session.uuid) ?? UUID(),
                    audioFile: audioFile,
                    modelID: session.modelID,
                    engineType: TranscriptionEngineType(rawValue: session.engineType) ?? .whisperKit,
                    state: .completed,
                    progress: 1.0,
                    result: result,
                    createdAt: session.createdAt,
                    completedAt: session.createdAt
                )

                tasks.append(task)
            }

            Logger.info("Loaded \(sessions.count) saved sessions")
        } catch {
            Logger.error("Failed to load sessions: \(error.localizedDescription)")
        }
    }

    // MARK: - Export

    /// Export a transcription task to a file.
    func exportTask(taskID: UUID, format: ExportFormat) {
        guard let task = tasks.first(where: { $0.id == taskID }),
              let result = task.result else { return }

        do {
            let url = try TranscriptExporter.exportToFile(
                result,
                to: format,
                fileName: task.audioFile.name
            )
            Logger.info("Exported to: \(url.path)")
        } catch {
            showError(message: "Export failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Error Handling

    func showError(message: String) {
        errorMessage = message
        showError = true
    }

    // MARK: - Selected Task

    var selectedTask: TranscriptionTask? {
        guard let selectedTaskID else { return nil }
        return tasks.first(where: { $0.id == selectedTaskID })
    }
}
