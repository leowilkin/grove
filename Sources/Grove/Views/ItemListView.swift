import SwiftUI

struct ItemListView: View {
    @Environment(GroveStore.self) private var store
    var filter: SidebarItem

    @State private var sortOrder = [KeyPathComparator(\GroveItem.activityKey, order: .reverse)]

    var body: some View {
        @Bindable var store = store
        let rows = store.items(for: filter).sorted(using: sortOrder)

        Table(rows, selection: $store.selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name, comparator: .localizedStandard) { item in
                NameCell(
                    item: item,
                    isPinned: store.pinned.contains(item.path),
                    worktreeCount: item.kind == .repository ? store.worktrees(of: item).count : 0
                )
            }
            .width(min: 160, ideal: 290)

            // Status and activity come before branch: in a narrow window, they're what's
            // left on screen, and they're what cleanup decisions hang on.
            TableColumn("Status", value: \.statusRank) { item in
                if showsReason, let reason = store.cleanupReason(item) {
                    Text(reason.label).foregroundStyle(.secondary)
                } else {
                    StatusPills(item: item)
                }
            }
            .width(min: 96, ideal: 210)

            TableColumn("Last Activity", value: \.activityKey) { item in
                ActivityCell(item: item, activity: store.activity(item))
            }
            .width(min: 88, ideal: 130)

            TableColumn("Branch", value: \.branchKey, comparator: .localizedStandard) { item in
                BranchCell(item: item)
            }
            .width(min: 80, ideal: 190)

            TableColumn("Size", value: \.sizeKey) { item in
                Text(item.size.map(\.bytesLabel) ?? (item.isMissing ? "—" : "…"))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 52, ideal: 76)
        }
        .contextMenu(forSelectionType: GroveItem.ID.self) { ids in
            // Menus are built outside the view hierarchy, like table cells.
            ItemMenu(ids: ids).environment(store)
        } primaryAction: { ids in
            store.openInEditor(store.items.filter { ids.contains($0.id) && !$0.isMissing }.map(\.path))
        }
        .onDeleteCommand { store.requestTrash(store.selection) }
        .overlay {
            if rows.isEmpty {
                if store.searchText.isEmpty {
                    ContentUnavailableView(filter.title, systemImage: filter.symbol, description: Text(filter.emptyMessage))
                } else {
                    ContentUnavailableView.search(text: store.searchText)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                ToastSlot()
                if store.selection.count > 1 {
                    SelectionBar(items: store.selectedItems)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, 14)
        }
        .animation(.smooth(duration: 0.25), value: store.selection.count > 1)
        .inspector(isPresented: $store.showInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 280, ideal: 320, max: 480)
                .toolbar {
                    ToolbarItem {
                        Button {
                            store.showInspector.toggle()
                        } label: {
                            Label("Inspector", systemImage: "sidebar.trailing")
                        }
                        .help("Show or hide the inspector (⌥⌘I)")
                        .keyboardShortcut("i", modifiers: [.command, .option])
                    }
                }
        }
        .navigationTitle(filter.title)
        .onAppear { keepSelectionVisible(rows) }
        // A search that hides the selected rows shouldn't leave them in the inspector.
        .onChange(of: store.searchText) { keepSelectionVisible(store.items(for: filter)) }
    }

    private func keepSelectionVisible(_ rows: [GroveItem]) {
        let visible = Set(rows.map(\.id))
        let kept = store.selection.filter(visible.contains)
        if kept != store.selection { store.selection = kept }
    }

    private var showsReason: Bool {
        [.cleanup, .finishedWorktrees, .dormantRepositories].contains(filter)
    }
}

/// Table cells take plain values: NSTableView can re-render a row that's being removed
/// outside the view hierarchy, where environment objects aren't available.
private struct NameCell: View {
    var item: GroveItem
    var isPinned: Bool
    var worktreeCount: Int

