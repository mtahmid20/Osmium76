import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

public enum CompressionError: LocalizedError {
    case unreadableSource
    case noFrames
    case decodeFailed
    case unsupportedFormat(OutputFormat)
    case encodeFailed
    case destinationUnavailable
    case writeFailed(String)
    case webPEncoderMissing

    public var errorDescription: String? {
        switch self {
        case .unreadableSource: "The file could not be opened."
        case .noFrames: "The file contains no image frames."
        case .decodeFailed: "The image data could not be decoded."
        case .unsupportedFormat(let format):
            "This Mac cannot encode \(format.displayName). Pick another format."
        case .encodeFailed: "The image encoder failed."
        case .destinationUnavailable: "The output file could not be created."
        case .writeFailed(let reason): "Could not save the file: \(reason)"
        case .webPEncoderMissing: WebPEncoder.unavailableReason
        }
    }
}

public enum ImageCompressor {

    /// One shared renderer: CIContext is expensive to create, and it is Sendable.
    private static let sharedCIContext = CIContext(options: nil)

    // MARK: - Source inspection

    public struct SourceInfo {
        public let pixelWidth: Int
        public let pixelHeight: Int
        public let fileSize: Int64
        public let formatName: String
        public let orientation: CGImagePropertyOrientation
        public let hasAlpha: Bool
    }

