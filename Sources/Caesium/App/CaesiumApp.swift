import SwiftUI

@main
struct CaesiumApp: App {
    @State private var model = CompressionModel()

    init() {
        DropStaging.purgeStaleFiles()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 940, minHeight: 700)
        }
        .defaultSize(width: 1_240, height: 780)
        .windowToolbarStyle(.unified)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// Menu-bar commands get the model handed to them directly. Reading it through
/// @Environment traps at launch: the commands are evaluated from
/// applicationWillFinishLaunching, before any scene has installed the object.
struct AppCommands: Commands {
    @Bindable var model: CompressionModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Files…") { FilePicker.openFiles(into: model) }
                .keyboardShortcut("o", modifiers: .command)
            Button("Add Folder…") { FilePicker.openFolder(into: model) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandMenu("Image") {
            Button("Compress") { model.start() }
                .disabled(!model.canStart)
            Button("Stop") { model.cancel() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!model.isRunning)
            Divider()
            Button("Remove Selected") {
                if let id = model.selection { model.remove([id]) }
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(model.isRunning || model.selection == nil)
            Button("Clear Completed") { model.clearFinished() }
                .disabled(model.isRunning)
            Button("Reset Queue") { model.resetQueue() }
                .disabled(model.isRunning)
        }
    }
}
