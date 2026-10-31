import SwiftUI
import Observation

enum SidebarItem: Hashable {
    case overview
    case all
    case repositories
    case worktrees
    case folders
    case attention
    case active
    case dormant
    case cleanup
    case finishedWorktrees
    case dormantRepositories
    case project(String)

    var title: String {
        switch self {
        case .overview: "Overview"
        case .all: "All Items"
        case .repositories: "Repositories"
        case .worktrees: "Worktrees"
        case .folders: "Other Folders"
        case .attention: "Needs Attention"
        case .active: "Recently Active"
        case .dormant: "Dormant"
        case .cleanup: "Ready to Remove"
        case .finishedWorktrees: "Finished Worktrees"
        case .dormantRepositories: "Dormant Repositories"
        case .project(let path): (path as NSString).lastPathComponent
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .all: "tray.full"
        case .repositories: "shippingbox"
        case .worktrees: "arrow.triangle.branch"
        case .folders: "folder"
        case .attention: "exclamationmark.circle"
        case .active: "bolt"
        case .dormant: "moon.zzz"
        case .cleanup: "leaf"
        case .finishedWorktrees: "checkmark.circle"
        case .dormantRepositories: "moon.zzz"
        case .project: "pin"
        }
    }

    var tint: Color? {
        switch self {
        case .attention: .orange
        case .active: .green
        case .dormant: .indigo
        case .cleanup: .mint
        default: nil
        }
    }

    var emptyMessage: String {
        switch self {
        case .attention: "Nothing has uncommitted changes or unpushed commits."
        case .cleanup, .finishedWorktrees, .dormantRepositories: "Nothing here looks safe to remove right now."
        case .dormant: "Everything has been touched recently."
        case .active: "Nothing has been touched recently."
        case .folders: "Every folder is a git repository."
        default: "Nothing matches."
        }
    }
}

enum Activity {
    case active, idle, dormant, unknown

    var label: String {
        switch self {
        case .active: "Active"
        case .idle: "Idle"
        case .dormant: "Dormant"
        case .unknown: "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .active: .green
        case .idle: .blue
        case .dormant: .orange
        case .unknown: .gray
        }
    }
}

enum CleanupReason {
    case missing, merged, remoteDeleted, idleWorktree, dormantRepository

    var label: String {
        switch self {
        case .missing: "Folder is already gone"
        case .merged: "Branch is merged"
        case .remoteDeleted: "Remote branch was deleted"
        case .idleWorktree: "Idle, and everything is pushed"
        case .dormantRepository: "Dormant, and everything is pushed"
        }
    }
}

enum Phase: Equatable {
    case idle
    case scanning
    case sizing(done: Int, total: Int)
    case fetching(done: Int, total: Int)
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var canUndo: Bool
}

struct TrashPlan: Identifiable {
    struct Entry: Identifiable {
        var id: String { item.path }
        var item: GroveItem
        var note: String?
        var warnings: [String]
    }

    let id = UUID()
    var entries: [Entry]
    var folders: [String]
    var admins: [String]
    var repair: [String]
    var bytes: Int64

    var onlyForgetsMissing: Bool { entries.allSatisfy(\.item.isMissing) }
    var warningCount: Int { entries.filter { !$0.warnings.isEmpty }.count }
}

struct BranchPlan: Identifiable {
    struct Group: Identifiable {
        var id: String { repository.path }
        var repository: GroveItem
        var branches: [BranchInfo]
    }

    let id = UUID()
    var groups: [Group]
    var total: Int { groups.reduce(0) { $0 + $1.branches.count } }
}

struct Recommendation: Identifiable {
    enum Action {
        case show(SidebarItem)
        case cleanBranches
        case forgetMissing
    }

    var id: String
    var symbol: String
    var tint: Color
    var title: String
    var detail: String
    var bytes: Int64?
    var actionTitle: String
    var action: Action
}

