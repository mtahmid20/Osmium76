import Foundation
import ImageIO

public enum OutputFormat: String, CaseIterable, Identifiable, Sendable, Codable {
    case jpeg
    case heic
    case png
    case webp

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .png: "PNG"
        case .webp: "WebP"
        }
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .heic: "heic"
        case .png: "png"
        case .webp: "webp"
        }
    }

    /// Raw UTI strings rather than `UTType` members: `UTType.webp` does not
    /// exist on every SDK, but the identifier itself is stable.
    public var utTypeIdentifier: String {
        switch self {
        case .jpeg: "public.jpeg"
        case .heic: "public.heic"
        case .png: "public.png"
        case .webp: "org.webmproject.webp"
        }
    }

    public var systemImage: String {
        switch self {
        case .jpeg: "photo"
        case .heic: "apple.logo"
        case .png: "seal"
        case .webp: "globe"
        }
    }

    /// Formats whose encoder honours a lossy quality value.
    public var usesLossyQuality: Bool { self != .png }

    /// True when the container can carry an alpha channel without flattening.
    public var supportsAlpha: Bool {
        switch self {
        case .jpeg: false
        case .heic, .png, .webp: true
        }
    }

    public var qualityRange: ClosedRange<Double> {
        switch self {
        case .jpeg: 0.05...1.0
        case .heic: 0.05...1.0
        case .webp: 0.05...1.0
        case .png: 0...1
        }
    }

    /// Formats this OS build can actually write. ImageIO covers everything
    /// except WebP, which is handed to libwebp's cwebp.
    public static let encodableFormats: [OutputFormat] = {
        let available = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        return allCases.filter { format in
            available.contains(format.utTypeIdentifier) || (format == .webp && WebPEncoder.isAvailable)
        }
    }()

    public static func isEncodable(_ format: OutputFormat) -> Bool {
        switch format {
        case .webp: return WebPEncoder.isAvailable
        default: return encodableFormats.contains(format)
        }
    }
}
