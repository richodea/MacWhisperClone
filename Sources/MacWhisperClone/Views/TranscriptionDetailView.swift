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

                Button {
                    transcriptionViewModel.startTranscription(taskID: task.id)
                } label: {
                    Label("Re-transcribe", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            } else {
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
                        Text(speaker)
                            .font(.caption.bold())
                            .foregroundStyle(.blue)
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

// MARK: - Metadata View

struct TranscriptionMetadataView: View {
    let task: TranscriptionTask
    let result: TranscriptionResult

    var body: some View {
        HStack(spacing: 16) {
            MetadataPill(icon: "globe", label: "Language", value: result.detectedLanguage.uppercased())
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