@Observable
@MainActor
final class GroveStore {
    var items: [GroveItem] = []
    var phase: Phase = .idle
    var lastScanned: Date?
    var sidebar: SidebarItem? = .overview
    var selection: Set<String> = []
    var searchText = ""
    var showInspector = true
    var toast: Toast?
    var trashPlan: TrashPlan?
    var branchPlan: BranchPlan?
    var errorMessage: String?

    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var rescanRequested = false

    // MARK: Settings

    var rootPath: String {
        didSet {
            defaults.set(rootPath, forKey: "rootPath")
            items = Cache.load(root: rootPath)
            selection = []
            refresh()
        }
    }
    var activeDays: Int { didSet { defaults.set(activeDays, forKey: "activeDays") } }
    var dormantDays: Int { didSet { defaults.set(dormantDays, forKey: "dormantDays") } }
    var editorID: String? { didSet { defaults.set(editorID, forKey: "editorID") } }
    var terminalID: String? { didSet { defaults.set(terminalID, forKey: "terminalID") } }
    var showExternalWorktrees: Bool { didSet { defaults.set(showExternalWorktrees, forKey: "showExternalWorktrees") } }
    var pinned: Set<String> { didSet { defaults.set(Array(pinned).sorted(), forKey: "pinned") } }

    @ObservationIgnored private let defaults = UserDefaults.standard

    init(rootPath root: String? = nil) {
        let d = UserDefaults.standard
        let home = FileManager.default.homeDirectoryForCurrentUser
        rootPath = root ?? d.string(forKey: "rootPath") ?? home.appending(path: "Code").path
        activeDays = d.object(forKey: "activeDays") as? Int ?? 14
        dormantDays = d.object(forKey: "dormantDays") as? Int ?? 90
        editorID = d.string(forKey: "editorID") ?? Apps.defaultEditorID
        terminalID = d.string(forKey: "terminalID") ?? Apps.terminals.first?.bundleID
        showExternalWorktrees = d.object(forKey: "showExternalWorktrees") as? Bool ?? true
        pinned = Set(d.stringArray(forKey: "pinned") ?? [])
        items = Cache.load(root: rootPath)
        lastScanned = items.isEmpty ? nil : Date()
    }

    var rootDisplay: String { (rootPath as NSString).abbreviatingWithTildeInPath }
    var isBusy: Bool { phase == .scanning || { if case .fetching = phase { true } else { false } }() }
    var editor: ExternalApp? { Apps.app(editorID, in: Apps.editors) }
    var terminal: ExternalApp? { Apps.app(terminalID, in: Apps.terminals) }

    // MARK: Derived

    var visibleItems: [GroveItem] {
        showExternalWorktrees ? items : items.filter(\.isInsideRoot)
    }

    func item(at path: String) -> GroveItem? {
        items.first { $0.path == path }
    }

    var selectedItems: [GroveItem] {
        items.filter { selection.contains($0.id) }
    }

    func worktrees(of repo: GroveItem) -> [GroveItem] {
        items.filter { $0.parentPath == repo.path }
            .sorted { $0.activityKey > $1.activityKey }
    }

    func activity(_ item: GroveItem) -> Activity {
        guard let date = item.lastActivity else { return item.isMissing ? .dormant : .unknown }
        let days = Date().timeIntervalSince(date) / 86_400
        if days <= Double(activeDays) { return .active }
        if days > Double(dormantDays) { return .dormant }
        return .idle
    }

    func isPinned(_ item: GroveItem) -> Bool {
        pinned.contains(item.path) || item.parentPath.map(pinned.contains) == true
    }

    func needsAttention(_ item: GroveItem) -> Bool {
        guard let git = item.git, !item.isMissing else { return false }
        return item.uncommitted > 0 || (git.remoteURL != nil && git.unpushed > 0 && !git.upstreamGone)
    }

