// Linux stand-in for the AppKit symbols the engine/model touch.
// NSCache / NSString come from Foundation on Linux, so they are not redeclared here.
@_exported import Foundation
@_exported import CoreGraphics

public struct NSSize {
    public var width: CGFloat
    public var height: CGFloat
    public init(width: CGFloat, height: CGFloat) { self.width = width; self.height = height }
}

open class NSImage {
    public var size: NSSize
    public init(cgImage: CGImage, size: NSSize) { self.size = size }
    public convenience init?(data: Data) { self.init(cgImage: CGImage(), size: NSSize(width: 0, height: 0)) }
}

public class NSWorkspace {
    public static let shared = NSWorkspace()
    public func activateFileViewerSelecting(_ urls: [URL]) {}
    public func selectFile(_ filename: String?, inFileViewerRootedAtPath path: String) {}
}

public class NSPasteboard {
    public static let general = NSPasteboard()
    public func clearContents() {}
    public func setString(_ string: String, forType type: NSPasteboard.PasteboardType) {}
    public struct PasteboardType: RawRepresentable, Equatable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let string = PasteboardType(rawValue: "public.utf8-plain-text")
    }
}
