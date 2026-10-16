import SwiftUI

// MARK: - Export Sheet View

/// Sheet for exporting transcription results to various formats.
struct ExportSheetView: View {

    let task: TranscriptionTask
    @EnvironmentObject var transcriptionViewModel: TranscriptionViewModel
    @Environment(\.dismiss) var dismiss

    @State private var selectedFormat: ExportFormat = .txt
    @State private var includeTimestamps = true
    @State private var includeMetadata = true
    @State private var exportURL: URL?
    @State private var showSavePanel = false

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Export Transcription")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.borderless)
            }

            // Format selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Format")
                    .font(.subheadline.bold())

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                    ForEach(ExportFormat.allCases) { format in
                        FormatCard(format: format, isSelected: selectedFormat == format) {
                            selectedFormat = format
                        }
                    }
                }
            }

            // Options
            VStack(alignment: .leading, spacing: 8) {
                Text("Options")
                    .font(.subheadline.bold())

                Toggle("Include timestamps", isOn: $includeTimestamps)
                    .disabled(selectedFormat == .txt)

                Toggle("Include metadata", isOn: $includeMetadata)
                    .disabled(selectedFormat == .txt || selectedFormat == .srt || selectedFormat == .vtt)
            }

            // Preview
            if let result = task.result {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.subheadline.bold())

                    ScrollView {
                        Text(TranscriptExporter.export(result, to: selectedFormat))
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 150)
                    .padding(8)
                    .background(.quaternary.opacity(0.3))
                    .cornerRadius(8)
                }
            }

            Spacer()

            // Export button
            HStack {
                Spacer()
                Button("Export") {
                    performExport()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 500, height: 600)
    }

    // MARK: - Export

    private func performExport() {
        guard let result = task.result else { return }

        let panel = NSSavePanel()
        panel.title = "Export Transcription"
        panel.nameFieldStringValue = "\(task.audioFile.name).\(selectedFormat.fileExtension)"
        panel.allowedContentTypes = []

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let content = TranscriptExporter.export(result, to: selectedFormat)
                try content.write(to: url, atomically: true, encoding: .utf8)
                exportURL = url
                Logger.info("Exported to: \(url.path)")
                dismiss()
            } catch {
                transcriptionViewModel.showError(message: "Export failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Format Card

struct FormatCard: View {
    let format: ExportFormat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: format.icon)
                    .font(.title2)
                Text(format.rawValue)
                    .font(.caption)
                Text(".\(format.fileExtension)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
