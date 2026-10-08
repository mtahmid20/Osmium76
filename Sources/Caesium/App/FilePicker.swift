import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum FilePicker {
    @MainActor
    static func openFiles(into model: CompressionModel) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose images to compress"
        panel.allowedContentTypes = ImageScanner.inputExtensions.compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK {
            model.addFiles(panel.urls)
        }
    }

    @MainActor
    static func openFolder(into model: CompressionModel) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose a folder — sub-folders are included"
        panel.prompt = "Add"
        if panel.runModal() == .OK, let url = panel.url {
            model.addFiles([url])
        }
    }

    @MainActor
    static func chooseOutputFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Where should the compressed images go?"
        panel.prompt = "Select"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