    var body: some View {
        HStack(spacing: 9) {
            IconTile(kind: item.kind, missing: item.isMissing, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(item.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        var parts: [String] = []
        switch item.kind {
        case .repository:
            if let group = item.group { parts.append("in \(group)") }
            if let remote = item.git?.remoteURL {
                parts.append(RemoteURL.short(remote))
            } else {
                parts.append("No remote")
            }
            if worktreeCount > 0 { parts.append("\(worktreeCount) worktree\(worktreeCount == 1 ? "" : "s")") }
        case .worktree:
            let parentName = item.parentPath.map { ($0 as NSString).lastPathComponent } ?? "unknown repository"
            parts.append("of \(parentName)")
            if !item.isInsideRoot {
                parts.append((item.path as NSString).deletingLastPathComponent.abbreviatedPath)
            } else if item.isNestedInParent, let parent = item.parentPath {
                let relative = String(item.path.dropFirst(parent.count + 1))
                parts.append("in " + (relative as NSString).deletingLastPathComponent)
            }
        case .folder:
            parts.append("Folder")
        }
        return parts.joined(separator: " · ")
    }
}

extension String {
    var abbreviatedPath: String { (self as NSString).abbreviatingWithTildeInPath }
}

private struct BranchCell: View {
    var item: GroveItem

    var body: some View {
        if let git = item.git, let label = item.branchLabel {
            HStack(spacing: 6) {
                Text(label)
                    .font(.callout.monospaced())
                    .foregroundStyle(git.branch == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if git.ahead > 0 || git.behind > 0 {
                    HStack(spacing: 2) {
                        if git.ahead > 0 { Text("↑\(git.ahead)") }
                        if git.behind > 0 { Text("↓\(git.behind)") }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }
}

private struct ActivityCell: View {
    var item: GroveItem
    var activity: Activity

    var body: some View {
        if let date = item.lastActivity {
            HStack(spacing: 6) {
                ActivityDot(activity: activity)
                Text(date.relativeLabel)
                    .foregroundStyle(activity == .dormant ? .secondary : .primary)
            }
            .help(date.formatted(date: .complete, time: .shortened))
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }
}

struct ItemMenu: View {
    @Environment(GroveStore.self) private var store
    var ids: Set<String>

    var body: some View {
        let items = store.items.filter { ids.contains($0.id) }
        let paths = items.filter { !$0.isMissing }.map(\.path)
        let single = items.count == 1 ? items.first : nil

        if !paths.isEmpty {
            Button("Open in \(store.editor?.name ?? "Editor")") { store.openInEditor(paths) }
            Button("Open in \(store.terminal?.name ?? "Terminal")") { store.openInTerminal(paths) }
            Button("Show in Finder") { store.reveal(paths) }
        }
        if let single, single.webURL != nil {
            Button("Open Remote in Browser") { store.browse(single) }
        }
        if let single {
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(single.path, forType: .string)
            }
        }
        if let single, single.kind == .repository {
            Divider()
            Button(store.pinned.contains(single.path) ? "Unpin" : "Pin to Sidebar") { store.togglePin(single.path) }
            if !store.deletableBranches(in: single).isEmpty {
                Button("Clean Up Branches…") { store.branchPlan = store.makeBranchPlan(scope: [single.path]) }
            }
        }
        Divider()
        Button(items.allSatisfy(\.isMissing) ? "Forget Missing Worktree…" : "Move to Trash…", role: .destructive) {
            store.requestTrash(ids)
        }
    }
}

private struct SelectionBar: View {
    @Environment(GroveStore.self) private var store
    var items: [GroveItem]

    var body: some View {
        let bytes = store.totalBytes(items)
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(items.count) selected").fontWeight(.semibold)
                if let bytes {
                    Text(bytes.bytesLabel).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 6)

            Divider().frame(height: 22)

            Button {
                store.reveal(items.filter { !$0.isMissing }.map(\.path))
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            .buttonStyle(.glass)

            Button(role: .destructive) {
                store.requestTrash(Set(items.map(\.id)))
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .buttonStyle(.glassProminent)
            .tint(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassEffect(.regular.tint(.floatingBarTint), in: .capsule)
        .shadow(color: .black.opacity(0.1), radius: 14, y: 4)
    }
}
