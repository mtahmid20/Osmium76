import SwiftUI

struct SidebarView: View {
    @Environment(CompressionModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Form {
            Section("Preset") {
                Picker("", selection: presetBinding) {
                    ForEach(Preset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Text(model.options.preset.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Output Format") {
                Picker("Format", selection: formatBinding) {
                    ForEach(OutputFormat.encodableFormats) { format in
                        Label(format.displayName, systemImage: format.systemImage).tag(format)
                    }
                }
                .disabled(model.isRunning)

                if model.options.format == .webp {
                    Toggle("Lossless", isOn: $model.options.lossless)
                        .disabled(model.isRunning)
                }

                if model.options.format.usesLossyQuality && !model.options.lossless {
                    // Label and value share one row so the sidebar needs less
                    // height and the control stays fully visible when short.
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Quality")
                            Spacer(minLength: 4)
                            Text("\(Int((model.options.quality * 100).rounded()))%")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: qualityBinding,
                            in: model.options.format.qualityRange,
                            step: 0.01
                        )
                        .controlSize(.small)
                        .disabled(model.isRunning)
                    }
                    .padding(.vertical, 1)
                } else {
                    Text(model.options.lossless
                         ? "Lossless — quality is not used."
                         : "PNG is lossless — only resizing and metadata apply.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                resizeControls
            }

            Section("Privacy") {
                Toggle("Remove metadata", isOn: $model.options.stripMetadata)
                    .disabled(model.isRunning)
                Toggle("Remove location data", isOn: $model.options.stripLocation)
                    .disabled(model.isRunning)
                Toggle("Delete originals", isOn: $model.options.deleteOriginal)
                    .disabled(model.isRunning)
                Toggle("Skip when not smaller", isOn: $model.options.skipWhenNotSmaller)
                    .disabled(model.isRunning)
            }

            Section("Destination") {
                Toggle("Save next to originals", isOn: $model.options.writeAlongside)
                    .disabled(model.isRunning)

                if model.hasStagedDrops {
                    Label(
                        "Some images were dropped without a file location, so they will be saved to a folder you choose.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if !model.options.writeAlongside {
                    HStack {
                        Text(model.options.outputFolder?.lastPathComponent ?? "Choose…")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(model.options.outputFolder == nil ? .secondary : .primary)
                        Spacer()
                        Button("Choose") {
                            if let folder = FilePicker.chooseOutputFolder() {
                                model.options.outputFolder = folder
                                model.options.writeAlongside = false
                            }
                        }
                        .disabled(model.isRunning)
                    }
                } else {
                    TextField("Name suffix", text: $model.options.nameSuffix)
                        .disabled(model.isRunning)
                }

                Toggle("Never overwrite", isOn: $model.options.avoidOverwrite)
                    .disabled(model.isRunning)
            }

            Section("Performance") {
                Stepper(
                    "Parallel jobs: \(model.options.parallelismClamped)",
                    value: $model.options.parallelism,
                    in: 1...12
                )
                .disabled(model.isRunning)
            }

            if OutputFormat.encodableFormats.isEmpty {
                Section {
                    Text("No encoders available on this system.")
                        .foregroundStyle(.red)
                }
            }

            if !OutputFormat.isEncodable(.webp) {
                Section {
                    Text(WebPEncoder.unavailableReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var resizeControls: some View {
        // A menu picker rather than segmented: three segments with icons do not
        // fit the sidebar width without truncating, and the icons add nothing
        // next to the row label.
        Picker("Size", selection: resizeModeBinding) {
            ForEach(ResizeMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.menu)
        .disabled(model.isRunning)

        switch model.options.resizeMode {
        case .full:
            EmptyView()
        case .pixels:
            Picker("Max size", selection: maxDimensionBinding) {
                ForEach(CompressionOptions.dimensionChoices) { choice in
                    Text(choice.title).tag(choice.value)
                }
            }
            .disabled(model.isRunning)
        case .percent:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Scale")
                    Spacer()
                    Text("\(Int((model.options.scalePercent * 100).rounded()))%")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: scalePercentBinding, in: 0.05...1.0, step: 0.05)
                    .disabled(model.isRunning)
            }
        }

        Text(model.options.resizeSummary)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var presetBinding: Binding<Preset> {
        Binding(
            get: { model.options.preset },
            set: { model.applyPreset($0) }
        )
    }

    private var formatBinding: Binding<OutputFormat> {
        Binding(
            get: { model.options.format },
            set: { newFormat in
                model.updateOptions { options in
                    options.format = newFormat
                    options.quality = min(options.quality, newFormat.qualityRange.upperBound)
                    options.quality = max(options.quality, newFormat.qualityRange.lowerBound)
                }
            }
        )
    }

    private var qualityBinding: Binding<Double> {
        Binding(
            get: { model.options.quality },
            set: { newValue in
                model.updateOptions { options in
                    let range = options.format.qualityRange
                    options.quality = min(max(newValue, range.lowerBound), range.upperBound)
                }
            }
        )
    }

    private var resizeModeBinding: Binding<ResizeMode> {
        Binding(
            get: { model.options.resizeMode },
            set: { value in model.options.selectResizeMode(value) }
        )
    }

    private var maxDimensionBinding: Binding<Int> {
        Binding(
            get: { model.options.maxDimension },
            set: { value in model.updateOptions { $0.maxDimension = value } }
        )
    }

    private var scalePercentBinding: Binding<Double> {
        Binding(
            get: { model.options.scalePercent },
            set: { value in
                model.updateOptions { options in
                    options.resizeMode = .percent
                    options.scalePercent = min(max(value, 0.05), 1.0)
                }
            }
        )
    }
}
