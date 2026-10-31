import SwiftUI

@main
struct GroveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = GroveStore()
    @State private var updater = Updater()

    var body: some Scene {
        WindowGroup("Grove", id: "main") {
            ContentView()
                .environment(store)
                .environment(updater)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1320, height: 820)
        .commands { GroveCommands(store: store, updater: updater) }

        Window("Software Update", id: "update") {
            UpdateView()
                .environment(updater)
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .commandsRemoved()

        Settings {
            SettingsView()
                .environment(store)
                .environment(updater)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await Actions.sweepParkingLot() }
    }
}

struct GroveCommands: Commands {
    var store: GroveStore
    var updater: Updater
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                updater.checkNow()
                openWindow(id: "update")
            }
        }

        CommandGroup(replacing: .newItem) {}

        CommandMenu("Repository") {
            Button("Refresh") { store.refresh() }
                .keyboardShortcut("r")
                .disabled(store.isBusy)
            Button("Fetch All Remotes") { store.fetchAll() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(store.isBusy)

            Divider()

            let paths = store.selectedItems.filter { !$0.isMissing }.map(\.path)
            Button("Open in \(store.editor?.name ?? "Editor")") { store.openInEditor(paths) }
                .keyboardShortcut("o")
                .disabled(paths.isEmpty)
            Button("Open in \(store.terminal?.name ?? "Terminal")") { store.openInTerminal(paths) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(paths.isEmpty)
            Button("Show in Finder") { store.reveal(paths) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(paths.isEmpty)
            Button("Open Remote in Browser") {
                if let item = store.selectedItems.first { store.browse(item) }
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(store.selectedItems.count != 1 || store.selectedItems.first?.webURL == nil)

            Divider()

            Button("Clean Up Branches…") {
                let repos = store.selectedItems.filter { $0.kind == .repository }.map(\.path)
                store.branchPlan = store.makeBranchPlan(scope: repos.isEmpty ? nil : repos)
            }

            Divider()

            Button("Move to Trash…") { store.requestTrash(store.selection) }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(store.selection.isEmpty)
        }
    }
}
