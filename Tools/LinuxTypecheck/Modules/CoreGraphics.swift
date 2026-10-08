// Linux stand-in for Apple's CoreGraphics.
//
// Only the surface Caesium actually touches is declared, and CF* opaque types
// are aliased to plain Swift types. That keeps the app source unmodified while
// still letting the compiler check our own code (optionality, arithmetic,
// generics, Sendable, closure captures). It does NOT validate Apple's exact
// signatures — this is a self-consistency check, not an SDK conformance test.
//
@_exported import Foundation

public typealias CFString = String
public typealias CFData = Data
public typealias CFURL = URL
public typealias CFDictionary = [String: Any]
/// Opaque CFArray on Apple; bridged conditionally to [String] in the app.
public typealias CFArray = [Any]
public typealias CFMutableData = NSMutableData

// MARK: - Color

public class CGColor {
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {}
}

public struct CGColorSpaceModel: Equatable, RawRepresentable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }
    public static let unknown = CGColorSpaceModel(rawValue: -1)
    public static let monochrome = CGColorSpaceModel(rawValue: 0)
    public static let rgb = CGColorSpaceModel(rawValue: 1)
    public static let cmyk = CGColorSpaceModel(rawValue: 2)
    public static let lab = CGColorSpaceModel(rawValue: 3)
}

public struct CGColorSpaceName: RawRepresentable, Equatable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let sRGB = CGColorSpaceName(rawValue: "kCGColorSpaceSRGB")
    public static let deviceRGB = CGColorSpaceName(rawValue: "kCGColorSpaceDeviceRGB")
    public static let displayP3 = CGColorSpaceName(rawValue: "kCGColorSpaceDisplayP3")
}

public class CGColorSpace {
    public var model: CGColorSpaceModel = .rgb
    public init?(name: CGColorSpaceName) { self.model = .rgb }
    public init() { self.model = .rgb }

    // On Apple these come from the CoreGraphics C API.
    public static let sRGB = CGColorSpaceName(rawValue: "kCGColorSpaceSRGB")
}

public func CGColorSpaceCreateDeviceRGB() -> CGColorSpace { CGColorSpace() }

// MARK: - Images

public struct CGBitmapInfo: OptionSet, Equatable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let alphaInfoMask = CGBitmapInfo(rawValue: 0x1F)
    public static let byteOrderMask = CGBitmapInfo(rawValue: 0x7000)
    public static let byteOrder32Big = CGBitmapInfo(rawValue: (2 << 12))
    public static let byteOrder32Little = CGBitmapInfo(rawValue: (3 << 12))
}

public struct CGImageAlphaInfo: Equatable, RawRepresentable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let none = CGImageAlphaInfo(rawValue: 0)
    public static let premultipliedLast = CGImageAlphaInfo(rawValue: 1)
    public static let premultipliedFirst = CGImageAlphaInfo(rawValue: 2)
    public static let last = CGImageAlphaInfo(rawValue: 3)
    public static let first = CGImageAlphaInfo(rawValue: 4)
    public static let noneSkipLast = CGImageAlphaInfo(rawValue: 5)
    public static let noneSkipFirst = CGImageAlphaInfo(rawValue: 6)
}

public class CGImage {
    public init() {}
    public var width: Int = 0
    public var height: Int = 0
    public var alphaInfo: CGImageAlphaInfo = .none
    public var colorSpace: CGColorSpace? = nil
}

public enum CGInterpolationQuality: Int32 {
    case `default` = 0
    case low = 1
    case high = 2
    case none = 3
}

public class CGContext {
    public init?(
        data: UnsafeMutableRawPointer?,
        width: Int,
        height: Int,
        bitsPerComponent: Int,
        bytesPerRow: Int,
        space: CGColorSpace,
        bitmapInfo: UInt32
    ) {}

    public func setFillColor(_ color: CGColor) {}
    public func fill(_ rect: CGRect) {}
    public var interpolationQuality: CGInterpolationQuality = .default
    public func draw(_ image: CGImage, in rect: CGRect) {}
    public func makeImage() -> CGImage? { CGImage() }
}

public struct CGImagePropertyOrientation: Equatable, RawRepresentable {
    public let rawValue: UInt32
    // Failable on Apple platforms — the compiler enforces an unwrap there.
    public init?(rawValue: UInt32) { self.rawValue = rawValue }
    public static let up: CGImagePropertyOrientation = CGImagePropertyOrientation(rawValue: 1)!
    public static let upMirrored: CGImagePropertyOrientation = CGImagePropertyOrientation(rawValue: 2)!
    public static let down: CGImagePropertyOrientation = CGImagePropertyOrientation(rawValue: 3)!
    public static let downMirrored: CGImagePropertyOrientation = CGImagePropertyOrientation(rawValue: 4)!
    public static let leftMirrored: CGImagePropertyOrientation = CGImagePropertyOrientation(rawValue: 5)!
    public static let right: CGImagePropertyOrientation = CGImagePropertyOrientation(rawValue: 6)!
    public static let rightMirrored: CGImagePropertyOrientation = CGImagePropertyOrientation(rawValue: 7)!
    public static let left: CGImagePropertyOrientation = CGImagePropertyOrientation(rawValue: 8)!
}
