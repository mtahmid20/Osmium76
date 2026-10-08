import Foundation
import AppKit
import Observation

@MainActor
@Observable
final class CompressionModel {

    var jobs: [ImageJob] = []
    var options = CompressionOptions()
    var isRunning = false
    var isScanning = false
    var filter: JobFilter = .all
    var selection: UUID? = nil

    private var runTask: Task<Void, Never>?

    // MARK: - Derived state

    var visibleJobs: [ImageJob] {
        switch filter {
        case .all: return jobs
        case .pending: return jobs.filter { !$0.state.isFinished }
        case .done: return jobs.filter { $0.state == .done }
        case .skipped: return jobs.filter { $0.state == .skipped }
        case .failed: return jobs.filter { $0.state == .failed }
        }
    }

    var selectedJob: ImageJob? {
        guard let selection else { return nil }
        return jobs.first { $0.id == selection }
    }

    var pendingCount: Int { jobs.filter { !$0.state.isFinished }.count }
    var failedCount: Int { jobs.filter { $0.state == .failed }.count }
    var finishedCount: Int { jobs.count - pendingCount }

    var totalOriginalBytes: Int64 {
        jobs.filter { $0.state.isFinished }.reduce(0) { $0 + $1.originalSize }
    }

    var totalOutputBytes: Int64 {
        jobs.reduce(0) { total, job in
            guard job.state.isFinished else { return total }
            return total + (job.outputSize ?? job.originalSize)
        }
    }

    var totalSavedBytes: Int64 { max(0, totalOriginalBytes - totalOutputBytes) }

    var savedPercent: Double {
        guard totalOriginalBytes > 0 else { return 0 }
        return Double(totalSavedBytes) / Double(totalOriginalBytes) * 100
    }

    var canStart: Bool { !isRunning && !jobs.isEmpty && jobs.contains { !$0.state.isFinished } }

    // MARK: - Importing

    func addFiles(_ urls: [URL]) {
        let expanded = urls.flatMap { url -> [URL] in
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return ImageScanner.images(in: url)
            }
            return [url]
        }

        let existing = Set(jobs.map(\.sourceURL.standardizedFileURL.path))
        let incoming = expanded
            .filter { ImageScanner.isSupported($0) }
            .filter { !existing.contains($0.standardizedFileURL.path) }

        guard !incoming.isEmpty else { return }

