import AppKit
import SwiftUI

struct JobTableView: View {
    @Environment(CompressionModel.self) private var model

    @State private var sortOrder: [KeyPathComparator<ImageJob>] = [
        KeyPathComparator(\ImageJob.displayName, order: .forward)
    ]

    var body: some View {
        @Bindable var model = model

        Group {
            if model.jobs.isEmpty {
                EmptyStateView()
            } else {
                Table(model.visibleJobs, selection: $model.selection, sortOrder: $sortOrder) {
                    TableColumn("File", value: \.displayName) { job in
                        HStack(spacing: 10) {
                            ThumbnailCell(job: job)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.displayName)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(job.folderPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                        }
                        .help(job.sourceURL.path)
                    }
                    .width(min: 200, ideal: 320)

                    TableColumn("Dimensions") { job in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ByteFormat.pixels(job.pixelWidth, job.pixelHeight))
                            if let width = job.outputPixelWidth, job.state == .done {
                                Text(ByteFormat.pixels(width, job.outputPixelHeight ?? job.pixelHeight))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .monospacedDigit()
                    }
                    .width(min: 110, ideal: 120)

                    TableColumn("Type") { job in
                        Text(job.sourceFormat)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 50, ideal: 60)

                    TableColumn("Original") { job in
                        Text(ByteFormat.string(job.originalSize))
                            .monospacedDigit()
                    }
                    .width(min: 80, ideal: 90)

                    TableColumn("Compressed") { job in
                        if let outputSize = job.outputSize {
                            Text(ByteFormat.string(outputSize))
                                .monospacedDigit()
                        } else {
                            Text("—").foregroundStyle(.tertiary)
                        }
                    }
                    .width(min: 90, ideal: 100)

                    TableColumn("Saved") { job in
                        SavingsCell(job: job)
                    }
                    .width(min: 80, ideal: 90)

                    TableColumn("Status") { job in
                        StatusCell(job: job)
                    }
                    .width(min: 90, ideal: 110)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .contextMenu(forSelectionType: ImageJob.ID.self) { ids in
                    menu(for: ids)
                } primaryAction: { ids in
                    reveal(ids)
                }
            }
        }
    }

    @ViewBuilder
    private func menu(for ids: Set<ImageJob.ID>) -> some View {
        Button("Show in Finder") { reveal(ids) }
            .disabled(ids.isEmpty)
        Button("Copy Summary") { model.copySummary() }
            .disabled(ids.count != 1)
        Divider()
        Button("Remove from List") { model.remove(ids) }
            .disabled(model.isRunning)
        Button("Clear Completed") { model.clearFinished() }
            .disabled(model.isRunning)
    }

    private func reveal(_ ids: Set<ImageJob.ID>) {
        guard !ids.isEmpty else { return }
        if ids.count == 1, let id = ids.first, let job = model.jobs.first(where: { $0.id == id }) {
            model.reveal(job)
        } else {
            let urls = model.jobs.filter { ids.contains($0.id) }.compactMap { $0.outputURL }
            NSWorkspace.shared.activateFileViewerSelecting(urls.isEmpty ? model.jobs.map(\.sourceURL) : urls)
        }
    }
}

private struct ThumbnailCell: View {
    let job: ImageJob

    var body: some View {
        Group {
            if let image = ImageCache.shared.thumbnail(for: job) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.tertiary)
                    .padding(4)
            }
        }
        .frame(width: 40, height: 40)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }
}

private struct SavingsCell: View {
    let job: ImageJob

    var body: some View {
        if let fraction = job.savedFraction, job.state == .done {
            HStack(spacing: 6) {
                ProgressView(value: max(0, fraction))
                    .progressViewStyle(.linear)
                    .frame(width: 36)
                Text("\(Int((fraction * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(fraction > 0 ? Color.green : Color.secondary)
            }
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }
}

private struct StatusCell: View {
    let job: ImageJob

    var body: some View {
        switch job.state {
        case .pending:
            Label("Queued", systemImage: "circle.dashed")
                .foregroundStyle(.secondary)
        case .processing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Working")
            }
        case .done:
            Label("Done", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .skipped:
            Label("Kept", systemImage: "equal.circle")
                .foregroundStyle(.secondary)
                .help(job.message ?? "")
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(job.message ?? "")
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Drop images or folders here")
                .font(.title3.weight(.medium))
            Text("JPEG, PNG, HEIC, WebP, TIFF, BMP and GIF are supported.\nSub-folders are scanned automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
