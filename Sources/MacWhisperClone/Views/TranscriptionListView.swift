import SwiftUI

// MARK: - Transcription List View

/// Shows the list of transcription tasks with import button.
struct TranscriptionListView: View {

    @EnvironmentObject var transcriptionViewModel: TranscriptionViewModel
    @Binding var showFileImporter: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Transcriptions")
                    .font(.headline)
                Spacer()
                Button {
                    showFileImporter = true
                } label: {
                    Label("Import", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // List
            if transcriptionViewModel.tasks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No transcriptions yet")
                        .foregroundStyle(.secondary)
                    Button("Import Audio File") {
                        showFileImporter = true
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $transcriptionViewModel.selectedTaskID) {
                    ForEach(transcriptionViewModel.tasks) { task in
                        TranscriptionRowView(task: task)
                            .tag(task.id)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    transcriptionViewModel.deleteTask(taskID: task.id)
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

// MARK: - Transcription Row View

struct TranscriptionRowView: View {
    let task: TranscriptionTask

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: task.state.isRunning ? "waveform" : statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.caption)

                Text(task.audioFile.name)
                    .font(.body)
                    .lineLimit(1)
                    .fontWeight(.medium)

                Spacer()

                if task.state.isRunning {
                    ProgressView(value: task.progress)
                        .frame(width: 50)
                        .controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                Text(task.audioFile.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("·")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(task.engineType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let result = task.result {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(result.wordCount) words")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if task.state == .failed, let error = task.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch task.state {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "minus.circle.fill"
        default: return "circle"
        }
    }

    private var statusColor: Color {
        switch task.state {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        default: return .blue
        }
    }
}
