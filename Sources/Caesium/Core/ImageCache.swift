import AppKit
import ImageIO

/// Small memo so table rows and the preview pane do not re-decode on every redraw.
/// `@unchecked Sendable` is accurate: the only mutable state is an NSCache, which
/// is thread-safe, and it is reached from the encoder's background tasks.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 600
    }

    func thumbnail(for job: ImageJob) -> NSImage? {
        let key = "thumb-\(job.id.uuidString)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = job.thumbnail, let image = Self.makeImage(from: data, maxPixel: 240) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    func preview(for url: URL, maxPixel: CGFloat = 1800) -> NSImage? {
        let key = "preview-\(url.path)-\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = ImageCompressor.previewData(for: url, maxPixel: Int(maxPixel)),
              let image = Self.makeImage(from: data, maxPixel: maxPixel) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    func store(_ image: NSImage, for url: URL, maxPixel: CGFloat = 1800) {
        cache.setObject(image, forKey: "preview-\(url.path)-\(Int(maxPixel))" as NSString)
    }

    /// Decodes already-downscaled JPEG payloads produced by the encoder.
    func image(from data: Data, maxPixel: CGFloat = 1800) -> NSImage? {
        let key = "data-\(data.count)-\(data.prefix(16).hashValue)-\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = Self.makeImage(from: data, maxPixel: maxPixel) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    func invalidate(url: URL) {
        cache.removeObject(forKey: "preview-\(url.path)-1800" as NSString)
    }

    private static func makeImage(from data: Data, maxPixel: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        )
    }
}
