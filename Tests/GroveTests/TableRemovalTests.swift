import AppKit
import SwiftUI
import Testing
@testable import Grove

/// Removing a selected row once crashed: NSTableView re-rendered the outgoing cell outside
/// the view hierarchy, where `@Environment(GroveStore.self)` isn't available.
@MainActor
@Suite(.serialized)
struct TableRemovalTests {
    @Test func tableSurvivesTrashingTheSelectedRow() async throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "grove-ui-\(UUID().uuidString)").path
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "scripts/make-fixtures.sh").path
        try #require(await Shell.run("/bin/bash", [script, base], timeout: 120).ok)

        let store = GroveStore(rootPath: Scanner.normalize(base + "/code"), support: SupportFolder(url: URL(fileURLWithPath: base + "/support")))
        await store.scan()
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        store.undoManager = undoManager

        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView:
            NavigationStack { ItemListView(filter: .worktrees) }.environment(store)
        )
        window.orderFrontRegardless()
        await settle()

        let login = try #require(store.items.first { $0.name == "nebula-api-login" })
        store.selection = [login.id]
        await settle()

        undoManager.beginUndoGrouping()
        await store.performTrash(store.makeTrashPlan([login.id]))
        undoManager.endUndoGrouping()
        await settle()
        #expect(!store.items.contains { $0.id == login.id })

        undoManager.undo()
        for _ in 0..<200 where !(store.phase == .idle && store.items.contains { $0.id == login.id }) {
            await settle(0.05)
        }
        #expect(store.items.contains { $0.id == login.id })
        window.close()
        store.stop()
        try? FileManager.default.removeItem(atPath: base)
    }

    /// Spins the main run loop so SwiftUI and AppKit get to lay out and animate.
    private func settle(_ seconds: TimeInterval = 0.6) async {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            spin()
            await Task.yield()
        }
    }

    private func spin() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
}
