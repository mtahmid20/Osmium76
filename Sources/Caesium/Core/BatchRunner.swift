import Foundation

/// Executes one image job off the main thread.
public enum BatchRunner {

    public struct Outcome: Sendable {
        public let id: UUID
        public let state: ImageJob.State
        public let outputURL: URL?
        public let outputSize: Int64?
        public let pixelWidth: Int
        public let pixelHeight: Int
        public let preview: Data?
        public let originalPreview: Data?
        public let message: String?
    }

    /// - Parameter destination: pre-resolved output path. Passing one in is what
    ///   keeps parallel jobs from racing on `avoidOverwrite`; without it each
    ///   job resolves its own name and two files with the same stem can collide.
    /// - Parameter isCancelled: polled before the encode, before the write, and
    ///   again before the delete. Cancellation after a write must leave the
    ///   original in place, so a file is never left with neither version.
    public static func run(
        job: ImageJob,
        options: CompressionOptions,
        destination: URL? = nil,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> Outcome {
        let destination = destination ?? ImageCompressor.destinationURL(for: job, options: options)

        do {
            let input: Data
            do {
                input = try Data(contentsOf: job.sourceURL, options: .mappedIfSafe)
            } catch {
                return failure(job, "Cannot read file: \(error.localizedDescription)")
            }

            if isCancelled() { return cancelled(job) }

            let inPlace = destination == job.sourceURL
            let output = try ImageCompressor.compress(
                source: input,
                options: options,
                isCancelled: isCancelled
            )

            if options.skipWhenNotSmaller, output.data.count >= input.count {
                return Outcome(
                    id: job.id,
                    state: .skipped,
                    outputURL: nil,
                    outputSize: Int64(input.count),
                    pixelWidth: output.pixelWidth,
                    pixelHeight: output.pixelHeight,
                    preview: nil,
                    originalPreview: nil,
                    message: "Already optimised — kept the original"
                )
            }

            // Cancelling before the write leaves both files untouched, which is the only
            // point at which it is safe to abandon the job.
            if isCancelled() { return cancelled(job) }

            do {
                try write(output.data, to: destination, preserving: inPlace ? job.sourceURL : nil)
            } catch {
                return failure(job, CompressionError.writeFailed(error.localizedDescription).localizedDescription)
            }

            // Past this point the output exists. If the original were deleted and
            // then the job were cancelled as "failed", the user would be left
            // with nothing, so the delete either runs or is deliberately skipped.
            let staged = DropStaging.isStaged(job.sourceURL)
            if (options.deleteOriginal || staged), destination != job.sourceURL {
                do {
                    try FileManager.default.removeItem(at: job.sourceURL)
                } catch {
                    return failure(job, "Saved, but the original could not be removed: \(error.localizedDescription)")
                }
            }

            let preview = ImageCompressor.decodeThumbnail(from: output.data, maxPixel: 1800, quality: 0.92)
            // An in-place rewrite destroys the source, so snapshot "before" now.
            var before: Data? = nil
            if inPlace {
                before = ImageCompressor.decodeThumbnail(from: input, maxPixel: 1800, quality: 0.85)
            }
            return Outcome(
                id: job.id,
                state: .done,
                outputURL: destination,
                outputSize: Int64(output.data.count),
                pixelWidth: output.pixelWidth,
                pixelHeight: output.pixelHeight,
                preview: preview,
                originalPreview: before,
                message: nil
            )
        } catch CompressionError.cancelled {
            return cancelled(job)
        } catch {
            return failure(job, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// An interrupted job leaves the file untouched and returns to the queue,
    /// so pressing Stop mid-batch is resumable rather than destructive.
    private static func cancelled(_ job: ImageJob) -> Outcome {
        Outcome(
            id: job.id,
            state: .pending,
            outputURL: nil,
            outputSize: nil,
            pixelWidth: job.pixelWidth,
            pixelHeight: job.pixelHeight,
            preview: nil,
            originalPreview: nil,
            message: "Stopped"
        )
    }

    /// Writes the output. When replacing a file in place, the bytes go to a
    /// sibling temp file and `replaceItemAt` swaps it in, which preserves the
    /// original's permissions, ACLs and resource fork. A plain atomic write
    /// renames a fresh file over the top and silently drops all of that —
    /// including `com.apple.quarantine`, which erases the file's
    /// "downloaded from the internet" provenance.
    private static func write(_ data: Data, to destination: URL, preserving original: URL?) throws {
        guard let original, original == destination else {
            try data.write(to: destination, options: .atomic)
            return
        }

        let temporary = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).caesium-tmp")
        // Capture the source's attributes first: once it is replaced they are
        // gone, and `replaceItemAt` alone does not carry extended attributes
        // across — notably `com.apple.quarantine`, which records that a file
        // came from the internet.
        let attributes = extendedAttributes(of: original)

        try data.write(to: temporary, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let result = try? FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        if result == nil {
            // Volumes without replace support (some network shares): fall back,
            // which is still atomic with respect to file contents.
            try data.write(to: destination, options: .atomic)
        }

        for (name, value) in attributes {
            value.withUnsafeBytes { raw in
                _ = setxattr(destination.path, name, raw.baseAddress, raw.count, 0, 0)
            }
        }
    }

    /// Every extended attribute on `url`, as name → value. `com.apple.quarantine`
    /// is included: dropping it would silently erase the file's downloaded-from-
    /// the-internet provenance, which Gatekeeper and the user both rely on.
    private static func extendedAttributes(of url: URL) -> [(String, Data)] {
        let length = listxattr(url.path, nil, 0, 0)
        guard length > 0 else { return [] }

        var names = [CChar](repeating: 0, count: length)
        guard listxattr(url.path, &names, length, 0) == length else { return [] }

        // `listxattr` returns NUL-separated names in one buffer, so decoding it
        // with String(cString:) would stop at the first NUL and silently drop
        // every attribute after the first.
        let listing = String(decoding: names.map { UInt8(bitPattern: $0) }, as: UTF8.self)

        var result: [(String, Data)] = []
        for name in listing.split(separator: "\0") where !name.isEmpty {
            let key = String(name)
            let size = getxattr(url.path, key, nil, 0, 0, 0)
            guard size > 0 else { continue }
            var value = [UInt8](repeating: 0, count: size)
            let read = value.withUnsafeMutableBytes { raw in
                getxattr(url.path, key, raw.baseAddress?.assumingMemoryBound(to: CChar.self), size, 0, 0)
            }
            if read > 0 { result.append((key, Data(value.prefix(read)))) }
        }
        return result
    }

    private static func failure(_ job: ImageJob, _ message: String) -> Outcome {
        Outcome(
            id: job.id,
            state: .failed,
            outputURL: nil,
            outputSize: nil,
            pixelWidth: job.pixelWidth,
            pixelHeight: job.pixelHeight,
            preview: nil,
            originalPreview: nil,
            message: message
        )
    }
}
