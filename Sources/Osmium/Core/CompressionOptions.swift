import Foundation

public enum Preset: String, CaseIterable, Identifiable, Sendable, Codable {
    case webReady
    case balanced
    case highQuality
    case halfSize
    case thumbnail
    case webp
    case webpLossless
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .webReady: "Web Ready"
        case .balanced: "Balanced"
        case .highQuality: "High Quality"
        case .halfSize: "Half Size"
        case .thumbnail: "Thumbnail"
        case .webp: "WebP"
        case .webpLossless: "WebP Lossless"
        case .custom: "Custom"
        }
    }

    public var summary: String {
        switch self {
        case .webReady: "JPEG · 65% · max 1920px"
        case .balanced: "JPEG · 80% · max 2560px"
        case .highQuality: "JPEG · 92% · full size"
        case .halfSize: "JPEG · 80% · 50% of original"
        case .thumbnail: "JPEG · 55% · max 800px"
        case .webp: "WebP · 80% · max 2560px"
        case .webpLossless: "WebP · lossless · full size"
        case .custom: "Your own settings"
        }
    }
}

public struct DimensionChoice: Identifiable, Sendable, Hashable {
    public let title: String
    public let value: Int
    public var id: Int { value }

    public init(title: String, value: Int) {
        self.title = title
        self.value = value
    }
}

/// How the output size is decided: not at all, by a pixel cap, or as a
/// percentage of each source image's longest edge.
public enum ResizeMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case full
    case pixels
    case percent

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .full: "Full size"
        case .pixels: "Max pixels"
        case .percent: "Percent"
        }
    }

    public var symbol: String {
        switch self {
        case .full: "1.square"
        case .pixels: "max"
        case .percent: "percent"
        }
    }

    public var summary: String {
        switch self {
        case .full: "no resizing"
        case .percent: "scaled to % of the original"
        case .pixels: "longest edge capped"
        }
    }
}

public struct CompressionOptions: Sendable, Codable, Equatable {
    public var preset: Preset = .balanced
    public var format: OutputFormat = .jpeg
    /// 0…1, only meaningful when `format.usesLossyQuality`.
    public var quality: Double = 0.8
    /// WebP only: encode without loss. Ignored by the other formats.
    public var lossless: Bool = false
    /// Whether `maxDimension` / `scalePercent` / neither sets the output size.
    public var resizeMode: ResizeMode = .pixels
    /// Longest edge cap in pixels; only used when `resizeMode == .pixels`.
    public var maxDimension: Int = 2560
    /// Longest edge as a share of the source; only used when `resizeMode == .percent`.
    public var scalePercent: Double = 0.5
    /// Drop EXIF / TIFF / GPS / IPTC / 8BIM payloads.
    public var stripMetadata: Bool = true
    /// Drop GPS specifically while keeping camera info.
    public var stripLocation: Bool = false
    /// Delete the original after a successful conversion.
    public var deleteOriginal: Bool = false
    /// Write next to the source file instead of into `outputFolder`.
    public var writeAlongside: Bool = true
    public var outputFolder: URL? = nil
    /// Appended to the filename stem when not overwriting in place.
    public var nameSuffix: String = " compressed"
    /// Leave the file alone when re-encoding would not shrink it.
    public var skipWhenNotSmaller: Bool = true
    /// Never clobber an existing file; add " (2)", " (3)"… instead.
    public var avoidOverwrite: Bool = true
    /// Number of images compressed simultaneously.
    public var parallelism: Int = 4

    public init() {}

    /// Presets set a concrete resize mode; leaving one on `.full` when the user
    /// asked for pixels or percent would silently ignore their choice.
    public mutating func selectResizeMode(_ mode: ResizeMode) {
        resizeMode = mode
        preset = .custom
    }

    public static let dimensionChoices: [DimensionChoice] = [
        DimensionChoice(title: "Full size", value: 0),
        DimensionChoice(title: "5120 px", value: 5120),
        DimensionChoice(title: "4096 px", value: 4096),
        DimensionChoice(title: "2560 px", value: 2560),
        DimensionChoice(title: "1920 px", value: 1920),
        DimensionChoice(title: "1280 px", value: 1280),
        DimensionChoice(title: "800 px", value: 800),
        DimensionChoice(title: "512 px", value: 512)
    ]

    /// Re-applies a preset to the concrete settings, leaving `preset` untouched.
    public func applyingPreset(_ preset: Preset) -> CompressionOptions {
        var copy = self
        copy.preset = preset
        // Only the WebP lossless preset wants this. Left set from an earlier one,
        // it would hide the quality slider for JPEG — a format that ignores the
        // flag entirely, so the control would vanish with no cause shown.
        copy.lossless = preset == .webpLossless
        switch preset {
        case .webReady:
            copy.format = .jpeg
            copy.quality = 0.65
            copy.resizeMode = .pixels
            copy.maxDimension = 1920
        case .balanced:
            copy.format = .jpeg
            copy.quality = 0.80
            copy.resizeMode = .pixels
            copy.maxDimension = 2560
        case .highQuality:
            copy.format = .jpeg
            copy.quality = 0.92
            copy.resizeMode = .full
        case .halfSize:
            copy.format = .jpeg
            copy.quality = 0.80
            copy.resizeMode = .percent
            copy.scalePercent = 0.50
        case .thumbnail:
            copy.format = .jpeg
            copy.quality = 0.55
            copy.resizeMode = .pixels
            copy.maxDimension = 800
        case .webp:
            copy.format = .webp
            copy.quality = 0.80
            copy.resizeMode = .pixels
            copy.maxDimension = 2560
            copy.lossless = false
        case .webpLossless:
            copy.format = .webp
            copy.quality = 1.0
            copy.resizeMode = .full
            copy.lossless = true
        case .custom:
            break
        }
        return copy
    }

    /// The longest edge an output may have for a source of `longest` pixels,
    /// or 0 to keep the source resolution.
    public func dimensionCap(forSourceLongestEdge longest: Int) -> Int {
        switch resizeMode {
        case .full:
            return 0
        case .percent:
            let ratio = min(max(scalePercent, 0.01), 1.0)
            return max(1, Int((Double(longest) * ratio).rounded()))
        case .pixels:
            return max(0, maxDimension)
        }
    }

    /// One-line description of the resize setting, shown under the picker.
    public var resizeSummary: String {
        switch resizeMode {
        case .full:
            return "No resizing — every image keeps its own resolution."
        case .pixels:
            return maxDimension == 0
                ? "No resizing — every image keeps its own resolution."
                : "Longest edge capped at \(maxDimension) px."
        case .percent:
            let percent = Int((scalePercent * 100).rounded())
            return percent >= 100
                ? "No resizing — every image keeps its own resolution."
                : "Longest edge scaled to \(percent)% of the original."
        }
    }

    /// Called by the UI whenever a field other than `preset` changes.
    public func markingCustom() -> CompressionOptions {
        var copy = self
        copy.preset = .custom
        return copy
    }

    public var parallelismClamped: Int {
        min(max(parallelism, 1), 12)
    }
}