    /// Reads dimensions and metadata without fully decoding pixel data.
    public static func inspect(url: URL) -> SourceInfo? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard CGImageSourceGetCount(source) > 0 else { return nil }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }

        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let orientationValue = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up
        let hasAlpha = (properties[kCGImagePropertyHasAlpha] as? NSNumber)?.boolValue ?? false

        return SourceInfo(
            pixelWidth: width,
            pixelHeight: height,
            fileSize: fileSize(of: url),
            formatName: formatName(of: url),
            orientation: orientation,
            hasAlpha: hasAlpha
        )
    }

    // MARK: - Thumbnails & previews

    /// Small JPEG data used for table rows.
    public static func thumbnailData(for url: URL, maxPixel: Int = 240) -> Data? {
        decodeThumbnail(url: url, maxPixel: maxPixel, quality: 0.7)
    }

    /// Larger JPEG data used by the preview pane.
    public static func previewData(for url: URL, maxPixel: Int = 2000) -> Data? {
        decodeThumbnail(url: url, maxPixel: maxPixel, quality: 0.92)
    }

    public static func decodeThumbnail(from data: Data, maxPixel: Int = 2000, quality: Double = 0.9) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return encodeThumbnail(source: source, maxPixel: maxPixel, quality: quality)
    }

    private static func decodeThumbnail(url: URL, maxPixel: Int, quality: Double) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return encodeThumbnail(source: source, maxPixel: maxPixel, quality: quality)
    }

    private static func encodeThumbnail(source: CGImageSource, maxPixel: Int, quality: Double) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return try? encode(image: image, format: .jpeg, quality: quality, metadata: nil, alphaHandling: .flattenOnWhite)
    }

    // MARK: - Main pipeline

    public struct Output: Sendable {
        public let data: Data
        public let pixelWidth: Int
        public let pixelHeight: Int
    }

    /// Decodes, re-orients, resizes, strips metadata and re-encodes a single image.
    public static func compress(source data: Data, options: CompressionOptions) throws -> Output {
        guard OutputFormat.isEncodable(options.format) else {
            throw CompressionError.unsupportedFormat(options.format)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw CompressionError.unreadableSource
        }
        guard CGImageSourceGetCount(source) > 0 else { throw CompressionError.noFrames }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientationValue = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up

        let decodeOptions: [CFString: Any] = [kCGImageSourceShouldCache: true]
        guard let raw = CGImageSourceCreateImageAtIndex(source, 0, decodeOptions as CFDictionary) else {
            throw CompressionError.decodeFailed
        }

        let prepared = try prepare(raw, orientation: orientation, options: options)
        let metadata = MetadataPolicy.payload(
            from: properties,
            keepMetadata: !options.stripMetadata,
            stripLocation: options.stripLocation
        )
        let alpha: AlphaHandling = options.format == .jpeg ? .flattenOnWhite : .preserve

        let encoded = try encode(
            image: prepared,
            format: options.format,
            quality: options.quality,
            lossless: options.lossless,
            metadata: metadata,
            alphaHandling: alpha
        )
        return Output(data: encoded, pixelWidth: prepared.width, pixelHeight: prepared.height)
    }

    /// Bakes EXIF orientation into pixels and applies the resolution cap.
    private static func prepare(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation,
        options: CompressionOptions
    ) throws -> CGImage {
        let oriented: CGImage
        if orientation == .up {
            oriented = image
        } else {
            let ciImage = CIImage(cgImage: image).oriented(orientation)
            guard let baked = sharedCIContext.createCGImage(ciImage, from: ciImage.extent) else {
                throw CompressionError.decodeFailed
            }
            oriented = baked
        }

        let longest = max(oriented.width, oriented.height)
        let cap = options.dimensionCap(forSourceLongestEdge: longest)
        guard cap > 0, longest > cap else { return oriented }

        let scale = Double(cap) / Double(longest)
        let width = max(1, Int((Double(oriented.width) * scale).rounded()))
        let height = max(1, Int((Double(oriented.height) * scale).rounded()))
        guard let scaled = resize(oriented, width: width, height: height) else { return oriented }
        return scaled
    }

    private static func resize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let hasAlpha = image.alphaInfo != .none && image.alphaInfo != .noneSkipFirst && image.alphaInfo != .noneSkipLast
        let alphaInfo: CGImageAlphaInfo = hasAlpha ? .premultipliedLast : .noneSkipLast
        let bitmapInfo = alphaInfo.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: encodingColorSpace(for: image),
            bitmapInfo: bitmapInfo
        ) else { return nil }

        if !hasAlpha {
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    // MARK: - Encoding

    enum AlphaHandling {
        case preserve
        case flattenOnWhite
    }

    static func encode(
        image: CGImage,
        format: OutputFormat,
        quality: Double,
        lossless: Bool = false,
        metadata: MetadataPolicy.Payload?,
        alphaHandling: AlphaHandling
    ) throws -> Data {
        guard OutputFormat.isEncodable(format) else { throw CompressionError.unsupportedFormat(format) }

        let source: CGImage
        switch alphaHandling {
        case .preserve:
            source = image
        case .flattenOnWhite:
            guard let flattened = flatten(image, on: CGColor(red: 1, green: 1, blue: 1, alpha: 1)) else {
                throw CompressionError.encodeFailed
            }
            source = flattened
        }

        if format == .webp {
            return try WebPEncoder.encode(
                image: source,
                quality: quality,
                lossless: lossless,
                metadata: metadata
            )
        }

        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer as CFMutableData,
            format.utTypeIdentifier as CFString,
            1,
            nil
        ) else {
            throw CompressionError.unsupportedFormat(format)
        }

        var properties: [CFString: Any] = [:]
        if format.usesLossyQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = max(0.0, min(1.0, quality))
        }
        if format == .jpeg {
            let jfif: [AnyHashable: Any] = [kCGImagePropertyJFIFIsProgressive: true]
            properties[kCGImagePropertyJFIFDictionary] = jfif
        }
        if let metadata {
            if let exif = metadata.exif, !exif.isEmpty {
                properties[kCGImagePropertyExifDictionary] = exif
            }
            if let tiff = metadata.tiff, !tiff.isEmpty {
                properties[kCGImagePropertyTIFFDictionary] = tiff
            }
            if let gps = metadata.gps, !gps.isEmpty {
                properties[kCGImagePropertyGPSDictionary] = gps
            }
            if let iptc = metadata.iptc, !iptc.isEmpty {
                properties[kCGImagePropertyIPTCDictionary] = iptc
            }
            if let eightBIM = metadata.eightBIM, !eightBIM.isEmpty {
                properties[kCGImageProperty8BIMDictionary] = eightBIM
            }
        }

        CGImageDestinationAddImage(destination, source, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CompressionError.encodeFailed }
        return buffer as Data
    }

    private static func flatten(_ image: CGImage, on color: CGColor) -> CGImage? {
        let hasAlpha = image.alphaInfo != .none && image.alphaInfo != .noneSkipFirst && image.alphaInfo != .noneSkipLast
        guard hasAlpha else { return image }
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: encodingColorSpace(for: image),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// Keeps wide-gamut sources (Display P3) intact while refusing spaces the
    /// encoders cannot write, such as CMYK or pattern spaces.
    private static func encodingColorSpace(for image: CGImage) -> CGColorSpace {
        if let space = image.colorSpace, space.model == .rgb {
            return space
        }
        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    // MARK: - Output paths

    public static func destinationURL(for job: ImageJob, options: CompressionOptions) -> URL {
        // A staged drop lives in the temp scratch folder, where "next to the
        // original" would bury the result where nobody can find it.
        let staged = DropStaging.isStaged(job.sourceURL)

        let sameFormat = isSameFormat(job.sourceURL, options.format) && !staged

        // Re-compressing in the family's own format replaces the file, which is
        // what "compress this photo again" is expected to do.
        if options.writeAlongside && sameFormat {
            return job.sourceURL
        }

        let folder: URL = options.writeAlongside && !staged
            ? job.sourceURL.deletingLastPathComponent()
            : (options.outputFolder ?? DropStaging.fallbackOutputFolder())

        let stem = job.sourceURL.deletingPathExtension().lastPathComponent
        let name = sameFormat ? stem : stem + options.nameSuffix
        var candidate = folder
            .appendingPathComponent(name)
            .appendingPathExtension(options.format.fileExtension)

        if options.avoidOverwrite && candidate != job.sourceURL {
            var counter = 2
            while FileManager.default.fileExists(atPath: candidate.path) {
                candidate = folder
                    .appendingPathComponent("\(name) (\(counter))")
                    .appendingPathExtension(options.format.fileExtension)
                counter += 1
            }
        }
        return candidate
    }

    static func isSameFormat(_ url: URL, _ format: OutputFormat) -> Bool {
        let ext = url.pathExtension.lowercased()
        switch format {
        case .jpeg: return ext == "jpg" || ext == "jpeg"
        case .heic: return ext == "heic" || ext == "heif"
        case .png: return ext == "png"
        case .webp: return ext == "webp"
        }
    }

    // MARK: - Helpers

    public static func fileSize(of url: URL) -> Int64 {
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let size = values.fileSize {
            return Int64(size)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    public static func formatName(of url: URL) -> String {
        let ext = url.pathExtension
        return ext.isEmpty ? "—" : ext.uppercased()
    }
}
