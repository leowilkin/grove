import SwiftUI

struct OverviewView: View {
    @Environment(GroveStore.self) private var store

    var body: some View {
        ScrollView {
            if store.items.isEmpty {
                ContentUnavailableView {
                    Label(store.phase == .scanning ? "Scanning \(store.rootDisplay)…" : "Nothing in \(store.rootDisplay)", systemImage: "leaf")
                } description: {
                    Text(store.phase == .scanning ? "Looking for repositories, worktrees and folders." : "Choose another folder in Settings.")
                }
                .frame(maxWidth: .infinity, minHeight: 480)
            } else {
                VStack(alignment: .leading, spacing: 28) {
                    StorageSummary()
                    StatTiles()
                    RecommendationList()
                    RecentlyActive()
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: 1040)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Overview")
    }
}

// MARK: Storage

private struct StorageSummary: View {
    @Environment(GroveStore.self) private var store

    private struct Segment: Identifiable {
        var id: String { label }
        var label: String
        var color: Color
        var count: Int
        var bytes: Int64
    }

    private var segments: [Segment] {
        let items = store.storageItems
        func make(_ label: String, _ color: Color, _ match: (GroveItem) -> Bool) -> Segment {
            let group = items.filter(match)
            return Segment(label: label, color: color, count: group.count, bytes: group.compactMap(\.size).reduce(0, +))
        }
        return [
            make("Active", .green) { $0.kind != .folder && store.activity($0) == .active },
            make("Idle", .blue) { $0.kind != .folder && store.activity($0) == .idle },
            make("Dormant", .orange) { $0.kind != .folder && [.dormant, .unknown].contains(store.activity($0)) },
            make("Not in git", .gray) { $0.kind == .folder },
        ]
    }

    var body: some View {
        let segments = segments
        let totalBytes = segments.reduce(0) { $0 + $1.bytes }
        let totalCount = segments.reduce(0) { $0 + $1.count }
        let useBytes = totalBytes > 0
        let total = Double(useBytes ? totalBytes : Int64(totalCount))

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.rootDisplay)
                        .font(.title2.weight(.semibold))
                    Text(totalBytes > 0
                         ? "\(store.visibleItems.count) items · \(totalBytes.bytesLabel) on disk"
                         : "\(store.visibleItems.count) items")
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer()
                if case .sizing(let done, let total) = store.phase {
                    HStack(spacing: 6) {
                        ProgressView(value: Double(done), total: Double(max(total, 1)))
                            .progressViewStyle(.circular)
                            .controlSize(.mini)
                        Text("Measuring sizes")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(segments.filter { (useBytes ? Double($0.bytes) : Double($0.count)) > 0 }) { segment in
                        let value = useBytes ? Double(segment.bytes) : Double(segment.count)
                        Rectangle()
                            .fill(segment.color.gradient)
                            .frame(width: max(3, (geo.size.width - 6) * value / max(total, 1)))
                            .help("\(segment.label): \(segment.count) items\(useBytes ? ", \(segment.bytes.bytesLabel)" : "")")
                    }
                }
            }
            .frame(height: 22)
            .clipShape(.rect(cornerRadius: 6, style: .continuous))
            .animation(.smooth, value: totalBytes)

            HStack(spacing: 22) {
                ForEach(segments) { segment in
                    HStack(spacing: 6) {
                        Circle().fill(segment.color.gradient).frame(width: 8, height: 8)
                        Text(segment.label).fontWeight(.medium)
                        Text(useBytes ? segment.bytes.bytesLabel : "\(segment.count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Spacer()
            }
            .font(.callout)
        }
        .card(padding: 20)
    }
}

// MARK: Stats

private struct StatTiles: View {
    @Environment(GroveStore.self) private var store

    var body: some View {
        HStack(spacing: 14) {
            tile(.repositories, "shippingbox.fill", .blue, "Repositories")
            tile(.worktrees, "arrow.triangle.branch", .green, "Worktrees")
            tile(.attention, "exclamationmark.circle.fill", .orange, "Need attention")
            tile(.cleanup, "leaf.fill", .mint, "Ready to remove")
        }
    }

    private func tile(_ filter: SidebarItem, _ symbol: String, _ tint: Color, _ label: String) -> some View {
        Button {
            store.show(filter)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                IconTile(symbol: symbol, tint: tint, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(store.items(for: filter).count)")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(label)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}

// MARK: Recommendations

private struct RecommendationList: View {
    @Environment(GroveStore.self) private var store

    var body: some View {
        let recommendations = store.recommendations
        VStack(alignment: .leading, spacing: 10) {
            Text("Recommendations")
                .font(.title3.weight(.semibold))

            if recommendations.isEmpty {
                HStack(spacing: 12) {
                    IconTile(symbol: "checkmark", tint: .green, size: 32)
                    VStack(alignment: .leading) {
                        Text("Your grove is tidy").fontWeight(.semibold)
                        Text("Nothing needs cleaning up right now.").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .card(padding: 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recommendations.enumerated()), id: \.element.id) { index, rec in
                        if index > 0 { Divider().padding(.leading, 62) }
                        RecommendationRow(recommendation: rec)
                    }
                }
                .card()
            }
        }
    }
}

private struct RecommendationRow: View {
    @Environment(GroveStore.self) private var store
    var recommendation: Recommendation

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            IconTile(symbol: recommendation.symbol, tint: recommendation.tint, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(recommendation.title).fontWeight(.semibold)
                Text(recommendation.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            if let bytes = recommendation.bytes, bytes > 0 {
                Text(bytes.bytesLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 64, alignment: .trailing)
            }
            Button {
                store.perform(recommendation)
            } label: {
                Text(recommendation.actionTitle).frame(minWidth: 64)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

// MARK: Recently active

private struct RecentlyActive: View {
    @Environment(GroveStore.self) private var store

    var body: some View {
        let recent = store.items
            .filter { $0.kind != .folder && !$0.isMissing && store.activity($0) == .active }
            .sorted { ($0.ownActivity ?? .distantPast) > ($1.ownActivity ?? .distantPast) }
            .prefix(8)

        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recently Active").font(.title3.weight(.semibold))
                    Spacer()
                    Button("Show All") { store.show(.active) }
                        .buttonStyle(.link)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(Array(recent)) { item in
                        RecentCard(item: item)
                    }
                }
            }
        }
    }
}

private struct RecentCard: View {
    @Environment(GroveStore.self) private var store
    var item: GroveItem
    @State private var hovering = false

    var body: some View {
        Button {
            store.show(.all, select: item.path)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    IconTile(kind: item.kind, size: 22)
                    Text(item.name)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                if let branch = item.branchLabel {
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack {
                    StatusPills(item: item, limit: 2)
                        .font(.caption)
                    Spacer(minLength: 4)
                    Text((item.ownActivity ?? .distantPast).relativeLabel)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .scaleEffect(hovering ? 1.01 : 1)
            .animation(.smooth(duration: 0.15), value: hovering)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
    }
}
