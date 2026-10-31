import SwiftUI

struct SettingsView: View {
    @Environment(GroveStore.self) private var store
    @Environment(Updater.self) private var updater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var store = store
        @Bindable var updater = updater

        Form {
            Section {
                LabeledContent("Folder") {
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: store.rootPath))
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text(store.rootDisplay)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                Toggle("Include worktrees stored in other folders", isOn: $store.showExternalWorktrees)
            } header: {
                Text("Location")
            } footer: {
                Text("Grove looks at every folder in here, and one level into folders that group several repositories.")
                    .foregroundStyle(.secondary)
            }

            Section("Activity") {
                Picker("Active if touched within", selection: $store.activeDays) {
                    ForEach([3, 7, 14, 30], id: \.self) { Text("\($0) days").tag($0) }
                }
                Picker("Dormant after", selection: $store.dormantDays) {
                    ForEach([30, 60, 90, 180, 365], id: \.self) { days in
                        Text(days == 365 ? "1 year" : "\(days) days").tag(days)
                    }
                }
            }

            Section("Open With") {
                appPicker("Editor", selection: $store.editorID, apps: Apps.editors)
                appPicker("Terminal", selection: $store.terminalID, apps: Apps.terminals)
            }

            Section {
                Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
                LabeledContent("Version") {
                    HStack(spacing: 8) {
                        Text(updater.currentVersion)
                        Button("Check Now") {
                            updater.checkNow()
                            openWindow(id: "update")
                        }
                    }
                }
            } header: {
                Text("Updates")
            } footer: {
                Text(updatesFooter)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var updatesFooter: String {
        var text = updater.isInstalledCopy
            ? "Grove looks for a new release on GitHub once a day and asks before installing it."
            : "Updates install into Applications, so this copy only checks when you ask."
        if let date = updater.lastChecked {
            text += " Last checked \(date.formatted(.relative(presentation: .named)))."
        }
        return text
    }

    private func appPicker(_ title: String, selection: Binding<String?>, apps: [ExternalApp]) -> some View {
        Picker(title, selection: selection) {
            ForEach(apps) { app in
                Label {
                    Text(app.name)
                } icon: {
                    Image(nsImage: Apps.icon(for: app.bundleID))
                }
                .tag(Optional(app.bundleID))
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: store.rootPath)
        panel.prompt = "Choose"
        panel.message = "Choose the folder where you keep your git repositories."
        if panel.runModal() == .OK, let url = panel.url {
            store.rootPath = url.path
        }
    }
}
