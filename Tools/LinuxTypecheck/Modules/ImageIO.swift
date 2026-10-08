// Linux stand-in for ImageIO: source/destination C functions and the metadata
// key constants used by the engine.
@_exported import Foundation
@_exported import CoreGraphics

public typealias CGImageSource = AnyObject
public typealias CGImageDestination = AnyObject

// MARK: - Sources

public func CGImageSourceCreateWithURL(_ url: CFURL, _ options: CFDictionary?) -> CGImageSource? { nil }
public func CGImageSourceCreateWithData(_ data: CFData, _ options: CFDictionary?) -> CGImageSource? { nil }
public func CGImageSourceGetCount(_ source: CGImageSource) -> Int { 0 }
public func CGImageSourceGetType(_ source: CGImageSource) -> CFString? { nil }
// Real macOS returns a CF opaque type; Any? models the bridged cast honestly.
public func CGImageSourceCopyPropertiesAtIndex(_ source: CGImageSource, _ index: Int, _ options: CFDictionary?) -> Any? { nil }
public func CGImageSourceCreateImageAtIndex(_ source: CGImageSource, _ index: Int, _ options: CFDictionary?) -> CGImage? { nil }
public func CGImageSourceCreateThumbnailAtIndex(_ source: CGImageSource, _ index: Int, _ options: CFDictionary?) -> CGImage? { nil }

// MARK: - Destinations

public func CGImageDestinationCreateWithData(_ data: CFMutableData, _ type: CFString, _ count: Int, _ options: CFDictionary?) -> CGImageDestination? { nil }
public func CGImageDestinationAddImage(_ destination: CGImageDestination, _ image: CGImage, _ properties: CFDictionary?) {}
public func CGImageDestinationFinalize(_ destination: CGImageDestination) -> Bool { true }
public func CGImageDestinationCopyTypeIdentifiers() -> CFArray { [] }

// MARK: - Source / destination option keys

public nonisolated(unsafe) let kCGImageSourceShouldCache: CFString = "kCGImageSourceShouldCache"
public nonisolated(unsafe) let kCGImageSourceShouldCacheImmediately: CFString = "kCGImageSourceShouldCacheImmediately"
public nonisolated(unsafe) let kCGImageSourceCreateThumbnailFromImageAlways: CFString = "kCGImageSourceCreateThumbnailFromImageAlways"
public nonisolated(unsafe) let kCGImageSourceCreateThumbnailWithTransform: CFString = "kCGImageSourceCreateThumbnailWithTransform"
public nonisolated(unsafe) let kCGImageSourceThumbnailMaxPixelSize: CFString = "kCGImageSourceThumbnailMaxPixelSize"
public nonisolated(unsafe) let kCGImageDestinationLossyCompressionQuality: CFString = "kCGImageDestinationLossyCompressionQuality"

// MARK: - Top-level properties

public nonisolated(unsafe) let kCGImagePropertyPixelWidth: CFString = "kCGImagePropertyPixelWidth"
public nonisolated(unsafe) let kCGImagePropertyPixelHeight: CFString = "kCGImagePropertyPixelHeight"
public nonisolated(unsafe) let kCGImagePropertyOrientation: CFString = "kCGImagePropertyOrientation"
public nonisolated(unsafe) let kCGImagePropertyHasAlpha: CFString = "kCGImagePropertyHasAlpha"
public nonisolated(unsafe) let kCGImagePropertyExifDictionary: CFString = "kCGImagePropertyExifDictionary"
public nonisolated(unsafe) let kCGImagePropertyTIFFDictionary: CFString = "kCGImagePropertyTIFFDictionary"
public nonisolated(unsafe) let kCGImagePropertyGPSDictionary: CFString = "kCGImagePropertyGPSDictionary"
public nonisolated(unsafe) let kCGImagePropertyIPTCDictionary: CFString = "kCGImagePropertyIPTCDictionary"
public nonisolated(unsafe) let kCGImageProperty8BIMDictionary: CFString = "kCGImageProperty8BIMDictionary"
public nonisolated(unsafe) let kCGImagePropertyJFIFDictionary: CFString = "kCGImagePropertyJFIFDictionary"
public nonisolated(unsafe) let kCGImagePropertyJFIFIsProgressive: CFString = "kCGImagePropertyJFIFIsProgressive"
public nonisolated(unsafe) let kCGImagePropertyHEICDictionaries: CFString = "kCGImagePropertyHEICDictionaries"
public nonisolated(unsafe) let kCGImagePropertyHEICHasAlpha: CFString = "kCGImagePropertyHEICHasAlpha"

// NOTE: the individual kCGImagePropertyExif…/…TIFF… tags are deliberately absent —
// the macOS SDK does not expose them to Swift, so the app must not use them.


