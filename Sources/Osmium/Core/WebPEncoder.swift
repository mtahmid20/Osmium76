import Foundation
import CoreGraphics
import ImageIO

/// ImageIO on current macOS builds decodes WebP but has no WebP *encoder*
/// registered, so `CGImageDestinationCreateWithData` fails for it. libwebp's
/// `cwebp` ships with Homebrew and is used instead.
///
/// The image is handed to cwebp as a PNG, which is lossless and carries alpha,
/// so the pixels arrive unchanged; only the final WebP container is lossy.
public enum WebPEncoder {

    /// Where `cwebp` lives, checked in the usual Homebrew locations and then on PATH.
    public static let toolURL: URL? = {
        let candidates = [
            "/opt/homebrew/bin/cwebp",
            "/usr/local/bin/cwebp",
            "/opt/local/bin/cwebp"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        let searchPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { "\($0)/cwebp" }
        for path in searchPaths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }()

    public static var isAvailable: Bool { toolURL != nil }

    /// Human-readable reason shown when WebP is selected but cwebp is missing.
    public static var unavailableReason: String {
        "WebP needs the libwebp encoder. Install it with: brew install webp"
    }

    // MARK: - Encoding

    static func encode(
        image: CGImage,
        quality: Double,
        lossless: Bool,
        metadata: MetadataPolicy.Payload?,
        isCancelled: () -> Bool = { false }
    ) throws -> Data {
        guard let toolURL else { throw CompressionError.webPEncoderMissing }

        let staging = try stagingFolder()
        defer { try? FileManager.default.removeItem(at: staging) }

        let inputURL = staging.appendingPathComponent("in.png")
        let outputURL = staging.appendingPathComponent("out.webp")

        try writePNG(image, metadata: metadata, to: inputURL)
        if isCancelled() { throw CompressionError.cancelled }

        var arguments = [
            "-quiet",
            "-metadata", metadata == nil ? "none" : "all"
        ]
        if lossless {
            arguments += ["-lossless", "-z", "9"]
        } else {
            arguments += ["-q", String(Int((max(0, min(1, quality)) * 100).rounded()))]
        }
        if image.width > 4096 || image.height > 4096 {
            arguments.append("-mt")
        }
        arguments += [inputURL.path, "-o", outputURL.path]

        // cwebp can take many seconds on a large image and `waitUntilExit()` is
        // uninterruptible, so termination is polled and the child is killed
        // as soon as the user hits Stop.
        try run(toolURL, arguments: arguments, isCancelled: isCancelled)

        guard let data = try? Data(contentsOf: outputURL), !data.isEmpty else {
            throw CompressionError.encodeFailed
        }
        return data
    }

    // MARK: - Helpers

    /// One folder per encode so parallel jobs never collide on the same filenames.
    private static func stagingFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Osmium WebP", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// cwebp only reads EXIF/ICC/XMP, so the payload is written into the PNG
    /// intermediate and picked up by `-metadata all`.
    private static func writePNG(
        _ image: CGImage,
        metadata: MetadataPolicy.Payload?,
        to url: URL
    ) throws {
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer as CFMutableData,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw CompressionError.encodeFailed
        }

        var properties: [CFString: Any] = [:]
        if let metadata {
            if let exif = metadata.exif, !exif.isEmpty {
                properties[kCGImagePropertyExifDictionary] = exif
            }
            if let tiff = metadata.tiff, !tiff.isEmpty {
                properties[kCGImagePropertyTIFFDictionary] = tiff
            }
        }
        // GPS, IPTC and 8BIM have no WebP equivalent, so they are dropped here.

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CompressionError.encodeFailed
        }
        try (buffer as Data).write(to: url, options: .atomic)
    }

    private static func run(
        _ tool: URL,
        arguments: [String],
        isCancelled: () -> Bool
    ) throws {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw CompressionError.webPEncoderMissing
        }

        while process.isRunning {
            if isCancelled() {
                process.terminate()
                throw CompressionError.cancelled
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        guard process.terminationStatus == 0 else {
            throw CompressionError.encodeFailed
        }
    }
}