        isScanning = true
        Task { [weak self] in
            let built = await Task.detached(priority: .userInitiated) {
                incoming.compactMap { ImageScanner.job(for: $0) }
            }.value
            guard let self else { return }
            self.jobs.append(contentsOf: built)
            if self.selection == nil { self.selection = built.first?.id }
            self.isScanning = false
        }
    }

    func remove(_ ids: Set<ImageJob.ID>) {
        guard !isRunning else { return }
        jobs.removeAll { ids.contains($0.id) }
        if let selection, !jobs.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    func clearFinished() {
        guard !isRunning else { return }
        jobs.removeAll { $0.state.isFinished }
        if let selection, !jobs.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    func clearAll() {
        guard !isRunning else { return }
        jobs.removeAll()
        selection = nil
    }

    /// Puts every finished job back in the queue, keeping the imported list.
    func resetQueue() {
        guard !isRunning else { return }
        for index in jobs.indices {
            jobs[index].state = .pending
            jobs[index].outputURL = nil
            jobs[index].outputSize = nil
            jobs[index].preview = nil
            jobs[index].originalPreview = nil
            jobs[index].message = nil
        }
    }

    // MARK: - Running

    /// True when the queue holds images that arrived as raw data rather than
    /// file URLs, so "save next to the original" has nowhere to point.
    var hasStagedDrops: Bool {
        jobs.contains { !$0.state.isFinished && DropStaging.isStaged($0.sourceURL) }
    }

    func start() {
        guard canStart else { return }

        // A staged drop is our own scratch file, so there is no folder to save
        // beside. Ask where the output should go rather than picking silently.
        if hasStagedDrops, options.writeAlongside, options.outputFolder == nil {
            guard let folder = FilePicker.chooseOutputFolder() else { return }
            options.outputFolder = folder
            options.writeAlongside = false
        }

        let queue = jobs.filter { !$0.state.isFinished }
        let snapshot = options
        isRunning = true

        runTask = Task { [weak self] in
            await self?.process(queue: queue, options: snapshot)
        }
    }

    func cancel() {
        runTask?.cancel()
    }

    private func process(queue: [ImageJob], options: CompressionOptions) async {
        let width = options.parallelismClamped
        var index = 0

        while index < queue.count, !Task.isCancelled {
            let upper = min(index + width, queue.count)
            let batch = Array(queue[index..<upper])
            index = upper

            for job in batch { setState(job.id, .processing) }

            let outcomes = await withTaskGroup(
                of: BatchRunner.Outcome.self,
                returning: [BatchRunner.Outcome].self
            ) { group in
                for job in batch {
                    group.addTask(priority: .userInitiated) {
                        await Task.detached(priority: .userInitiated) {
                            BatchRunner.run(job: job, options: options)
                        }.value
                    }
                }
                var collected: [BatchRunner.Outcome] = []
                for await outcome in group {
                    collected.append(outcome)
                }
                return collected
            }

            for outcome in outcomes {
                apply(outcome)
            }
        }

        // Anything never started goes back to pending so it can resume later.
        for index in jobs.indices where jobs[index].state == .processing {
            jobs[index].state = .pending
        }
        isRunning = false
        runTask = nil
    }

    private func apply(_ outcome: BatchRunner.Outcome) {
        guard let index = firstIndex(of: outcome.id) else { return }
        jobs[index].state = outcome.state
        jobs[index].outputURL = outcome.outputURL
        jobs[index].outputSize = outcome.outputSize
        jobs[index].outputPixelWidth = outcome.pixelWidth
        jobs[index].outputPixelHeight = outcome.pixelHeight
        jobs[index].message = outcome.message
        jobs[index].preview = outcome.preview
        jobs[index].originalPreview = outcome.originalPreview
        if outcome.state == .done, let outputURL = outcome.outputURL {
            ImageCache.shared.invalidate(url: outputURL)
        }
    }

    private func setState(_ id: ImageJob.ID, _ state: ImageJob.State) {
        guard let index = firstIndex(of: id) else { return }
        jobs[index].state = state
    }

    private func firstIndex(of id: ImageJob.ID) -> Int? {
        jobs.firstIndex { $0.id == id }
    }

    // MARK: - Actions

    func reveal(_ job: ImageJob) {
        let target = job.outputURL ?? job.sourceURL
        guard FileManager.default.fileExists(atPath: target.path) else {
            NSWorkspace.shared.activateFileViewerSelecting([job.sourceURL])
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    func revealAllOutputs() {
        let targets = jobs.compactMap(\.outputURL).filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        if targets.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(jobs.map(\.sourceURL))
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(targets)
        }
    }

    func copySummary() {
        let lines = jobs.map { job -> String in
            let result = job.outputSize.map(ByteFormat.string) ?? "—"
            return "\(job.displayName)\t\(ByteFormat.string(job.originalSize))\t\(result)"
        }.joined(separator: "\n")

        let text = """
        File\tOriginal\tCompressed
        \(lines)

        Total: \(ByteFormat.string(totalOriginalBytes)) → \(ByteFormat.string(totalOutputBytes)) \
        (\(String(format: "%.1f", savedPercent))% smaller)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Options

    func updateOptions(_ mutate: (inout CompressionOptions) -> Void) {
        var copy = options.markingCustom()
        mutate(&copy)
        options = copy
    }

    func applyPreset(_ preset: Preset) {
        if preset == .custom {
            options.preset = .custom
        } else {
            options = options.applyingPreset(preset)
        }
    }
}

enum JobFilter: String, CaseIterable, Identifiable {
    case all
    case pending
    case done
    case skipped
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .pending: "Queued"
        case .done: "Compressed"
        case .skipped: "Kept"
        case .failed: "Failed"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.stack.3d.up"
        case .pending: "clock"
        case .done: "checkmark.circle"
        case .skipped: "equal.circle"
        case .failed: "exclamationmark.triangle"
        }
    }
}
