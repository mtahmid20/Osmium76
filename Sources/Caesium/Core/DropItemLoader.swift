import Foundation
import UniformTypeIdentifiers

/// Pulls a real file path out of an `NSItemProvider` from a drag session.
///
/// `loadObject(ofClass: URL.self)` looks like the obvious call and works for a
/// synthesised provider, but Finder vends `public.file-url` as a *bookmark*
/// blob: `loadObject` then "succeeds" with a URL whose path is the raw bookmark
/// bytes (`book@@@^T~...`), and `err` is still nil. That non-existent path is
/// what made real Finder drops fall through to the image-payload path and get
/// staged into the temp folder. Reading the representation directly and
/// decoding it ourselves is the only reliable route.
enum DropItemLoader {

    static func fileURL(from provider: NSItemProvider) async -> URL? {
        // Preferred: the raw representation, decoded below.
        if let url = await loadFileURLRepresentation(provider) { return url }

        // Some sources only vend it through the object loader. Accept the
        // result only if it is a path that actually exists on disk, so a
        // mis-decoded bookmark cannot masquerade as a real file.
        if let url = await loadObjectURL(provider), isUsableFile(url) { return url }
        return nil
    }

    private static func loadFileURLRepresentation(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            let resume = ResumeOnce(continuation)
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                resume.call(data.flatMap(decodeFileURLData))
            }
        }
    }

    private static func loadObjectURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            let resume = ResumeOnce(continuation)
            _ = provider.loadObject(ofClass: URL.self) { object, _ in
                resume.call(object)
            }
        }
    }

    /// Finder sends the raw path bytes, but a source is free to send a
    /// percent-encoded URL or a security-scoped bookmark instead, so all three
    /// shapes are accepted.
    static func decodeFileURLData(_ data: Data) -> URL? {
        if let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("file://") {
                if let url = URL(string: trimmed), isUsableFile(url) { return url }
            } else if trimmed.hasPrefix("/") {
                let url = URL(fileURLWithPath: trimmed)
                if isUsableFile(url) { return url }
            }
        }
        // Anything else is treated as a bookmark.
        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), isUsableFile(url) {
            return url
        }
        return nil
    }

    /// A dropped folder is legitimately a directory, so existence is the test
    /// rather than "is a file".
    private static func isUsableFile(_ url: URL) -> Bool {
        guard url.isFileURL, !url.path.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}

/// Guards a continuation against a provider calling back more than once or
/// never at all, which would otherwise crash or hang the drop.
private final class ResumeOnce: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    private let continuation: CheckedContinuation<URL?, Never>

    init(_ continuation: CheckedContinuation<URL?, Never>) {
        self.continuation = continuation
    }

    func call(_ value: URL?) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        continuation.resume(returning: value)
    }
}