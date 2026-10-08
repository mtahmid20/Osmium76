import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

public enum CompressionError: LocalizedError {
case cancelled
case unreadableSource
    case noFrames
    case decodeFailed
    case unsupportedFormat(OutputFormat)
    case encodeFailed
    case animatedSource(frameCount: Int)
    case destinationUnavailable
    case writeFailed(String)
    case webPEncoderMissing

    public var errorDescription: String? {
        switch self {
        case .cancelled: "Stopped."
        case .unreadableSource: "The file could not be opened."
        case .noFrames: "The file contains no image frames."
        case .decodeFailed: "The image data could not be decoded."
        case .unsupportedFormat(let format):
            "This Mac cannot encode \(format.displayName). Pick another format."
        case .encodeFailed: "The image encoder failed."
        case .animatedSource(let frames):
            "\(frames) frames — animations and multi-page documents are left untouched."
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
        /// Frames in the container. > 1 does not imply animation: a multi-size
        /// .ico has one frame per resolution.
        public let frameCount: Int
        /// True only when those frames are separate images.
        public let isAnimated: Bool
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
        let type = CGImageSourceGetType(source) as String? ?? ""

        return SourceInfo(
            pixelWidth: width,
            pixelHeight: height,
            fileSize: fileSize(of: url),
            formatName: formatName(of: url),
            orientation: orientation,
            hasAlpha: hasAlpha,
            frameCount: CGImageSourceGetCount(source),
            // A multi-size .ico reports one frame per resolution of the same
            // image, so the raw count must not be read as "animated" or the
            // sidebar would warn about a perfectly ordinary icon.
            isAnimated: CGImageSourceGetCount(source) > 1 && frameCountIsContent(type)
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
    ///
    /// - Parameter isCancelled: polled at each stage so a long encode can be
    ///   abandoned promptly. Cancellation must never discard a file that has
    ///   already been written, so callers check this *before* the destructive
    ///   write, not after.
    public static func compress(
        source data: Data,
        options: CompressionOptions,
        isCancelled: () -> Bool = { false }
    ) throws -> Output {
        try checkCancelled(isCancelled)
        guard OutputFormat.isEncodable(options.format) else {
            throw CompressionError.unsupportedFormat(options.format)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw CompressionError.unreadableSource
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { throw CompressionError.noFrames }
        // Only frame 0 is ever decoded and a single-frame destination is built,
        // so a multi-frame source would silently lose its remaining frames —
        // and the caller is allowed to delete the original afterwards. Refuse
        // rather than destroy the animation.
        //
        // Only for containers where a frame is real content. A multi-size .ico
        // reports one frame per resolution of the *same* icon, so refusing it
        // would reject an ordinary file with a misleading message.
        let type = CGImageSourceGetType(source) as String? ?? ""
        guard frameCount == 1 || !Self.frameCountIsContent(type) else {
            throw CompressionError.animatedSource(frameCount: frameCount)
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientationValue = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up

        let decodeOptions: [CFString: Any] = [kCGImageSourceShouldCache: true]
        guard let raw = CGImageSourceCreateImageAtIndex(source, 0, decodeOptions as CFDictionary) else {
            throw CompressionError.decodeFailed
        }

        let prepared = try prepare(raw, orientation: orientation, options: options)
        try checkCancelled(isCancelled)
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
            alphaHandling: alpha,
            isCancelled: isCancelled
        )
        return Output(data: encoded, pixelWidth: prepared.width, pixelHeight: prepared.height)
    }

    private static func checkCancelled(_ isCancelled: () -> Bool) throws {
        if isCancelled() { throw CompressionError.cancelled }
    }

    /// Containers whose extra frames are separate images rather than alternate
    /// resolutions of one image. `com.microsoft.ico` is deliberately absent: its
    /// frames are the same icon at different sizes, so decoding frame 0 loses
    /// nothing meaningful and refusing it would be wrong.
    private static func frameCountIsContent(_ type: String) -> Bool {
        switch type {
        case "com.compuserve.gif",
             "org.webmproject.webp",
             "com.apple.icns",
             "com.adobe.photoshop-image",
             "public.avif":
            return true
        default:
            // APNG and multi-page TIFF both report public.png / public.tiff.
            return type == "public.png" || type == "public.tiff"
        }
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
        alphaHandling: AlphaHandling,
        isCancelled: () -> Bool = { false }
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
                metadata: metadata,
                isCancelled: isCancelled
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
        destinationURL(for: job, options: options, reservedPaths: [])
    }

    /// - Parameter reservedPaths: paths already claimed by this batch. Two
    ///   sources with the same stem in different folders collapse to one name
///   in a shared output folder resolve to the same name. Resolving each
///   independently races: both see the name as free and both write it, so one
///   output is overwritten and both originals may then be deleted. Reserving on
///   the main actor, before any encoding starts, makes the assignment
///   single-threaded regardless of parallelism.
    public static func destinationURL(
        for job: ImageJob,
        options: CompressionOptions,
        reservedPaths: Set<String>
    ) -> URL {
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

        // Two jobs in one batch must never be handed the same output path, whatever
        // the user's naming preference. With "Never overwrite" off they would
        // both see the name as free, both write it, and — if originals are being
        // deleted — two source photos would be destroyed to produce one file.
        // So an occupied name always advances, and only the check against files
        // already on disk is a user setting.
        var counter = 2
        while isTaken(candidate, by: job, options: options, reserved: reservedPaths) {
            candidate = folder
                .appendingPathComponent("\(name) (\(counter))")
                .appendingPathExtension(options.format.fileExtension)
            counter += 1
        }
        return candidate
    }

    private static func isTaken(
        _ candidate: URL,
        by job: ImageJob,
        options: CompressionOptions,
        reserved: Set<String>
    ) -> Bool {
        if candidate == job.sourceURL { return false }
        if reserved.contains(candidate.standardizedFileURL.path) { return true }
        return options.avoidOverwrite && FileManager.default.fileExists(atPath: candidate.path)
    }

    /// Assigns a distinct destination to every job in a batch. Must be called
    /// once on the main actor before encoding starts; the result is passed
    /// through to `BatchRunner` so each file writes where it was promised.
    public static func reserveDestinations(
        for jobs: [ImageJob],
        options: CompressionOptions
    ) -> [ImageJob.ID: URL] {
        var reserved = Set<String>()
        var assignments: [ImageJob.ID: URL] = [:]
        for job in jobs {
            let url = destinationURL(for: job, options: options, reservedPaths: reserved)
            reserved.insert(url.standardizedFileURL.path)
            assignments[job.id] = url
        }
        return assignments
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
