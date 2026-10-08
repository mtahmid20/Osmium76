import Foundation

/// Tracks which files are scratch copies made while handling a drop.
///
/// A drop from Photos or Safari arrives as raw bytes, so it is written to a temp
/// file first. That file is not something the user can see or wants to keep, so
/// "save next to the original" and "delete the original" both need special
/// handling: the output has to go somewhere real, and the staged copy always
/// goes away.
public enum DropStaging {

    public static let folderName = "Caesium Drops"

    public static var folder: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(folderName, isDirectory: true)
    }

    public static func isStaged(_ url: URL) -> Bool {
        let root = folder.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == root || path.hasPrefix(root + "/")
    }

    /// Last-resort destination if a staged drop somehow reaches the encoder with no
    /// folder chosen. `CompressionModel.start()` normally asks the user first.
    public static func fallbackOutputFolder() -> URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let folder = pictures.appendingPathComponent("Caesium", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Deletes stale scratch copies from earlier sessions, so the temp folder
    /// does not accumulate images that were queued but never compressed.
    public static func purgeStaleFiles(olderThan interval: TimeInterval = 60 * 60 * 24) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-interval)
        for entry in entries {
            let modified = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
            guard let date = modified?.contentModificationDate, date < cutoff else { continue }
            try? FileManager.default.removeItem(at: entry)
        }
    }
}