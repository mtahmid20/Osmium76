import Foundation

public struct ImageJob: Identifiable, Sendable {
    public enum State: String, Sendable {
        case pending
        case processing
        case done
        case skipped
        case failed

        public var isFinished: Bool {
            switch self {
            case .done, .skipped, .failed: true
            case .pending, .processing: false
            }
        }
    }

    public let id: UUID
    public let sourceURL: URL
    public var originalSize: Int64
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let sourceFormat: String
    public let thumbnail: Data?
    /// Frames in the source container. > 1 does not imply animation: a
    /// multi-size .ico reports one frame per resolution.
    public let frameCount: Int
    /// True for animated GIF/WebP, APNG and multi-page TIFF, which are refused
    /// rather than flattened to a single frame.
    public let isAnimatedSource: Bool

    public var state: State = .pending
    public var outputURL: URL? = nil
    public var outputSize: Int64? = nil
    public var outputPixelWidth: Int? = nil
    public var outputPixelHeight: Int? = nil
    public var preview: Data? = nil
    /// Only captured for in-place jobs, where the source file is overwritten and
    /// the "before" pixels would otherwise be gone.
    public var originalPreview: Data? = nil
    public var message: String? = nil

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        originalSize: Int64,
        pixelWidth: Int,
        pixelHeight: Int,
        sourceFormat: String,
        thumbnail: Data? = nil,
        frameCount: Int = 1,
        isAnimatedSource: Bool = false
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.originalSize = originalSize
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.sourceFormat = sourceFormat
        self.thumbnail = thumbnail
        self.frameCount = frameCount
        self.isAnimatedSource = isAnimatedSource
    }

    public var displayName: String { sourceURL.lastPathComponent }

    public var isAnimated: Bool { isAnimatedSource }

    public var folderPath: String { sourceURL.deletingLastPathComponent().path }

    public var megapixels: Double {
        Double(pixelWidth * pixelHeight) / 1_000_000.0
    }

    /// Signed: negative when the output came out larger than the original, so
    /// the row can report that rather than clamping it away.
    public var savedFraction: Double? {
        guard let outputSize, originalSize > 0, state == .done else { return nil }
        return 1.0 - (Double(outputSize) / Double(originalSize))
    }
}

public enum ByteFormat {
    public static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }

    public static func pixels(_ width: Int, _ height: Int) -> String {
        "\(width) × \(height)"
    }
}
