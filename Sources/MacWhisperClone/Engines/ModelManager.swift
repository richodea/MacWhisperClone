import Foundation
import WhisperKit

// MARK: - Model Manager

/// Manages downloading, storing, and selecting WhisperKit models.
/// WhisperKit models are CoreML bundles downloaded from HuggingFace (argmaxinc/whisperkit-coreml).
/// Unlike whisper.cpp's single .bin files, WhisperKit stores models as folders containing
/// multiple .mlmodelc files (encoder + decoder).
@MainActor
final class ModelManager: ObservableObject {

    // MARK: Published Properties

    @Published private(set) var models: [WhisperModel] = []
    @Published private(set) var selectedModelID: String
    @Published private(set) var downloadStates: [String: ModelDownloadState] = [:]

    // MARK: Private Properties

    private var downloadTasks: [String: Task<Void, Never>] = [:]

    // MARK: Initialization

    init() {
        // Load model list and check which are downloaded
        models = WhisperModel.availableModels.map { model in
            var m = model
            let path = AppPaths.modelPath(for: model.id)
            m.localPath = path
            m.isDownloaded = FileManager.default.fileExists(atPath: path.path)
            return m
        }

        // Load selected model from preferences
        let savedModelID = UserDefaults.standard.string(forKey: "selectedModelID")
        selectedModelID = savedModelID ?? WhisperModel.defaultModelID

        Logger.info("ModelManager initialized with \(models.count) models, selected: \(selectedModelID)")
    }

    // MARK: - Model Selection

    /// Select a model as the active model for transcription.
    func selectModel(_ modelID: String) {
        guard models.contains(where: { $0.id == modelID }) else {
            Logger.warning("Attempted to select unknown model: \(modelID)")
            return
        }
        selectedModelID = modelID
        UserDefaults.standard.set(modelID, forKey: "selectedModelID")
        Logger.info("Selected model: \(modelID)")
    }

    /// Get the currently selected model.
    var selectedModel: WhisperModel? {
        models.first(where: { $0.id == selectedModelID })
    }

    /// Get all downloaded models.
    var downloadedModels: [WhisperModel] {
        models.filter(\.isDownloaded)
    }

    /// Check if at least one model is downloaded.
    var hasDownloadedModel: Bool {
        !downloadedModels.isEmpty
    }

    // MARK: - Download

    /// Mark a model as downloaded. WhisperKit handles its own model downloads
    /// when the engine is initialized with a model name. This method updates
    /// the UI state to reflect that a model is available locally.
    /// - Parameter modelID: The model identifier to mark as downloaded
    func markModelDownloaded(_ modelID: String) {
        guard let modelIndex = models.firstIndex(where: { $0.id == modelID }) else {
            Logger.error("Model not found: \(modelID)")
            return
        }

        let path = AppPaths.modelPath(for: modelID)
        downloadStates[modelID] = .completed
        updateModel(modelID) {
            $0.isDownloaded = true
            $0.isDownloading = false
            $0.downloadProgress = 1.0
            $0.localPath = path
        }
        Logger.info("Model marked as downloaded: \(modelID)")
    }

    /// Check if a model is already downloaded locally.
    /// - Parameter modelID: The model identifier to check
    /// - Returns: True if the model folder exists locally
    func isModelDownloaded(_ modelID: String) -> Bool {
        let path = AppPaths.modelPath(for: modelID)
        return FileManager.default.fileExists(atPath: path.path)
    }

    /// Download a model using WhisperKit's download API.
    /// Downloads the CoreML model files from HuggingFace (argmaxinc/whisperkit-coreml)
    /// and caches them locally in the app's Models directory.
    /// - Parameter modelID: The model identifier to download (e.g., "openai_whisper-tiny")
    func downloadModel(_ modelID: String) {
        guard let modelIndex = models.firstIndex(where: { $0.id == modelID }) else {
            Logger.error("Model not found: \(modelID)")
            return
        }

        guard !models[modelIndex].isDownloaded else {
            Logger.info("Model already downloaded: \(modelID)")
            return
        }

        guard downloadTasks[modelID] == nil else {
            Logger.info("Download already in progress: \(modelID)")
            return
        }

        Logger.info("Starting model download: \(modelID)")

        downloadStates[modelID] = .downloading(progress: 0)
        models[modelIndex].isDownloading = true

        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let modelFolder = try await WhisperKit.download(
                    variant: modelID,
                    downloadBase: AppPaths.modelsDirectory,
                    progressCallback: { [weak self] progress in
                        let progressValue = progress.fractionCompleted
                        Task { @MainActor in
                            self?.downloadStates[modelID] = .downloading(progress: progressValue)
                            self?.updateModel(modelID) {
                                $0.downloadProgress = progressValue
                            }
                        }
                    }
                )

                // Download complete
                self.downloadStates[modelID] = .completed
                self.updateModel(modelID) {
                    $0.isDownloaded = true
                    $0.isDownloading = false
                    $0.downloadProgress = 1.0
                    $0.localPath = modelFolder
                }

                // Auto-select the first downloaded model if none selected
                if !self.hasDownloadedModel || self.selectedModelID == modelID {
                    self.selectModel(modelID)
                }

                Logger.info("Model downloaded successfully: \(modelID) at \(modelFolder.path)")
            } catch {
                if Task.isCancelled {
                    Logger.info("Download cancelled: \(modelID)")
                } else {
                    Logger.error("Failed to download model \(modelID): \(error.localizedDescription)")
                    self.downloadStates[modelID] = .failed(error.localizedDescription)
                }
                self.updateModel(modelID) {
                    $0.isDownloading = false
                    $0.downloadProgress = 0
                }
            }

            self.downloadTasks.removeValue(forKey: modelID)
        }

        downloadTasks[modelID] = task
    }

    /// Cancel an in-progress model download.
    func cancelDownload(_ modelID: String) {
        downloadTasks[modelID]?.cancel()
        downloadTasks.removeValue(forKey: modelID)
        downloadStates[modelID] = .idle
        updateModel(modelID) {
            $0.isDownloading = false
            $0.downloadProgress = 0
        }
        Logger.info("Download cancelled: \(modelID)")
    }

    /// Delete a downloaded model from disk.
    func deleteModel(_ modelID: String) {
        let path = AppPaths.modelPath(for: modelID)

        do {
            if FileManager.default.fileExists(atPath: path.path) {
                try FileManager.default.removeItem(at: path)
            }

            updateModel(modelID) {
                $0.isDownloaded = false
                $0.downloadProgress = 0
                $0.localPath = nil
            }

            downloadStates[modelID] = .idle

            // If we deleted the selected model, switch to default
            if selectedModelID == modelID {
                selectedModelID = WhisperModel.defaultModelID
                UserDefaults.standard.set(selectedModelID, forKey: "selectedModelID")
            }

            Logger.info("Model deleted: \(modelID)")
        } catch {
            Logger.error("Failed to delete model \(modelID): \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    private func updateModel(_ modelID: String, _ update: (inout WhisperModel) -> Void) {
        guard let index = models.firstIndex(where: { $0.id == modelID }) else { return }
        update(&models[index])
    }
}
