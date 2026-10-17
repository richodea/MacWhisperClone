import SwiftUI

// MARK: - Live Transcription View

/// View for live (real-time) transcription with mic or system audio capture.
struct LiveTranscriptionView: View {

    // MARK: Environment

    @EnvironmentObject var liveViewModel: LiveTranscriptionViewModel
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var settingsViewModel: SettingsViewModel

    // MARK: Binding

    @Binding var sidebarSelection: SidebarItem?

    // MARK: State

    @State private var showExportSheet = false
    @State private var selectedExportFormat: ExportFormat = .txt

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            // Source selector
            sourceSelector

            Divider()

            // Recording controls
            recordingControls

            Divider()

            // Transcript display
            transcriptDisplay
        }
        .navigationTitle("Live Transcription")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !liveViewModel.segments.isEmpty {
                    // Save button (when stopped and not yet saved)
                    if liveViewModel.state == .stopped && !liveViewModel.isSessionSaved {
                        Button {
                            liveViewModel.saveLiveSession()
                        } label: {
                            Label("Save", systemImage: "tray.and.arrow.down")
                        }
                        .help("Save this session to your library")
                    }

                    // Saved indicator
                    if liveViewModel.isSessionSaved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .labelStyle(.iconOnly)
                    }

                    Button {
                        showExportSheet = true
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showExportSheet) {
            LiveExportSheet(viewModel: liveViewModel)
        }
        .overlay(alignment: .bottom) {
            if let status = liveViewModel.saveStatus {
                SaveStatusToast(status: status) {
                    liveViewModel.clearSaveStatus()
                }
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: liveViewModel.saveStatus)
    }

    // MARK: - Source Selector

    private var sourceSelector: some View {
        HStack(spacing: 16) {
            ForEach(LiveTranscriptionSource.allCases) { source in
                Button {
                    liveViewModel.setSource(source)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: source.icon)
                            .font(.title2)
                        Text(source.rawValue)
                            .font(.caption)
                        Text(source.description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        liveViewModel.source == source
                            ? Color.accentColor.opacity(0.15)
                            : Color(nsColor: .controlBackgroundColor)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(liveViewModel.isLive)
            }
        }
        .padding(16)
    }

    // MARK: - Recording Controls

    private var recordingControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 24) {
                // Status indicator
                statusIndicator

                // Duration
                VStack(spacing: 2) {
                    Text("Duration")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(TimeFormatter.formatDuration(liveViewModel.recordingDuration))
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.semibold)
                }

                // Segments count
                VStack(spacing: 2) {
                    Text("Segments")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(liveViewModel.segments.count)")
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.semibold)
                }

                Spacer()

                // Start/Stop button
                startStopButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Audio level bar
            if liveViewModel.isLive {
                audioLevelBar
            }
        }
    }

    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .scaleEffect(liveViewModel.isLive ? 1.0 : 0.8)
                .animation(
                    liveViewModel.isLive
                        ? .easeInOut(duration: 0.6).repeatForever()
                        : .default,
                    value: liveViewModel.isLive
                )

            Text(liveViewModel.state.displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
    }

    private var statusColor: Color {
        switch liveViewModel.state {
        case .listening: return .green
        case .transcribing: return .orange
        case .loadingModel: return .blue
        case .requestingPermission: return .yellow
        case .error: return .red
        case .stopped: return .gray
        case .idle: return .gray
        }
    }

    private var startStopButton: some View {
        Group {
            if liveViewModel.isLive {
                Button(role: .destructive) {
                    liveViewModel.stopLiveTranscription()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(width: 100)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    liveViewModel.startLiveTranscription()
                } label: {
                    Label("Start", systemImage: "mic.fill")
                        .frame(width: 100)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
    }

    private var audioLevelBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<20, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: i, level: liveViewModel.audioLevel))
                    .frame(width: 4, height: 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func barColor(for index: Int, level: Float) -> Color {
        let threshold = Float(index) / 20.0
        if level >= threshold {
            if index < 12 {
                return .green
            } else if index < 16 {
                return .yellow
            } else {
                return .red
            }
        }
        return Color.secondary.opacity(0.2)
    }

    // MARK: - Transcript Display

    private var transcriptDisplay: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if liveViewModel.segments.isEmpty && !liveViewModel.isLive {
                    emptyState
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(liveViewModel.segments) { segment in
                            segmentView(segment)
                                .id(segment.id)
                        }

                        // Partial text indicator
                        if !liveViewModel.partialText.isEmpty && liveViewModel.isLive {
                            HStack(spacing: 8) {
                                Image(systemName: "ellipsis.bubble")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                Text(liveViewModel.partialText)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .italic()
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
            .onChange(of: liveViewModel.segments.count) { _, _ in
                withAnimation {
                    proxy.scrollTo(liveViewModel.segments.last?.id, anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()

            // Central waveform icon
            VStack(spacing: 20) {
                // Animated waveform bars
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 3, height: CGFloat([18, 32, 12, 40, 22, 36, 16][i]))
                    }
                }

                Text("Live Transcription")
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.bold)

                Text("Capture audio from your microphone or system output and transcribe it in real time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            Spacer()

            // Setup checklist
            VStack(alignment: .leading, spacing: 0) {
                setupStep(
                    number: 1,
                    title: "Download a model",
                    detail: modelManager.hasDownloadedModel
                        ? modelManager.selectedModel?.name ?? "Ready"
                        : "Required for transcription",
                    isDone: modelManager.hasDownloadedModel,
                    action: !modelManager.hasDownloadedModel ? {
                        sidebarSelection = .models
                    } : nil,
                    actionLabel: "Go to Models"
                )

                Divider()
                    .opacity(0.3)
                    .padding(.leading, 32)

                setupStep(
                    number: 2,
                    title: "Choose a source",
                    detail: liveViewModel.source == .microphone ? "Microphone selected" : "System audio selected",
                    isDone: true,
                    action: nil,
                    actionLabel: nil
                )

                Divider()
                    .opacity(0.3)
                    .padding(.leading, 32)

                setupStep(
                    number: 3,
                    title: "Press Start",
                    detail: "Recording begins immediately",
                    isDone: false,
                    action: nil,
                    actionLabel: nil
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.15))
            )
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func setupStep(
        number: Int,
        title: String,
        detail: String,
        isDone: Bool,
        action: (() -> Void)?,
        actionLabel: String?
    ) -> some View {
        HStack(spacing: 12) {
            // Step number / checkmark
            ZStack {
                Circle()
                    .fill(isDone ? Color.green : Color.secondary.opacity(0.15))
                    .frame(width: 22, height: 22)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let action, let actionLabel {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 10)
    }

    private func segmentView(_ segment: TranscriptionSegment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(segment.formattedStartTime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if let speaker = segment.speaker {
                    Text(speaker)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                }

                Spacer()
            }

            Text(segment.text)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .padding(.horizontal, 12)
    }
}

// MARK: - Live Export Sheet

struct LiveExportSheet: View {
    @ObservedObject var viewModel: LiveTranscriptionViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedFormat: ExportFormat = .txt
    @State private var exportedURL: URL?
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Export Live Transcript")
                .font(.headline)

            Picker("Format", selection: $selectedFormat) {
                ForEach(ExportFormat.allCases) { format in
                    Label(format.rawValue, systemImage: format.icon)
                        .tag(format)
                }
            }
            .pickerStyle(.radioGroup)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Export") {
                    do {
                        let url = try viewModel.exportTranscript(format: selectedFormat)
                        exportedURL = url
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
        .alert("Export Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}
