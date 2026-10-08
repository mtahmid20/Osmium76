import Foundation
import UniformTypeIdentifiers

public enum ImageScanner {

    public static let inputExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "png", "heic", "heif", "webp",
        "tif", "tiff", "bmp", "gif", "ico", "avif", "jp2", "j2k"
    ]

    public static func isSupported(_ url: URL) -> Bool {
        inputExtensions.contains(url.pathExtension.lowercased())
    }

    /// Every supported image under `folder`, including nested folders.
    public static func images(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        guard let walker = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [URL] = []
        for case let url as URL in walker {
            if isSupported(url) {
                results.append(url)
            }
        }
        return results.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Builds a job, or nil when the file cannot be read as an image.
    public static func job(for url: URL, thumbnail: Bool = true) -> ImageJob? {
        guard let info = ImageCompressor.inspect(url: url) else { return nil }
        guard info.pixelWidth > 0, info.pixelHeight > 0 else { return nil }

        var thumb: Data? = nil
        if thumbnail {
            thumb = ImageCompressor.thumbnailData(for: url)
        }
        return ImageJob(
            sourceURL: url,
            originalSize: info.fileSize,
            pixelWidth: info.pixelWidth,
            pixelHeight: info.pixelHeight,
            sourceFormat: ImageCompressor.formatName(of: url),
            thumbnail: thumb,
            frameCount: info.frameCount,
            isAnimatedSource: info.isAnimated
        )
    }
}