    func cleanupReason(_ item: GroveItem) -> CleanupReason? {
        if isPinned(item) { return nil }
        switch item.kind {
        case .worktree:
            if item.isMissing { return .missing }
            guard let git = item.git, item.uncommitted == 0, !item.isLocked else { return nil }
            if git.isMerged { return .merged }
            if git.upstreamGone { return .remoteDeleted }
            if git.remoteURL != nil, git.unpushed == 0, activity(item) != .active { return .idleWorktree }
            return nil
        case .repository:
            guard let git = item.git, activity(item) == .dormant, item.uncommitted == 0,
                  git.remoteURL != nil, git.unpushedAllBranches == 0, git.stashes == 0
            else { return nil }
            if worktrees(of: item).contains(where: { $0.uncommitted > 0 }) { return nil }
            return .dormantRepository
        case .folder:
            return nil
        }
    }

    func items(for filter: SidebarItem) -> [GroveItem] {
        var result = visibleItems
        switch filter {
        case .overview, .all:
            break
        case .repositories:
            result = result.filter { $0.kind == .repository }
        case .worktrees:
            result = result.filter { $0.kind == .worktree }
        case .folders:
            result = result.filter { $0.kind == .folder }
        case .attention:
            result = result.filter(needsAttention)
        case .active:
            result = result.filter { activity($0) == .active }
        case .dormant:
            result = result.filter { activity($0) == .dormant }
        case .cleanup:
            result = result.filter { cleanupReason($0) != nil }
        case .finishedWorktrees:
            result = result.filter {
                guard let reason = cleanupReason($0) else { return false }
                return [.merged, .remoteDeleted, .idleWorktree].contains(reason)
            }
        case .dormantRepositories:
            result = result.filter { cleanupReason($0) == .dormantRepository }
        case .project(let path):
            result = result.filter { $0.path == path || $0.parentPath == path }
        }
        return search(result)
    }

