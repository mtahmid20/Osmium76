import SwiftUI

struct SettingsView: View {
    @Environment(CompressionModel.self) private var model

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            formats
                .tabItem { Label("Formats", systemImage: "photo.badge.arrow.down") }
            about
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 300)
    }

    private var general: some View {
        Form {
            Section("Defaults") {
                Picker("Preset", selection: presetBinding) {
                    ForEach(Preset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                Stepper(
                    "Parallel jobs: \(model.options.parallelismClamped)",
                    value: parallelismBinding,
                    in: 1...12
                )
            }

            Section {
                Button("Reveal Osmium in Finder") {
                    NSWorkspace.shared.selectFile(
                        nil,
                        inFileViewerRootedAtPath: Bundle.main.bundlePath
                    )
                }
                Button("Clear All") { model.clearAll() }
                    .disabled(model.isRunning || model.jobs.isEmpty)
            }
        }
        .formStyle(.grouped)
    }

    private var formats: some View {
        Form {
            Section("Encoders available on this Mac") {
                ForEach(OutputFormat.allCases) { format in
                    HStack {
                        Label(format.displayName, systemImage: format.systemImage)
                        Spacer()
                        if OutputFormat.isEncodable(format) {
                            Text(format == .webp ? "libwebp" : "ImageIO")
                                .foregroundStyle(.green)
                        } else {
                            Text("Unavailable")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !OutputFormat.isEncodable(.webp) {
                Section {
                    Text(WebPEncoder.unavailableReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("Extensions read: \(ImageScanner.inputExtensions.sorted().joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        Form {
            Section {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                LabeledContent("Engine", value: "ImageIO / Core Graphics / libwebp")
                LabeledContent("Requires", value: "macOS 14 or later")
            }
            Section {
                Text("Compression happens entirely on this Mac. No image data leaves your machine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var presetBinding: Binding<Preset> {
        Binding(get: { model.options.preset }, set: { model.applyPreset($0) })
    }

    private var parallelismBinding: Binding<Int> {
        Binding(
            get: { model.options.parallelism },
            set: { model.options.parallelism = min(max($0, 1), 12) }
        )
    }
}
