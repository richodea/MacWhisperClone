import SwiftUI

// MARK: - Model List View

/// Shows available WhisperKit models with download/manage controls.
/// Design direction: instrument-panel aesthetic — precise, technical,
/// data-dense. Models are presented as spec sheets, not generic cards.
struct ModelListView: View {

    @EnvironmentObject var modelManager: ModelManager

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Summary header
                summaryHeader

                Divider()
                    .opacity(0.5)

                // Model list
                LazyVStack(spacing: 0) {
                    ForEach(Array(modelManager.models.enumerated()), id: \.element.id) { index, model in
                        ModelRowView(model: model, index: index)
                            .environmentObject(modelManager)

                        if index < modelManager.models.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                                .opacity(0.3)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Summary Header

    private var summaryHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Models")
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.bold)

                Text("\(modelManager.downloadedModels.count) of \(modelManager.models.count) ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if modelManager.hasDownloadedModel {
                if let selected = modelManager.selectedModel {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                        Text("Using \(selected.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Model Row View

struct ModelRowView: View {
    let model: WhisperModel
    let index: Int
    @EnvironmentObject var modelManager: ModelManager

    private var isSelected: Bool {
        modelManager.selectedModelID == model.id
    }

    private var downloadState: ModelDownloadState? {
        modelManager.downloadStates[model.id]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Status indicator column
            statusColumn

            // Model info
            VStack(alignment: .leading, spacing: 6) {
                // Name row
                HStack(spacing: 8) {
                    Text(model.name)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)

                    if model.isDownloaded {
                        statusBadge
                    }

                    Spacer()
                }

                // Description
                Text(model.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // Spec row
                specRow

                // Download progress or error
                if let state = downloadState {
                    progressSection(state)
                }
            }

            // Action column
            actionColumn
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.06)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if model.isDownloaded {
                modelManager.selectModel(model.id)
            }
        }
    }

    // MARK: - Status Column

    private var statusColumn: some View {
        VStack(spacing: 0) {
            if model.isDownloaded {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            } else if model.isDownloading {
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
                    .foregroundStyle(.blue)
            } else {
                Image(systemName: "cloud")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 24)
        .padding(.top, 2)
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        Text(isSelected ? "ACTIVE" : "READY")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(isSelected ? .white : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                isSelected
                    ? Color.accentColor
                    : Color.secondary.opacity(0.15)
            )
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    // MARK: - Spec Row

    private var specRow: some View {
        HStack(spacing: 0) {
            specItem(label: "Size", value: model.size)
            specDivider
            specItem(label: "Params", value: model.parameters)
            if model.isDownloaded, let path = model.localPath {
                specDivider
                specItem(label: "Path", value: path.lastPathComponent)
            }
        }
        .padding(.top, 2)
    }

    private func specItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.trailing, 12)
    }

    private var specDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.15))
            .frame(width: 1, height: 22)
            .padding(.trailing, 12)
    }

    // MARK: - Progress Section

    @ViewBuilder
    private func progressSection(_ state: ModelDownloadState) -> some View {
        switch state {
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.15))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 4)

                HStack {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(.top, 4)

        case .failed(let error):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                Text(error)
                    .font(.caption2)
            }
            .foregroundStyle(.red)
            .padding(.top, 4)

        case .completed:
            EmptyView()

        case .idle:
            EmptyView()
        }
    }

    // MARK: - Action Column

    @ViewBuilder
    private var actionColumn: some View {
        VStack(spacing: 6) {
            if model.isDownloaded {
                if !isSelected {
                    Button {
                        modelManager.selectModel(model.id)
                    } label: {
                        Text("Use")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Button(role: .destructive) {
                    modelManager.deleteModel(model.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Delete model")
            } else if model.isDownloading {
                Button {
                    modelManager.cancelDownload(model.id)
                } label: {
                    Text("Cancel")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button {
                    modelManager.downloadModel(model.id)
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(width: 80)
        .padding(.top, 2)
    }
}
