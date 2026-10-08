import AppKit
import SwiftUI

struct PreviewPane: View {
    @Environment(CompressionModel.self) private var model

    @State private var originalImage: NSImage? = nil
    @State private var resultImage: NSImage? = nil
    @State private var isLoading = false
    @State private var split: CGFloat = 0.5
    @State private var zoom: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            if let job = model.selectedJob {
                header(for: job)
                Divider()
                canvas(for: job)
                Divider()
                footer(for: job)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Select an image to compare before and after")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.quaternary.opacity(0.25))
    }

    // MARK: - Header

    private func header(for job: ImageJob) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(job.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(job.sourceURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            Picker("", selection: zoomBinding) {
                Text("Fit").tag(CGFloat(1))
                Text("1.5×").tag(CGFloat(1.5))
                Text("2×").tag(CGFloat(2))
                Text("4×").tag(CGFloat(4))
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()

            Button {
                split = split > 0.5 ? 0 : 1
            } label: {
                Image(systemName: "arrow.left.and.right")
            }
            .help("Flip between original and compressed")

            Button {
                model.reveal(job)
            } label: {
                Image(systemName: "folder")
            }
            .help("Show in Finder")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Canvas

    @ViewBuilder
    private func canvas(for job: ImageJob) -> some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                ComparisonCanvas(
                    original: originalImage,
                    result: resultImage,
                    split: splitBinding
                )
                .frame(
                    width: max(geo.size.width, 1) * zoom,
                    height: max(geo.size.height, 1) * zoom
                )
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .frame(minHeight: 180)
        .task(id: loadToken(for: job)) {
            await loadImages(for: job)
        }
    }

    private func loadToken(for job: ImageJob) -> String {
        "\(job.id.uuidString)-\(job.state.rawValue)"
    }

    @MainActor
    private func loadImages(for job: ImageJob) async {
        let jobID = job.id
        isLoading = true
        defer { isLoading = false }

        let sourceURL = job.sourceURL
        let outputURL = job.outputURL
        let originalPreview = job.originalPreview
        let resultPreview = job.preview

        let loaded = await Task.detached(priority: .userInitiated) { () -> (NSImage?, NSImage?) in
            let before: NSImage? = {
                if let originalPreview { return ImageCache.shared.image(from: originalPreview) }
                return ImageCache.shared.preview(for: sourceURL)
            }()
            let after: NSImage? = {
                if let resultPreview { return ImageCache.shared.image(from: resultPreview) }
                guard let outputURL,
                      FileManager.default.fileExists(atPath: outputURL.path) else { return nil }
                return ImageCache.shared.preview(for: outputURL)
            }()
            return (before, after)
        }.value

        // The selection may have moved on while the decode was running.
        guard model.selectedJob?.id == jobID else { return }

        originalImage = loaded.0
        resultImage = loaded.1
    }

    // MARK: - Footer

    private func footer(for job: ImageJob) -> some View {
        HStack(alignment: .top, spacing: 16) {
            LabeledContent("Before") {
                Text("\(ByteFormat.string(job.originalSize)) · \(ByteFormat.pixels(job.pixelWidth, job.pixelHeight))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            LabeledContent("After") {
                if job.state == .done, let outputSize = job.outputSize {
                    let width = job.outputPixelWidth ?? job.pixelWidth
                    let height = job.outputPixelHeight ?? job.pixelHeight
                    Text("\(ByteFormat.string(outputSize)) · \(ByteFormat.pixels(width, height))")
                        .monospacedDigit()
                } else if job.state == .skipped {
                    Text("unchanged").foregroundStyle(.secondary)
                } else {
                    Text("not compressed yet").foregroundStyle(.tertiary)
                }
            }

            if let fraction = job.savedFraction, job.state == .done {
                Text("\(Int((fraction * 100).rounded()))% smaller")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(fraction > 0 ? Color.green : Color.secondary)
                    .monospacedDigit()
            }

            Spacer()

            if let message = job.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(job.state == .failed ? Color.orange : Color.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .font(.callout)
    }

    // MARK: - Bindings

    private var splitBinding: Binding<CGFloat> {
        Binding(get: { split }, set: { split = $0 })
    }

    private var zoomBinding: Binding<CGFloat> {
        Binding(get: { zoom }, set: { zoom = $0 })
    }
}

private struct ComparisonCanvas: View {
    let original: NSImage?
    let result: NSImage?
    @Binding var split: CGFloat

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            ZStack(alignment: .leading) {
                CheckerboardBackground()
                    .frame(width: width, height: height)

                imageLayer(original)
                    .frame(width: width, height: height)

                imageLayer(result)
                    .frame(width: width, height: height)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: max(0, min(width, width * split)))
                    }

                Rectangle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 1.5)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: max(0, min(width - 1.5, width * split)))
                    .allowsHitTesting(false)

                handle
                    .offset(x: max(0, min(width - 26, width * split - 13)))
                    .allowsHitTesting(false)

                if split > 0.12 {
                    badge("ORIGINAL", alignment: .leading, width: width)
                        .allowsHitTesting(false)
                }
                if split < 0.88 {
                    badge(result == nil ? "ORIGINAL" : "COMPRESSED", alignment: .trailing, width: width)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        split = min(max(value.location.x / max(width, 1), 0), 1)
                    }
            )
        }
    }

    private var handle: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
                .frame(width: 26, height: 26)
                .shadow(radius: 3)
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.primary)
        }
    }

    private func badge(_ text: String, alignment: Alignment, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule())
            .foregroundStyle(.white)
            .frame(width: width, alignment: alignment)
            .padding(10)
    }

    @ViewBuilder
    private func imageLayer(_ image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "photo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.tertiary)
                .padding(24)
        }
    }
}

private struct CheckerboardBackground: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 12
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var column = 0
                var x: CGFloat = 0
                while x < size.width {
                    if (row + column) % 2 == 0 {
                        context.fill(
                            Path(CGRect(x: x, y: y, width: tile, height: tile)),
                            with: .color(Color.gray.opacity(0.18))
                        )
                    }
                    x += tile
                    column += 1
                }
                y += tile
                row += 1
            }
        }
        .drawingGroup()
    }
}
