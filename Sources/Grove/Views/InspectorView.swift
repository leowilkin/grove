import SwiftUI

struct InspectorView: View {
    @Environment(GroveStore.self) private var store

    var body: some View {
        let selected = store.selectedItems
        Group {
            if selected.count == 1, let item = selected.first {
                ItemDetail(item: item)
                    .id(item.id)
            } else if selected.count > 1 {
                MultiSelectionDetail(items: selected)
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "sidebar.trailing",
                    description: Text("Select a repository, worktree, or folder to see what's in it.")
                )
            }
        }
    }
}

// MARK: Single item

private struct ItemDetail: View {
    @Environment(GroveStore.self) private var store
    var item: GroveItem

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                if !item.isMissing { actions }
                if let git = item.git, !item.isMissing {
                    statusSection(git)
                    if let commit = git.lastCommit { commitSection(commit) }
                }
                if item.isMissing { missingSection }
                if item.kind == .repository {
                    worktreeSection
                    branchSection
                }
                if item.kind == .worktree, let parent = item.parentPath.flatMap(store.item(at:)) {
                    parentSection(parent)
                }
                detailsSection
                dangerSection
            }
            .padding(16)
        }
    }

    // Header

    private var header: some View {
        VStack(spacing: 8) {
            IconTile(kind: item.kind, missing: item.isMissing, size: 56)
                .padding(.top, 6)
            Text(item.name)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            Text(item.displayPath)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            let activity = store.activity(item)
            HStack(spacing: 6) {
                Pill(text: item.kind.label, symbol: nil, tint: item.kind.tint)
                if item.kind != .folder || item.lastActivity != nil {
                    Pill(text: activity.label, symbol: nil, tint: activity.color)
                }
                if store.pinned.contains(item.path) {
                    Pill(text: "Pinned", symbol: "pin.fill", tint: .orange)
                }
            }
            if let reason = store.cleanupReason(item) {
                Label(reason.label, systemImage: "leaf.fill")
                    .font(.callout)
                    .foregroundStyle(.mint)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            ActionTile(title: "Finder", image: Image(nsImage: Apps.icon(for: "com.apple.finder"))) {
                store.reveal([item.path])
            }
            if let editor = store.editor {
                ActionTile(title: editor.name, image: Image(nsImage: Apps.icon(for: editor.bundleID))) {
                    store.openInEditor([item.path])
                }
            }
            if let terminal = store.terminal {
                ActionTile(title: terminal.name, image: Image(nsImage: Apps.icon(for: terminal.bundleID))) {
                    store.openInTerminal([item.path])
                }
            }
            if item.webURL != nil {
                ActionTile(title: remoteHostName, image: Image(systemName: "safari"), isTemplate: true) {
                    store.browse(item)
                }
            }
        }
    }

    private var remoteHostName: String {
        switch item.webURL?.host() {
        case "github.com": "GitHub"
        case "gitlab.com": "GitLab"
        case "bitbucket.org": "Bitbucket"
        default: "Remote"
        }
    }

    // Sections

    private func statusSection(_ git: GitInfo) -> some View {
        InspectorSection("Status") {
            InfoRow("Branch") {
                Text(item.branchLabel ?? "No commits yet")
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
            if let upstream = git.upstream {
                InfoRow("Tracking") {
                    HStack(spacing: 6) {
                        Text(upstream).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                        if git.upstreamGone {
                            Pill(text: "Deleted", symbol: nil, tint: .purple)
                        } else if git.ahead > 0 || git.behind > 0 {
                            Text("↑\(git.ahead) ↓\(git.behind)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            } else if git.branch != nil {
                InfoRow("Tracking") { Text("Not tracking a remote branch").foregroundStyle(.secondary) }
            }
            InfoRow("Working tree") {
                if item.uncommitted == 0 {
                    Label("Clean", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        if git.changes > 0 { Text("\(git.changes) modified") }
                        if git.untracked > 0 { Text("\(git.untracked) untracked") }
                        if git.conflicts > 0 { Text("\(git.conflicts) conflicted").foregroundStyle(.red) }
                    }
                    .foregroundStyle(.orange)
                }
            }
            if git.remoteURL != nil {
                InfoRow("Not on remote") {
                    let n = item.kind == .repository ? max(git.unpushed, git.unpushedAllBranches) : git.unpushed
                    Text(n == 0 ? "Nothing — all pushed" : store.count(n, "commit"))
                        .foregroundStyle(n == 0 ? .secondary : Color.blue)
                }
            }
            if git.stashes > 0 {
                InfoRow("Stashes") { Text("\(git.stashes)") }
            }
            if let remote = git.remoteURL {
                InfoRow("Remote") {
                    Text(RemoteURL.short(remote))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            } else {
                InfoRow("Remote") { Text("None — local only").foregroundStyle(.orange) }
            }
        }
    }

    private func commitSection(_ commit: CommitInfo) -> some View {
        InspectorSection("Last Commit") {
            VStack(alignment: .leading, spacing: 6) {
                Text(commit.subject)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    Text(commit.shortSHA).font(.caption.monospaced())
                    Text("·")
                    Text(commit.author).lineLimit(1)
                    Spacer()
                    Text(commit.date.relativeLabel)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
        }
    }

    private var missingSection: some View {
        InspectorSection("Missing Folder") {
            Text("This worktree's folder was deleted, but git still has a record of it. Its branch stays reserved until the record is cleared.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
        }
    }

    @ViewBuilder
    private var worktreeSection: some View {
        let worktrees = store.worktrees(of: item)
        if !worktrees.isEmpty {
            InspectorSection("Worktrees", trailing: "\(worktrees.count)") {
                ForEach(Array(worktrees.prefix(12).enumerated()), id: \.element.id) { index, worktree in
                    if index > 0 { Divider().padding(.leading, 40) }
                    Button {
                        store.selection = [worktree.id]
                    } label: {
                        HStack(spacing: 10) {
                            IconTile(kind: .worktree, missing: worktree.isMissing, size: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(worktree.name).lineLimit(1)
                                Text(worktree.branchLabel ?? "—")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 6)
                            if let issue = worktree.issues.first {
                                issue.pill
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                if worktrees.count > 12 {
                    Divider()
                    Button("Show all \(worktrees.count) worktrees") {
                        store.pinned.insert(item.path)
                        store.show(.project(item.path))
                    }
                    .buttonStyle(.link)
                    .padding(10)
                }
            }
        }
    }

    @ViewBuilder
    private var branchSection: some View {
        if let git = item.git, !git.branches.isEmpty {
            let deletable = store.deletableBranches(in: item)
            let gone = git.branches.filter(\.upstreamGone).count
            let merged = git.branches.filter(\.isMerged).count
            InspectorSection("Branches", trailing: "\(git.branches.count)") {
                InfoRow("Local branches") { Text("\(git.branches.count)") }
                if merged > 0 { InfoRow("Merged") { Text("\(merged)") } }
                if gone > 0 { InfoRow("Remote deleted") { Text("\(gone)") } }
                if !deletable.isEmpty {
                    Divider()
                    HStack {
                        Text("\(store.count(deletable.count, "branch")) can go")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clean Up…") {
                            store.branchPlan = store.makeBranchPlan(scope: [item.path])
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func parentSection(_ parent: GroveItem) -> some View {
        InspectorSection("Repository") {
            Button {
                store.selection = [parent.id]
            } label: {
                HStack(spacing: 10) {
                    IconTile(kind: .repository, size: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(parent.name)
                        Text(parent.displayPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private var detailsSection: some View {
        InspectorSection("Details") {
            InfoRow("Last activity") {
                Text(item.lastActivity.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Unknown")
            }
            InfoRow("Size on disk") {
                Text(item.size?.bytesLabel ?? (item.isMissing ? "—" : "Measuring…"))
            }
            if let group = item.group {
                InfoRow("Group") { Text(group) }
            }
        }
    }

    private var dangerSection: some View {
        VStack(spacing: 8) {
            if item.kind == .repository {
                Button {
                    store.togglePin(item.path)
                } label: {
                    Label(store.pinned.contains(item.path) ? "Unpin" : "Pin to Sidebar", systemImage: store.pinned.contains(item.path) ? "pin.slash" : "pin")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
            Button(role: .destructive) {
                store.requestTrash([item.id])
            } label: {
                Label(item.isMissing ? "Forget Worktree…" : "Move to Trash…", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            if item.kind == .repository, !store.pinned.contains(item.path) {
                Text("Pinned repositories are never suggested for cleanup.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: Multiple items

private struct MultiSelectionDetail: View {
    @Environment(GroveStore.self) private var store
    var items: [GroveItem]

    var body: some View {
        let bytes = store.totalBytes(items)
        let attention = items.filter(store.needsAttention)
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    ZStack {
                        ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { index, item in
                            IconTile(kind: item.kind, missing: item.isMissing, size: 48)
                                .rotationEffect(.degrees(Double(index - 1) * 8))
                                .offset(x: Double(index - 1) * 14)
                        }
                    }
                    .frame(height: 64)
                    Text("\(items.count) Items")
                        .font(.title2.weight(.semibold))
                    if let bytes {
                        Text(bytes.bytesLabel).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)

                if !attention.isEmpty {
                    Label("\(store.count(attention.count, "item")) \(attention.count == 1 ? "has" : "have") work that isn't saved anywhere else.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 10, style: .continuous))
                }

                InspectorSection("Selected") {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.leading, 40) }
                        HStack(spacing: 10) {
                            IconTile(kind: item.kind, missing: item.isMissing, size: 20)
                            Text(item.name).lineLimit(1)
                            Spacer()
                            Text(item.size?.bytesLabel ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                }
            }
            .padding(16)
        }
    }
}

// MARK: Building blocks

struct InspectorSection<Content: View>: View {
    var title: String
    var trailing: String?
    @ViewBuilder var content: Content

    init(_ title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                if let trailing { Text(trailing).foregroundStyle(.tertiary) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }
}

struct InfoRow<Value: View>: View {
    var label: String
    @ViewBuilder var value: Value

    init(_ label: String, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            value
                .multilineTextAlignment(.trailing)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}
