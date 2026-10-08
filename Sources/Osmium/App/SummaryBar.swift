import SwiftUI

struct SummaryBar: View {
    @Environment(CompressionModel.self) private var model
    @Binding var showsPreview: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Picker("", selection: filterBinding) {
                    ForEach(JobFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                .disabled(model.isRunning)

                if model.failedCount > 0 {
                    Text("\(model.failedCount) failed")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Spacer()

                Button {
                    showsPreview.toggle()
                } label: {
                    Label("Preview", systemImage: showsPreview ? "rectangle.bottomhalf.insetfilled" : "rectangle")
                }
                .help(showsPreview ? "Hide the comparison pane" : "Show the comparison pane")
            }

            HStack(spacing: 14) {
                if model.isScanning {
                    ProgressView().controlSize(.small)
                    Text("Reading files…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if model.finishedCount > 0 {
                    StatBlock(
                        title: "Original",
                        value: ByteFormat.string(model.totalOriginalBytes)
                    )
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    StatBlock(
                        title: "Compressed",
                        value: ByteFormat.string(model.totalOutputBytes)
                    )
                    SavingsBadge(
                        percent: model.savedPercent,
                        bytes: model.totalSavedBytes,
                        grew: model.isRegression
                    )
                } else {
                    Text("\(model.jobs.count) image\(model.jobs.count == 1 ? "" : "s") in the queue")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if model.isRunning {
                    Button(role: .cancel) {
                        model.cancel()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                }

                Button {
                    model.start()
                } label: {
                    Label("Compress", systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canStart)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var filterBinding: Binding<JobFilter> {
        Binding(get: { model.filter }, set: { model.filter = $0 })
    }
}

private struct StatBlock: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.medium))
                .monospacedDigit()
        }
    }
}

private struct SavingsBadge: View {
    let percent: Double
    let bytes: Int64
    let grew: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // "Reduction", not "Saved": originals are kept by default, so these
            // are smaller copies rather than space freed on disk.
            Text(grew ? "Increased" : "Reduction")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(String(format: "%.1f", percent))% · \(ByteFormat.string(abs(bytes)))")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .help("How much smaller the compressed copies are than the originals. The originals are kept unless \"Delete originals\" is on.")
    }

    private var tint: Color {
        if grew { return .orange }
        return percent > 0 ? .green : .secondary
    }
}
