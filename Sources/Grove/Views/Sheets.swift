import SwiftUI

struct TrashSheet: View {
    @Environment(GroveStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var plan: TrashPlan

    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                IconTile(symbol: plan.onlyForgetsMissing ? "questionmark.folder.fill" : "trash.fill",
                         tint: plan.onlyForgetsMissing ? .gray : .red, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title3.weight(.semibold))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)

            if plan.warningCount > 0 {
                Label {
                    Text("\(store.count(plan.warningCount, "item")) \(plan.warningCount == 1 ? "has" : "have") work that may not exist anywhere else. Check the notes below before continuing.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.callout)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.orange.opacity(0.1), in: .rect(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

            List {
                ForEach(plan.entries) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        IconTile(kind: entry.item.kind, missing: entry.item.isMissing, size: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entry.item.name).fontWeight(.medium)
                                if let note = entry.note {
                                    Text(note).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let size = entry.item.size, plan.folders.contains(entry.item.path) {
                                    Text(size.bytesLabel).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                            Text(entry.item.displayPath)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            ForEach(entry.warnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
            .frame(height: listHeight)
            .padding(.horizontal, 20)

            HStack {
                if !plan.onlyForgetsMissing {
                    Text("Undo with ⌘Z, or use Put Back in the Trash.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(role: .destructive) {
                    working = true
                    Task { await store.performTrash(plan) }
                } label: {
                    Text(plan.onlyForgetsMissing ? "Forget" : "Move to Trash")
                        .frame(minWidth: 100)
                }
                .keyboardShortcut(plan.warningCount == 0 ? .defaultAction : nil)
                .buttonStyle(.borderedProminent)
                .tint(plan.onlyForgetsMissing ? .accentColor : .red)
                .disabled(working)
            }
            .padding(20)
        }
        .frame(width: 560)
    }

    private var listHeight: CGFloat {
        let rows = plan.entries.reduce(CGFloat(0)) { $0 + 50 + CGFloat($1.warnings.count) * 17 }
        return min(340, rows + 8)
    }

    private var title: String {
        let n = plan.entries.count
        if plan.onlyForgetsMissing { return "Forget \(store.count(n, "missing worktree"))?" }
        return n == 1 ? "Move “\(plan.entries[0].item.name)” to the Trash?" : "Move \(n) items to the Trash?"
    }

    private var subtitle: String {
        if plan.onlyForgetsMissing {
            return "Their folders are already gone. Grove clears git's records of them so their branches can be checked out again."
        }
        var text = plan.bytes > 0 ? "This frees \(plan.bytes.bytesLabel) once you empty the Trash." : "You can put everything back from the Trash."
        if plan.entries.contains(where: { $0.note != nil }) {
            text += " Worktrees of a removed repository go with it, since they can't work without it."
        }
        return text
    }
}

struct BranchCleanupSheet: View {
    @Environment(GroveStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var plan: BranchPlan

    @State private var chosen: [String: Set<String>] = [:]
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                IconTile(symbol: "scissors", tint: .purple, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Clean Up Branches").font(.title3.weight(.semibold))
                    Text("These local branches are merged into the default branch, or track a remote branch that was deleted — usually after its pull request was merged. Branches checked out in a worktree aren't listed.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)

            if plan.groups.isEmpty {
                ContentUnavailableView("No Stale Branches", systemImage: "checkmark.circle", description: Text("Every local branch is still in use."))
                    .frame(height: 200)
            } else {
                List {
                    ForEach(plan.groups) { group in
                        Section {
                            ForEach(group.branches) { branch in
                                Toggle(isOn: binding(group.id, branch.name)) {
                                    HStack(spacing: 8) {
                                        Text(branch.name)
                                            .font(.callout.monospaced())
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer()
                                        if branch.upstreamGone {
                                            Pill(text: "Remote deleted", symbol: nil, tint: .purple)
                                        } else {
                                            Pill(text: "Merged", symbol: nil, tint: .green)
                                        }
                                        Text(branch.date?.relativeLabel ?? "")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 90, alignment: .trailing)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        } header: {
                            HStack {
                                IconTile(kind: .repository, size: 16)
                                Text(group.repository.name)
                                Spacer()
                                Button(allChosen(group) ? "Deselect All" : "Select All") {
                                    chosen[group.id] = allChosen(group) ? [] : Set(group.branches.map(\.name))
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                            }
                        }
                    }
                }
                .listStyle(.bordered)
                .frame(minHeight: 200, maxHeight: 400)
                .padding(.horizontal, 20)
            }

            HStack {
                Text("Undo with ⌘Z. Each branch's last commit is kept so it can be restored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(role: .destructive) {
                    working = true
                    Task { await store.deleteBranches(chosen, from: plan) }
                } label: {
                    Text(total == 0 ? "Delete" : "Delete \(store.count(total, "Branch"))")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(total == 0 || working)
            }
            .padding(20)
        }
        .frame(width: 600)
        .onAppear {
            chosen = Dictionary(uniqueKeysWithValues: plan.groups.map { ($0.id, Set($0.branches.map(\.name))) })
        }
    }

    private var total: Int { chosen.values.reduce(0) { $0 + $1.count } }

    private func allChosen(_ group: BranchPlan.Group) -> Bool {
        (chosen[group.id]?.count ?? 0) == group.branches.count
    }

    private func binding(_ repo: String, _ branch: String) -> Binding<Bool> {
        Binding(
            get: { chosen[repo]?.contains(branch) ?? false },
            set: { on in
                var set = chosen[repo] ?? []
                if on { set.insert(branch) } else { set.remove(branch) }
                chosen[repo] = set
            }
        )
    }
}
