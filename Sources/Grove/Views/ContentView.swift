import SwiftUI

struct ContentView: View {
    @Environment(GroveStore.self) private var store
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        @Bindable var store = store

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            switch store.sidebar ?? .overview {
            case .overview where store.searchText.isEmpty:
                OverviewView()
            case let filter:
                ItemListView(filter: filter == .overview ? .all : filter)
                    .id(filter)
            }
        }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "Search repositories, branches")
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        // Sheets get the store explicitly: while a sheet animates closed, SwiftUI can
        // re-render it detached from this view's environment.
        .sheet(item: $store.trashPlan) { plan in
            TrashSheet(plan: plan).environment(store)
        }
        .sheet(item: $store.branchPlan) { plan in
            BranchCleanupSheet(plan: plan).environment(store)
        }
        .alert("Something went wrong", isPresented: .init(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(6))
                        withAnimation(.smooth) { if store.toast?.id == toast.id { store.toast = nil } }
                    }
            }
        }
        .animation(.smooth(duration: 0.3), value: store.toast)
        .onAppear {
            store.undoManager = undoManager
            store.refresh()
        }
        .onChange(of: undoManager) { store.undoManager = undoManager }
    }

    private var subtitle: String {
        switch store.phase {
        case .scanning:
            return "Scanning \(store.rootDisplay)…"
        case .fetching(let done, let total):
            return "Fetching \(done) of \(total)…"
        case .sizing(let done, let total):
            return "Measuring sizes \(done) of \(total)…"
        case .idle:
            let n = store.visibleItems.count
            return "\(n) items in \(store.rootDisplay)"
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if store.phase != .idle {
                ProgressView().controlSize(.small)
            }
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                store.fetchAll()
            } label: {
                Label("Fetch All", systemImage: "arrow.down.circle")
            }
            .help("Fetch every repository's remotes (⌥⌘R)")
            .disabled(store.isBusy)

            Button {
                store.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Rescan \(store.rootDisplay) (⌘R)")
            .disabled(store.isBusy)
        }
    }
}

struct ToastView: View {
    @Environment(GroveStore.self) private var store
    var toast: Toast

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .imageScale(.large)
            Text(toast.message)
                .font(.callout.weight(.medium))
            if toast.canUndo {
                Button("Undo") { store.undo() }
                    .buttonStyle(.borderless)
                    .fontWeight(.semibold)
                    .keyboardShortcut("z", modifiers: .command)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, toast.canUndo ? 16 : 18)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}
