import SwiftUI

struct SidebarView: View {
    @Environment(GroveStore.self) private var store

    var body: some View {
        @Bindable var store = store

        List(selection: $store.sidebar) {
            Section {
                row(.overview, count: nil)
                row(.all)
            }

            Section("Library") {
                row(.repositories)
                row(.worktrees)
                row(.folders)
            }

            Section("Smart Filters") {
                row(.attention)
                row(.active)
                row(.dormant)
                row(.cleanup)
            }

            if !pinnedRepos.isEmpty {
                Section("Pinned") {
                    ForEach(pinnedRepos) { repo in
                        Label {
                            Text(repo.name)
                        } icon: {
                            IconTile(kind: repo.kind, size: 18)
                        }
                        .badge(store.worktrees(of: repo).count)
                        .tag(SidebarItem.project(repo.path))
                        .contextMenu {
                            Button("Unpin") { store.togglePin(repo.path) }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { footer }
    }

    private var pinnedRepos: [GroveItem] {
        store.items
            .filter { store.pinned.contains($0.path) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @ViewBuilder
    private func row(_ item: SidebarItem, count: Int? = -1) -> some View {
        let n = count == -1 ? store.items(for: item, searching: false).count : count
        Label {
            Text(item.title)
        } icon: {
            if let tint = item.tint {
                Image(systemName: item.symbol).foregroundStyle(tint)
            } else {
                Image(systemName: item.symbol)
            }
        }
        .badge(n ?? 0)
        .tag(item)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(store.rootDisplay)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let date = store.lastScanned, store.phase == .idle {
                Text(date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
