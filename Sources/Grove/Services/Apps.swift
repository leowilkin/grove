import AppKit

struct ExternalApp: Identifiable, Hashable, Sendable {
    var id: String { bundleID }
    var bundleID: String
    var name: String
    var url: URL
}

@MainActor
enum Apps {
    static let editorIDs = [
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.microsoft.VSCode",
        "dev.zed.Zed",
        "com.apple.dt.Xcode",
        "com.sublimetext.4",
        "com.panic.Nova",
        "com.exafunction.windsurf",
        "com.jetbrains.intellij",
        "com.jetbrains.WebStorm",
        "com.jetbrains.rubymine",
    ]

    static let terminalIDs = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
    ]

    static let editors: [ExternalApp] = installed(editorIDs)
    static let terminals: [ExternalApp] = installed(terminalIDs)

    private static var iconCache: [String: NSImage] = [:]

    static func installed(_ ids: [String]) -> [ExternalApp] {
        ids.compactMap { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            return ExternalApp(bundleID: id, name: name, url: url)
        }
    }

    /// The editor used most recently, so the default matches habit.
    static var defaultEditorID: String? {
        editors.max { lastUsed($0.url) < lastUsed($1.url) }?.bundleID
    }

    private static func lastUsed(_ url: URL) -> Date {
        NSMetadataItem(url: url)?.value(forAttribute: "kMDItemLastUsedDate") as? Date ?? .distantPast
    }

    static func icon(for bundleID: String) -> NSImage {
        if let cached = iconCache[bundleID] { return cached }
        let image: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
        }
        iconCache[bundleID] = image
        return image
    }

    static func app(_ bundleID: String?, in list: [ExternalApp]) -> ExternalApp? {
        list.first { $0.bundleID == bundleID } ?? list.first
    }

    static func open(_ paths: [String], with app: ExternalApp?) {
        let urls = paths.map { URL(fileURLWithPath: $0) }
        guard let app else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: app.url, configuration: config)
    }

    static func reveal(_ paths: [String]) {
        NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
    }

    static func browse(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
