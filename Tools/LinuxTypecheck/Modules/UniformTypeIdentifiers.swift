// Linux stand-in for UniformTypeIdentifiers.
import Foundation

public struct UTType: Hashable {
    public let identifier: String
    public init(_ identifier: String) { self.identifier = identifier }
    public init?(filenameExtension: String) { self.identifier = filenameExtension }
    public static func filenameExtension(_ ext: String) -> UTType? { UTType(ext) }
    public var preferredFilenameExtension: String? { identifier }

    public static let jpeg = UTType("public.jpeg")
    public static let heic = UTType("public.heic")
    public static let png = UTType("public.png")
    public static let webp = UTType("org.webmproject.webp")
    public static let image = UTType("public.image")
    public static let fileURL = UTType("public.file-url")

    public func conforms(to other: UTType) -> Bool { identifier == other.identifier }
}
