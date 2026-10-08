import SwiftUI
import ImageIO
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(CompressionModel.self) private var model
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showsPreview = true
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 300, max: 380)
        } detail: {
            VStack(spacing: 0) {
                JobTableView()
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        SummaryBar(showsPreview: $showsPreview)
                    }
                if showsPreview {
                    Divider()
                    PreviewPane()
                        .frame(minHeight: 240, idealHeight: 300)
                }
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.tint, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                        .background(.tint.opacity(0.07))
                        .allowsHitTesting(false)
                }
            }
            // Only `fileURL` is declared. Listing `.image` alongside it makes SwiftUI hand
            // over a provider narrowed to `public.jpeg` alone
            // (`conforms(fileURL) == false`), so a Finder drop loses its path and
            // can only be treated as raw bytes. Sources that offer image data
            // without a file location still arrive here; they fall through to
            // the staging branch below.
            .onDrop(
                of: [UTType.fileURL],
                isTargeted: $isDropTargeted,
                perform: handleDrop(providers:)
            )
        }
        .toolbar { toolbarContent }
        .navigationTitle("Osmium")
    }

    // MARK: - Drops

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        Task { @MainActor in
            var urls: [URL] = []
            var payloads: [Data] = []

            for provider in providers {
                if let url = await DropItemLoader.fileURL(from: provider) {
                    urls.append(url)
                } else if let data = await loadImageData(from: provider) {
                    payloads.append(data)
                }
            }

            if !urls.isEmpty { model.addFiles(urls) }
            if !payloads.isEmpty { model.addFiles(ImageDropStaging.stage(payloads)) }
        }
        return true
    }

    

    private func loadImageData(from provider: NSItemProvider) async -> Data? {
        let identifier = provider.registeredTypeIdentifiers.first {
            UTType($0)?.conforms(to: .image) == true
        } ?? UTType.image.identifier

        return await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            let resumed = AtomicFlag()
            _ = provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                guard resumed.claim() else { return }
                continuation.resume(returning: data)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                FilePicker.openFiles(into: model)
            } label: {
                Label("Add Files", systemImage: "plus")
            }
            .help("Add images to the queue")
            .disabled(model.isRunning)

            Button {
                FilePicker.openFolder(into: model)
            } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
            }
            .help("Add every image inside a folder")
            .disabled(model.isRunning)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.resetQueue()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .help("Put every image back in the queue")
            .disabled(model.isRunning || model.jobs.isEmpty)

            Button {
                model.revealAllOutputs()
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            .help("Reveal the results in Finder")
            .disabled(model.jobs.isEmpty)
        }
    }
}

/// One-shot flag so a provider that calls back twice cannot resume a
/// continuation twice.
private final class AtomicFlag: @unchecked Sendable {
    private var used = false
    private let lock = NSLock()

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !used else { return false }
        used = true
        return true
    }
}

/// Writes image payloads (dropped from Photos, Safari, …) into a temp folder so
/// the rest of the pipeline only ever deals with file URLs. See `DropStaging`
/// for how those scratch files are cleaned up and where their output goes.
enum ImageDropStaging {
    static func stage(_ payloads: [Data]) -> [URL] {
        let folder = DropStaging.folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var urls: [URL] = []
        for payload in payloads {
            guard let fileExtension = suggestedExtension(for: payload) else { continue }
            let url = folder
                .appendingPathComponent("Drop-\(UUID().uuidString.prefix(8))")
                .appendingPathExtension(fileExtension)
            do {
                try payload.write(to: url, options: .atomic)
                urls.append(url)
            } catch {
                continue
            }
        }
        return urls
    }

    private static func suggestedExtension(for payload: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(payload as CFData, nil) else { return nil }
        guard let type = CGImageSourceGetType(source) else { return nil }
        return UTType(type as String)?.preferredFilenameExtension ?? "png"
    }
}
