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

    public static func run(job: ImageJob, options: CompressionOptions) -> Outcome {
        let destination = ImageCompressor.destinationURL(for: job, options: options)

        do {
            let input: Data
            do {
                input = try Data(contentsOf: job.sourceURL, options: .mappedIfSafe)
            } catch {
                return failure(job, "Cannot read file: \(error.localizedDescription)")
            }

            let inPlace = destination == job.sourceURL
            let output = try ImageCompressor.compress(source: input, options: options)

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

            do {
                try output.data.write(to: destination, options: .atomic)
            } catch {
                return failure(job, CompressionError.writeFailed(error.localizedDescription).localizedDescription)
            }

            // A staged drop is our own scratch copy, so it always goes away once
            // the real output exists. For a real file this only happens when the
            // user asked for it and the output is a separate file.
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
        } catch {
            return failure(job, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
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
