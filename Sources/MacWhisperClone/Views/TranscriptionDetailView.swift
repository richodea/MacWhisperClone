import SwiftUI

// MARK: - Transcription Detail View

/// Shows the full transcription with segments, timestamps, and controls.
struct TranscriptionDetailView: View {

    let task: TranscriptionTask
    @Binding var showExportSheet: Bool

    @EnvironmentObject var transcriptionViewModel: TranscriptionViewModel
    @EnvironmentObject var modelManager: ModelManager

    @State private var searchText = ""
    @State private var showWordTimestamps = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            detailToolbar
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            // Content
            if task.state.isRunning {
                TranscriptionProgressView(task: task)
            } else if task.state == .failed {
                TranscriptionErrorView(task: task) {
                    transcriptionViewModel.startTranscription(taskID: task.id)
                }
            } else if let result = task.result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Metadata header
                        TranscriptionMetadataView(task: task, result: result)
                            .padding(.horizontal)
                            .padding(.top, 16)
                            .padding(.bottom, 12)

                        Divider()
                            .padding(.bottom, 8)

                        // Segments
                        ForEach(result.segments) { segment in
                            SegmentRowView(segment: segment, showWordTimestamps: showWordTimestamps)
                                .padding(.horizontal)
                                .padding(.vertical, 4)
                        }

