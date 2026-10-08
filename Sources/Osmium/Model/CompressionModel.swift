import Foundation
import AppKit
import Observation

/// Carries cancellation from a cancellable Swift task into work that has no
/// task context of its own (`Task.detached`, a `Process` wait, libwebp).
///
/// `onCancel` runs on whichever thread called `cancel()`, so the flag is
/// lock-guarded rather than a bare `Bool`.
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }

    func cancel() {
        lock.lock()
        flag = true
        lock.unlock()
    }
}

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
    /// Paths claimed by an in-flight scan, so two drops arriving during the
    /// same decode cannot both queue the same file.
    private var claimedPaths: Set<String> = []
    /// Overlapping scans are counted, not flagged: the first to finish used to
    /// clear the "Reading files…" indicator while another was still running.
    private var scansInFlight = 0

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

    /// Jobs that produced a comparable output. A failed job is excluded from both
    /// sides: it never saved anything, and counting its original size against
    /// itself cancelled out while diluting the percentage.
    private var accountedJobs: [ImageJob] {
        jobs.filter { $0.state == .done || $0.state == .skipped }
    }

    /// Sum of the source sizes of the jobs a reduction can be measured against.
    var totalOriginalBytes: Int64 {
        accountedJobs.reduce(0) { $0 + $1.originalSize }
    }

    var totalOutputBytes: Int64 {
        accountedJobs.reduce(0) { total, job in
            // A skipped job left its original untouched, so its "output" is the
            // original by definition.
            total + (job.outputSize ?? job.originalSize)
        }
    }

    /// Signed, so a batch that grew reports negative rather than being clamped
    /// to a flattering zero.
    var totalSavedBytes: Int64 { totalOriginalBytes - totalOutputBytes }

    var savedPercent: Double {
        guard totalOriginalBytes > 0 else { return 0 }
        return Double(totalSavedBytes) / Double(totalOriginalBytes) * 100
    }

    /// True when the output came out larger than the input.
    var isRegression: Bool { totalSavedBytes < 0 }

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

        let known = claimedPaths.union(jobs.map(\.sourceURL.standardizedFileURL.path))
        var incoming: [URL] = []
        var fresh: Set<String> = []
        for url in expanded where ImageScanner.isSupported(url) {
            let key = url.standardizedFileURL.path
            // Claim synchronously. Comparing only against `jobs` left a window
            // between this check and the append below, so dropping a folder and
            // a file from inside it at once queued the same image twice.
            guard !known.contains(key), !fresh.contains(key) else { continue }
            fresh.insert(key)
            incoming.append(url)
        }

        guard !incoming.isEmpty else { return }

        claimedPaths.formUnion(fresh)
        scansInFlight += 1
        isScanning = true
        Task { [weak self] in
            let built = await Task.detached(priority: .userInitiated) {
                incoming.compactMap { ImageScanner.job(for: $0) }
            }.value
            guard let self else { return }
            // Anything that could not be read must be released, or the path
            // would stay permanently unqueueable.
            let builtPaths = Set(built.map(\.sourceURL.standardizedFileURL.path))
            self.claimedPaths.subtract(fresh.subtracting(builtPaths))
            self.jobs.append(contentsOf: built)
            if self.selection == nil { self.selection = built.first?.id }
            self.scansInFlight = max(0, self.scansInFlight - 1)
            self.isScanning = self.scansInFlight > 0
        }
    }

    func remove(_ ids: Set<ImageJob.ID>) {
        guard !isRunning else { return }
        let removed = Set(jobs.filter { ids.contains($0.id) }.map(\.sourceURL.standardizedFileURL.path))
        jobs.removeAll { ids.contains($0.id) }
        // Re-queueable, so re-adding the same file must not be blocked as a dup.
        claimedPaths.subtract(removed)
        if let selection, !jobs.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    func clearFinished() {
        guard !isRunning else { return }
        let removed = Set(jobs.filter { $0.state.isFinished }.map(\.sourceURL.standardizedFileURL.path))
        jobs.removeAll { $0.state.isFinished }
        claimedPaths.subtract(removed)
        if let selection, !jobs.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    func clearAll() {
        guard !isRunning else { return }
        jobs.removeAll()
        claimedPaths.removeAll()
        selection = nil
    }

    /// Puts every finished job back in the queue, keeping the imported list.
    ///
    /// The original size is re-measured because a previous run may have
    /// rewritten the file in place: reporting the size from before that run
    /// would claim savings against a file that no longer exists.
    func resetQueue() {
        guard !isRunning else { return }
        for index in jobs.indices {
            guard jobs[index].state.isFinished else { continue }
            jobs[index].state = .pending
            jobs[index].outputURL = nil
            jobs[index].outputSize = nil
            jobs[index].preview = nil
            jobs[index].originalPreview = nil
            jobs[index].message = nil

            let path = jobs[index].sourceURL.path
            guard FileManager.default.fileExists(atPath: path) else {
                // The original was deleted by an earlier run, so there is
                // nothing left to compress and no size to compare against.
                jobs[index].state = .failed
                jobs[index].message = "The original file no longer exists"
                continue
            }
            jobs[index].originalSize = ImageCompressor.fileSize(of: jobs[index].sourceURL)
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

        // Two cases leave "save next to the original" with nowhere to point: a staged
        // drop, which is our own scratch file, and any run with the toggle off
        // but no folder chosen. Both ask rather than quietly writing to a
        // fallback the user never picked.
        //
        // Note that `writeAlongside` is deliberately left alone. Setting only
        // `outputFolder` is enough: `destinationURL` sends staged drops to that
        // folder while real files stay where they are. Flipping the toggle here
        // used to relocate the *whole* batch, so one image dragged out of
        // Photos moved every photo the user dropped from Finder.
        let needsDestination = options.outputFolder == nil
            && (!options.writeAlongside || hasStagedDrops)
        if needsDestination {
            guard let folder = FilePicker.chooseOutputFolder() else { return }
            options.outputFolder = folder
        }

        let queue = jobs.filter { !$0.state.isFinished }
        let snapshot = options
        // Claim every destination up front, on the main actor. `avoidOverwrite`
        // otherwise resolves each job's name independently at encode time, so
        // two same-stem files landing in one folder both see the name as free,
        // both write it, and one output is lost.
        let destinations = ImageCompressor.reserveDestinations(for: queue, options: snapshot)
        isRunning = true

        runTask = Task { [weak self] in
            await self?.process(queue: queue, options: snapshot, destinations: destinations)
        }
    }

    func cancel() {
        runTask?.cancel()
    }

    private func process(
        queue: [ImageJob],
        options: CompressionOptions,
        destinations: [ImageJob.ID: URL]
    ) async {
        // A cancel that lands before the body is scheduled must not leave the
        // UI stuck in a running state with every control disabled.
        defer { isRunning = false; runTask = nil }

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
                    let destination = destinations[job.id]
                    let cancellation = CancellationFlag()
                    group.addTask(priority: .userInitiated) {
                        // Group children ARE cancelled when the run task is,
                        // but a Task.detached inside one inherits nothing — its
                        // own flag is never set, so reading Task.isCancelled
                        // there always returns false. The cancellation handler
                        // is what bridges the two: onCancel fires on the
                        // cancelled group child and flips the flag that
                        // BatchRunner and WebPEncoder actually poll.
                        await withTaskCancellationHandler {
                            await Task.detached(priority: .userInitiated) {
                                BatchRunner.run(
                                    job: job,
                                    options: options,
                                    destination: destination,
                                    isCancelled: { cancellation.isCancelled }
                                )
                            }.value
                        } onCancel: {
                            cancellation.cancel()
                        }
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

        // Anything never started, or interrupted by Stop, goes back to pending so it
        // can resume. Cancelled jobs already report `.pending`.
        for index in jobs.indices where jobs[index].state == .processing {
            jobs[index].state = .pending
        }
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

        // The pane caches decoded previews under "<job id>-before"/"-after",
        // which survive a Reset, so a second run would be shown the first run's
        // image. Drop them before storing the new payloads.
        ImageCache.shared.invalidateData(key: "\(outcome.id.uuidString)-before")
        ImageCache.shared.invalidateData(key: "\(outcome.id.uuidString)-after")

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
        (\(String(format: "%.1f", abs(savedPercent)))% \(savedPercent < 0 ? "larger" : "smaller"), originals kept)
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