    private func search(_ list: [GroveItem]) -> [GroveItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return list }
        return list.filter { item in
            item.name.localizedCaseInsensitiveContains(query)
                || item.path.localizedCaseInsensitiveContains(query)
                || (item.git?.branch?.localizedCaseInsensitiveContains(query) ?? false)
                || (item.git?.remoteURL?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    /// Items that make up the root's disk usage, without counting nested worktrees twice.
    var storageItems: [GroveItem] {
        items.filter { $0.isInsideRoot && !$0.isNestedInParent && !$0.isMissing }
    }

    func deletableBranches(in repo: GroveItem) -> [BranchInfo] {
        guard let git = repo.git else { return [] }
        let defaultName = git.defaultBranchName
        return git.branches.filter { branch in
            (branch.upstreamGone || branch.isMerged)
                && branch.worktreePath == nil
                && branch.name != git.branch
                && branch.name != defaultName
        }
    }

    var recommendations: [Recommendation] {
        var list: [Recommendation] = []
        let finished = items(for: .finishedWorktrees)
        if !finished.isEmpty {
            let merged = finished.filter { [.merged, .remoteDeleted].contains(cleanupReason($0)) }.count
            list.append(Recommendation(
                id: "worktrees", symbol: "arrow.triangle.branch", tint: .green,
                title: "Remove finished worktrees",
                detail: "\(count(finished.count, "worktree")) with no uncommitted changes. \(merged) are on branches that were merged or deleted on the remote; the rest are idle with everything pushed.",
                bytes: totalBytes(finished), actionTitle: "Review", action: .show(.finishedWorktrees)
            ))
        }
        let dormantRepos = items(for: .dormantRepositories)
        if !dormantRepos.isEmpty {
            list.append(Recommendation(
                id: "repos", symbol: "moon.zzz.fill", tint: .indigo,
                title: "Clear out dormant repositories",
                detail: "\(count(dormantRepos.count, "repository")) untouched for over \(dormantDays) days, with every commit already on a remote. You can clone them again any time.",
                bytes: totalBytes(dormantRepos), actionTitle: "Review", action: .show(.dormantRepositories)
            ))
        }
        let branchCount = items.filter { $0.kind == .repository }.reduce(0) { $0 + deletableBranches(in: $1).count }
        if branchCount > 0 {
            list.append(Recommendation(
                id: "branches", symbol: "scissors", tint: .purple,
                title: "Prune stale branches",
                detail: "\(count(branchCount, "local branch")) already merged, or whose remote branch was deleted after its pull request closed.",
                bytes: nil, actionTitle: "Clean Up…", action: .cleanBranches
            ))
        }
        let missing = items.filter(\.isMissing)
        if !missing.isEmpty {
            list.append(Recommendation(
                id: "missing", symbol: "questionmark.folder.fill", tint: .red,
                title: "Forget missing worktrees",
                detail: "Git still tracks \(count(missing.count, "worktree")) whose folder was deleted. These block their branches from being checked out elsewhere.",
                bytes: nil, actionTitle: "Forget…", action: .forgetMissing
            ))
        }
        let attention = items(for: .attention)
        if !attention.isEmpty {
            list.append(Recommendation(
                id: "attention", symbol: "exclamationmark.circle.fill", tint: .orange,
                title: "Save work in progress",
                detail: "\(count(attention.count, "item")) with uncommitted changes or commits that aren't on any remote yet.",
                bytes: nil, actionTitle: "Show", action: .show(.attention)
            ))
        }
        let folders = items.filter { $0.kind == .folder }
        if !folders.isEmpty {
            list.append(Recommendation(
                id: "folders", symbol: "folder.fill", tint: .gray,
                title: "Sort out loose folders",
                detail: "\(count(folders.count, "folder")) in \(rootDisplay) aren't git repositories, so nothing backs them up.",
                bytes: totalBytes(folders), actionTitle: "Show", action: .show(.folders)
            ))
        }
        return list
    }

    func totalBytes(_ list: [GroveItem]) -> Int64? {
        let sized = list.filter { item in
            !item.isNestedInParent || !list.contains { $0.path == item.parentPath }
        }
        let sizes = sized.compactMap(\.size)
        return sizes.isEmpty ? nil : sizes.reduce(0, +)
    }

    func count(_ n: Int, _ noun: String) -> String {
        if n == 1 { return "1 \(noun)" }
        if noun.hasSuffix("y") { return "\(n) \(noun.dropLast())ies" }
        if noun.hasSuffix("ch") || noun.hasSuffix("sh") { return "\(n) \(noun)es" }
        return "\(n) \(noun)s"
    }

    // MARK: Navigation

    func show(_ filter: SidebarItem, select path: String? = nil) {
        sidebar = filter
        if let path {
            selection = [path]
            showInspector = true
        }
    }

    func perform(_ recommendation: Recommendation) {
        switch recommendation.action {
        case .show(let filter):
            searchText = ""
            show(filter)
        case .cleanBranches:
            branchPlan = makeBranchPlan(scope: nil)
        case .forgetMissing:
            trashPlan = makeTrashPlan(Set(items.filter(\.isMissing).map(\.path)))
        }
    }

    func togglePin(_ path: String) {
        if pinned.contains(path) { pinned.remove(path) } else { pinned.insert(path) }
    }

    // MARK: Opening

    func openInEditor(_ paths: [String]) { Apps.open(paths, with: editor) }
    func openInTerminal(_ paths: [String]) { Apps.open(paths, with: terminal) }
    func reveal(_ paths: [String]) { Apps.reveal(paths) }

    func browse(_ item: GroveItem) {
        guard var url = item.webURL else { return }
        if let branch = item.git?.branch, url.host() == "github.com", !(item.git?.isOnDefaultBranch ?? true), !(item.git?.upstreamGone ?? false), item.git?.upstream != nil {
            url = url.appending(path: "tree").appending(path: branch)
        }
        Apps.browse(url)
    }

    // MARK: Scanning

    func refresh() {
        // A refresh asked for mid-scan (say, by an undo) runs once the current scan ends,
        // so the result always reflects the latest change on disk.
        guard !isBusy else {
            rescanRequested = true
            return
        }
        scanTask?.cancel()
        scanTask = Task {
            repeat {
                rescanRequested = false
                await scan()
            } while rescanRequested && !Task.isCancelled
            if !Task.isCancelled { await computeSizes() }
        }
    }

    func fetchAll() {
        guard !isBusy else { return }
        scanTask?.cancel()
        scanTask = Task {
            let repos = items.filter { $0.kind == .repository && $0.hasRemote }.map(\.path)
            var done = 0
            var failures = 0
            phase = .fetching(done: 0, total: repos.count)
            await forEachConcurrently(repos, limit: 6, work: { await Git.fetch($0).ok }) { ok in
                done += 1
                if !ok { failures += 1 }
                self.phase = .fetching(done: done, total: repos.count)
            }
            phase = .idle
            await scan()
            toast = Toast(
                message: failures == 0
                    ? "Fetched \(count(repos.count, "repository"))"
                    : "Fetched \(repos.count - failures) of \(repos.count) · \(failures) couldn't be reached",
                canUndo: false
            )
            if !Task.isCancelled { await computeSizes() }
        }
    }

    func scan() async {
        phase = .scanning
        let root = rootPath
        let normalizedRoot = Scanner.normalize(root)
        let discovery = await Scanner.discover(root: root)
        let previous = Dictionary(items.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var results: [String: GroveItem] = [:]

        func carry(_ item: inout GroveItem) {
            if let old = previous[item.path] {
                item.size = old.size
                item.sizedAt = old.sizedAt
            }
        }

        // Repositories
        await forEachConcurrently(discovery.repositories, limit: 8, work: { entry in
            (entry, await Scanner.scanCheckout(path: entry.path, full: true))
        }) { entry, scan in
            var item = GroveItem(path: entry.path, name: (entry.path as NSString).lastPathComponent, kind: .repository, group: entry.group)
            item.git = scan.git
            item.ownActivity = scan.activity
            carry(&item)
            results[item.path] = item
        }

        // Worktrees: everything git knows about, plus worktree folders found in the root.
        struct Pending: Sendable {
            var path: String
            var group: String?
            var parent: String?
            var record: WorktreeRecord?
        }
        var pending: [String: Pending] = [:]
        for repo in results.values {
            for record in repo.git?.worktrees ?? [] {
                pending[record.path] = Pending(path: record.path, parent: repo.path, record: record)
            }
        }
        for entry in discovery.worktrees {
            var p = pending[entry.path] ?? Pending(path: entry.path)
            p.group = entry.group
            p.parent = p.parent ?? Scanner.parentRepository(ofWorktree: entry.path)
            pending[entry.path] = p
        }

        var toScan: [Pending] = []
        for p in pending.values {
            let exists = FileManager.default.fileExists(atPath: p.path)
            if p.record?.isPrunable == true || !exists {
                var item = GroveItem(path: p.path, name: (p.path as NSString).lastPathComponent, kind: .worktree, group: p.group, parentPath: p.parent)
                item.isMissing = true
                item.adminDir = p.record?.adminDir
                var git = GitInfo()
                git.branch = p.record?.branch
                git.headSHA = p.record?.head
                item.git = git
                results[item.path] = item
            } else {
                toScan.append(p)
            }
        }

        await forEachConcurrently(toScan, limit: 8, work: { p in
            (p, await Scanner.scanCheckout(path: p.path, full: false))
        }) { p, scan in
            var item = GroveItem(path: p.path, name: (p.path as NSString).lastPathComponent, kind: .worktree, group: p.group, parentPath: p.parent)
            item.git = scan.git
            item.ownActivity = scan.activity
            item.isLocked = p.record?.isLocked ?? false
            // Only metadata the parent repository itself lists; never wherever a `.git` file points.
            item.adminDir = p.record?.adminDir
            carry(&item)
            results[item.path] = item
        }

        // Plain folders
        await forEachConcurrently(discovery.folders, limit: 8, work: { entry in
            (entry, await Scanner.folderActivity(entry.path))
        }) { entry, date in
            var item = GroveItem(path: entry.path, name: (entry.path as NSString).lastPathComponent, kind: .folder)
            item.ownActivity = date
            carry(&item)
            results[item.path] = item
        }

        // A repository is as active as its busiest worktree.
        var latestByParent: [String: Date] = [:]
        for item in results.values where item.kind == .worktree {
            guard let parent = item.parentPath, let date = item.ownActivity else { continue }
            latestByParent[parent] = max(latestByParent[parent] ?? date, date)
        }
        for key in results.keys {
            guard var item = results[key] else { continue }
            item.lastActivity = [item.ownActivity, latestByParent[item.path]].compactMap { $0 }.max()
            item.isInsideRoot = item.path.hasPrefix(normalizedRoot + "/")
            if let parent = item.parentPath {
                item.isNestedInParent = item.path.hasPrefix(parent + "/")
            }
            results[key] = item
        }

        debugLog("scan finished: \(results.count) items")
        guard !Task.isCancelled else { phase = .idle; return }
        items = results.values.sorted { $0.activityKey > $1.activityKey }
        selection = selection.filter { results[$0] != nil }
        lastScanned = Date()
        phase = .idle
        Cache.save(items, root: root)
    }

    private func computeSizes() async {
        let cutoff = Date().addingTimeInterval(-30 * 60)
        let paths = items.filter { !$0.isMissing && ($0.sizedAt ?? .distantPast) < cutoff }.map(\.path)
        guard !paths.isEmpty else { return }
        var done = 0
        var buffer: [String: Int64] = [:]
        phase = .sizing(done: 0, total: paths.count)

        func flush() {
            let now = Date()
            for index in items.indices {
                if let size = buffer[items[index].path] {
                    items[index].size = size
                    items[index].sizedAt = now
                }
            }
            buffer = [:]
        }

        await forEachConcurrently(paths, limit: 4, work: { path in
            (path, await Scanner.diskSize(path))
        }) { path, size in
            done += 1
            if let size { buffer[path] = size }
            if buffer.count >= 6 { flush() }
            self.phase = .sizing(done: done, total: paths.count)
        }
        flush()
        if case .sizing = phase { phase = .idle }
        Cache.save(items, root: rootPath)
    }

    private func forEachConcurrently<T: Sendable, R: Sendable>(
        _ inputs: [T],
        limit: Int,
        work: @escaping @Sendable (T) async -> R,
        handle: (R) -> Void
    ) async {
        await withTaskGroup(of: R.self) { group in
            var iterator = inputs.makeIterator()
            for _ in 0..<limit {
                guard let next = iterator.next() else { break }
                group.addTask { await work(next) }
            }
            while let result = await group.next() {
                handle(result)
                if Task.isCancelled { continue }
                if let next = iterator.next() { group.addTask { await work(next) } }
            }
        }
    }

    // MARK: Removing

    func requestTrash(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        trashPlan = makeTrashPlan(ids)
    }

    func makeTrashPlan(_ ids: Set<String>) -> TrashPlan {
        var entries: [TrashPlan.Entry] = []
        var included = Set<String>()
        let chosen = items.filter { ids.contains($0.id) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        for item in chosen {
            entries.append(.init(item: item, note: nil, warnings: warnings(for: item)))
            included.insert(item.path)
        }
        // Removing a repository strands its linked worktrees, so they go with it.
        for repo in chosen where repo.kind == .repository {
            for worktree in worktrees(of: repo) where !included.contains(worktree.path) {
                let note = worktree.isNestedInParent ? "Inside \(repo.name)" : "Worktree of \(repo.name)"
                entries.append(.init(item: worktree, note: note, warnings: warnings(for: worktree)))
                included.insert(worktree.path)
            }
        }

        let existing = entries.filter { !$0.item.isMissing }.map(\.item.path)
        let folders = existing.filter { path in
            !existing.contains { other in other != path && path.hasPrefix(other + "/") }
        }
        let repositories = Set(items.filter { $0.kind == .repository }.map(\.path))
        let admins = entries.compactMap { entry -> String? in
            guard entry.item.kind == .worktree, let parent = entry.item.parentPath,
                  repositories.contains(parent), !included.contains(parent) else { return nil }
            return entry.item.adminDir
        }
        let repair = Set(entries.compactMap { entry -> String? in
            entry.item.kind == .repository ? entry.item.path : entry.item.parentPath
        })
        let bytes = entries.filter { folders.contains($0.item.path) }.compactMap(\.item.size).reduce(0, +)
        return TrashPlan(entries: entries, folders: folders, admins: admins, repair: Array(repair), bytes: bytes)
    }

    private func warnings(for item: GroveItem) -> [String] {
        var list: [String] = []
        if item.isMissing { return [] }
        guard let git = item.git else {
            return ["Not a git repository — this may be the only copy"]
        }
        if git.conflicts > 0 { list.append("Merge conflicts in progress") }
        if item.uncommitted > 0 { list.append(count(item.uncommitted, "uncommitted change")) }
        if git.remoteURL == nil {
            list.append("No remote — this is the only copy")
        } else if item.kind == .repository, git.unpushedAllBranches > 0 {
            list.append("\(count(git.unpushedAllBranches, "commit")) on local branches that aren't on any remote")
        } else if git.unpushed > 0 {
            list.append(git.upstreamGone
                ? "\(count(git.unpushed, "local commit")); its remote branch was deleted (often after a squash merge)"
                : "\(count(git.unpushed, "commit")) not pushed to any remote")
        }
        if git.stashes > 0, item.kind == .repository { list.append(count(git.stashes, "stash")) }
        if item.isLocked { list.append("Worktree is locked") }
        return list
    }

    func performTrash(_ plan: TrashPlan) async {
        trashPlan = nil
        do {
            let record = try await Actions.remove(folders: plan.folders, admins: plan.admins, repair: plan.repair)
            let removed = Set(plan.entries.map(\.item.path))
            items.removeAll { removed.contains($0.path) }
            selection.subtract(removed)
            Cache.save(items, root: rootPath)
            let n = plan.entries.count
            let message = plan.onlyForgetsMissing
                ? "Forgot \(count(n, "missing worktree"))"
                : "Moved \(count(n, "item")) to the Trash"
            registerUndo(plan.onlyForgetsMissing ? "Forget Worktrees" : "Move to Trash") { store in
                let failures = await Actions.restore(record)
                if !failures.isEmpty {
                    store.errorMessage = "Couldn't put back \(store.count(failures.count, "item")). They're still in the Trash."
                }
                store.toast = Toast(message: "Put back \(store.count(n, "item"))", canUndo: false)
                store.refresh()
            }
            toast = Toast(message: message, canUndo: true)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
            refresh()
        }
    }

    // MARK: Branches

    func makeBranchPlan(scope: [String]?) -> BranchPlan {
        let repos = items.filter { $0.kind == .repository && (scope?.contains($0.path) ?? true) }
        let groups = repos.compactMap { repo -> BranchPlan.Group? in
            let branches = deletableBranches(in: repo).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            return branches.isEmpty ? nil : .init(repository: repo, branches: branches)
        }
        .sorted { $0.repository.name.localizedStandardCompare($1.repository.name) == .orderedAscending }
        return BranchPlan(groups: groups)
    }

    func deleteBranches(_ chosen: [String: Set<String>], from plan: BranchPlan) async {
        branchPlan = nil
        var requests: [BranchDeletion] = []
        for group in plan.groups {
            let names = chosen[group.id] ?? []
            let refs = group.branches.filter { names.contains($0.name) }.map { BranchRef(name: $0.name, sha: $0.sha) }
            if !refs.isEmpty { requests.append(BranchDeletion(repository: group.id, branches: refs)) }
        }
        var deleted: [BranchDeletion] = []
        for request in requests {
            deleted.append(await Actions.deleteBranches(request))
        }
        let total = deleted.reduce(0) { $0 + $1.branches.count }
        registerUndo("Delete Branches") { store in
            for deletion in deleted { await Actions.restoreBranches(deletion) }
            store.toast = Toast(message: "Restored \(store.count(total, "branch"))", canUndo: false)
            store.refresh()
        }
        toast = Toast(message: "Deleted \(count(total, "branch"))", canUndo: true)
        refresh()
    }

    // MARK: Undo

    private func registerUndo(_ name: String, _ action: @escaping @MainActor @Sendable (GroveStore) async -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { store in
            Task { @MainActor in await action(store) }
        }
        undoManager.setActionName(name)
    }

    func undo() {
        undoManager?.undo()
        toast = nil
    }
}