                        Spacer(minLength: 32)
                    }
                }
                .searchable(text: $searchText, prompt: "Search transcript")
            } else {
                EmptyView()
            }
        }
        .navigationTitle(task.audioFile.name)
        .navigationSubtitle(task.state.displayName)
        .overlay(alignment: .bottom) {
            if let status = transcriptionViewModel.saveStatus {
                SaveStatusToast(status: status) {
                    transcriptionViewModel.clearSaveStatus()
                }
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: transcriptionViewModel.saveStatus)
    }

    // MARK: - Toolbar

    private var detailToolbar: some View {
        HStack(spacing: 12) {
            // Audio info
            VStack(alignment: .leading, spacing: 2) {
                Text(task.audioFile.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(task.audioFile.formattedDuration)
                    Text("·")
                    Text(task.audioFile.formattedFileSize)
                    Text("·")
                    Text(task.engineType.displayName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Actions
            if task.state.isRunning {
                Button(role: .destructive) {
                    transcriptionViewModel.cancelTranscription(taskID: task.id)
                } label: {
                    Label("Cancel", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            } else if task.state == .completed {
                Button {
                    showExportSheet = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)

                // Save button (shown when not yet saved, or to re-save)
                if transcriptionViewModel.isTaskSaved(task.id) {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .labelStyle(.iconOnly)
                } else {
                    Button {
                        transcriptionViewModel.saveSession(taskID: task.id)
                    } label: {
                        Label("Save", systemImage: "tray.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .help("Save this transcription to your library")
                }

                // Diarize button (separate speakers)
                if transcriptionViewModel.isDiarizing {
                    ProgressView()
                        .controlSize(.small)
                        .help("Separating speakers…")
                } else if transcriptionViewModel.isTaskDiarized(task.id) {
                    if let count = transcriptionViewModel.speakerCount(for: task.id) {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                                .foregroundStyle(.purple)
                            Text("\(count)")
                                .font(.caption.bold())
                            Text(count == 1 ? "speaker" : "speakers")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.purple.opacity(0.1), in: Capsule())
                        .help("Speakers separated — click to re-run")
                        .onTapGesture {
                            // Allow re-running diarization by clearing the flag.
                            transcriptionViewModel.diarizedTaskIDs.remove(task.id)
                            transcriptionViewModel.diarize(taskID: task.id)
                        }
                    }
                } else {
                    Button {
                        transcriptionViewModel.diarize(taskID: task.id)
                    } label: {
                        Label("Separate Speakers", systemImage: "person.2")
                    }
                    .buttonStyle(.bordered)
                    .help("Identify and label different speakers in the recording")
                }

                Button {
                    transcriptionViewModel.startTranscription(taskID: task.id)
                } label: {
                    Label("Re-transcribe", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            } else {
                // Detect Language button (only for WhisperKit engine)
                if task.engineType == .whisperKit && canTranscribe {
                    if transcriptionViewModel.isDetectingLanguage {
                        ProgressView()
                            .controlSize(.small)
                            .help("Detecting language…")
                    } else if let detection = transcriptionViewModel.detectedLanguage(for: task.id) {
                        // Show detected language as a pill
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .foregroundStyle(.blue)
                            Text(detection.languageName)
                                .font(.caption.bold())
                            Text("\(detection.confidencePercentage)%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.1), in: Capsule())
                        .help("Detected: \(detection.displayText)")
                    } else {
                        Button {
                            transcriptionViewModel.detectLanguage(taskID: task.id)
                        } label: {
                            Label("Detect Language", systemImage: "globe")
                        }
                        .buttonStyle(.bordered)
                        .help("Detect the spoken language before transcribing")
                    }
                }

                Button {
                    transcriptionViewModel.startTranscription(taskID: task.id)
                } label: {
                    Label("Transcribe", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canTranscribe)
            }

            // Word timestamps toggle
            if task.result != nil {
                Toggle(isOn: $showWordTimestamps) {
                    Label("Words", systemImage: "textformat")
                }
                .toggleStyle(.button)
                .controlSize(.small)
            }
        }
    }

    private var canTranscribe: Bool {
        if task.engineType.isLocal {
            return modelManager.selectedModel?.isDownloaded ?? false
        }
        return true
    }
}

// MARK: - Segment Row View

struct SegmentRowView: View {
    let segment: TranscriptionSegment
    let showWordTimestamps: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                // Timestamp
                VStack(alignment: .trailing) {
                    Text(segment.formattedStartTime)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(segment.formattedEndTime)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .frame(width: 80, alignment: .trailing)

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    if let speaker = segment.speaker {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(SpeakerColors.color(for: speaker))
                                .frame(width: 8, height: 8)
                            Text(speaker)
                                .font(.caption.bold())
                                .foregroundStyle(SpeakerColors.color(for: speaker))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(SpeakerColors.color(for: speaker).opacity(0.1), in: Capsule())
                    }

                    if showWordTimestamps, let words = segment.words {
                        // Word-level display
                        FlowLayout(spacing: 4) {
                            ForEach(words) { word in
                                Text(word.word)
                                    .font(.body)
                                    .background(
                                        word.probability > 0.8 ? Color.clear :
                                        word.probability > 0.5 ? Color.yellow.opacity(0.2) :
                                        Color.red.opacity(0.2)
                                    )
                                    .cornerRadius(2)
                            }
                        }
                    } else {
                        Text(segment.text)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }

                Spacer()
            }
        }
        .padding(.vertical, 2)
    }
}

/// Stable per-speaker color assignment for diarization labels.
enum SpeakerColors {
    private static let palette: [Color] = [
        .blue, .purple, .orange, .green, .pink, .teal, .indigo, .brown
    ]

    /// Map a speaker label like "Speaker 3" to a stable color.
    static func color(for speaker: String) -> Color {
        // Extract trailing number; fall back to hash.
        let digits = speaker.compactMap(\.wholeNumberValue)
        if let n = digits.last, n > 0 {
            return palette[(n - 1) % palette.count]
        }
        let hash = abs(speaker.hashValue)
        return palette[hash % palette.count]
    }
}

// MARK: - Metadata View

struct TranscriptionMetadataView: View {
    let task: TranscriptionTask
    let result: TranscriptionResult

    var body: some View {
        HStack(spacing: 16) {
            MetadataPill(
                icon: "globe",
                label: "Language",
                value: LanguageDetector.displayName(for: result.detectedLanguage)
            )
            MetadataPill(icon: "cpu", label: "Model", value: result.modelUsed)
            MetadataPill(icon: "text.word.spacing", label: "Words", value: "\(result.wordCount)")
            MetadataPill(icon: "clock", label: "Duration", value: TimeFormatter.formatDuration(result.audioDuration))
            MetadataPill(icon: "timer", label: "Processed", value: TimeFormatter.formatDuration(result.processingTime))

            if result.processingTime > 0 && result.audioDuration > 0 {
                MetadataPill(icon: "speedometer", label: "Speed", value: String(format: "%.1fx", result.audioDuration / result.processingTime))
            }

            Spacer()
        }
    }
}

struct MetadataPill: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.3))
        .cornerRadius(6)
    }
}

// MARK: - Progress View

struct TranscriptionProgressView: View {
    let task: TranscriptionTask

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
                .symbolEffect(.variableColor.iterative)

            Text(task.state.displayName)
                .font(.headline)

            ProgressView(value: task.progress)
                .frame(maxWidth: 300)

            Text("\(Int(task.progress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let result = task.result, !result.segments.isEmpty {
                Text("\(result.segments.count) segments found so far…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error View

struct TranscriptionErrorView: View {
    let task: TranscriptionTask
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Transcription Failed")
                .font(.headline)

            if let error = task.errorMessage {
                Text(error)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button("Try Again", action: retryAction)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Flow Layout

/// Simple flow layout for word-level display.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var width: CGFloat = 0
        var x: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                width = max(width, x - spacing)
                height += lineHeight + spacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        width = max(width, x - spacing)
        height += lineHeight

        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Save Status Toast

/// A transient toast that shows save status feedback.
/// Works with both `TranscriptionViewModel.SaveStatus` and `LiveTranscriptionViewModel.SaveStatus`.
struct SaveStatusToast: View {
    enum Kind {
        case saving, saved, failed
    }

    let kind: Kind
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            switch kind {
            case .saving:
                ProgressView()
                    .controlSize(.small)
            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.horizontal, 24)
    }
}

// Convenience initializers for each view model's SaveStatus
extension SaveStatusToast {
    init(status: TranscriptionViewModel.SaveStatus, onDismiss: @escaping () -> Void) {
        let kind: Kind
        switch status {
        case .saving: kind = .saving
        case .saved: kind = .saved
        case .failed: kind = .failed
        }
        self.init(kind: kind, message: status.message, onDismiss: onDismiss)
    }

    init(status: LiveTranscriptionViewModel.SaveStatus, onDismiss: @escaping () -> Void) {
        let kind: Kind
        switch status {
        case .saving: kind = .saving
        case .saved: kind = .saved
        case .failed: kind = .failed
        }
        self.init(kind: kind, message: status.message, onDismiss: onDismiss)
    }
}
