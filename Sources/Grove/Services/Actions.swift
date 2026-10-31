import AppKit

/// Where Grove keeps its cache and set-aside worktree metadata. Each store carries its own
/// copy, so tests can point theirs at a temporary folder.
struct SupportFolder: Sendable {
    var url: URL

    static let standard = SupportFolder(url: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "Grove", directoryHint: .isDirectory))

    var parkingLot: URL { url.appending(path: "Removed Worktree Metadata", directoryHint: .isDirectory) }

    func cacheFile(for root: String) -> URL {
        url.appending(path: "Cache/\(root.replacingOccurrences(of: "/", with: "_")).json")
    }
}

/// What happened during a removal, kept so it can be undone.
struct RemovalRecord: Sendable {
    /// Original path → where it landed in the Trash.
    var trashed: [String: String]
    /// Original worktree admin folder → where Grove parked it.
    var parkedAdmins: [String: String]
    var parkingBatch: String?
    var repositoriesToRepair: [String]
}

struct BranchRef: Sendable, Hashable {
    var name: String
    var sha: String
}

struct BranchDeletion: Sendable {
    var repository: String
    var branches: [BranchRef]
}

enum Actions {
    /// Worktree metadata goes to the support folder's parking lot rather than being deleted.
    /// It's restored on undo; otherwise this is equivalent to `git worktree prune`.
    @MainActor
    static func remove(folders: [String], admins: [String], repair: [String], support: SupportFolder) async throws -> RemovalRecord {
        var record = RemovalRecord(trashed: [:], parkedAdmins: [:], parkingBatch: nil, repositoriesToRepair: repair)

        if !folders.isEmpty {
            let urls = folders.map { URL(fileURLWithPath: $0) }
            let result = try await NSWorkspace.shared.recycle(urls)
            for (original, trashed) in result {
                record.trashed[original.path] = trashed.path
            }
        }

        let fm = FileManager.default
        let batch = support.parkingLot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        for admin in admins where fm.fileExists(atPath: admin) && isWorktreeMetadata(admin) {
            let holder = batch.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try fm.createDirectory(at: holder, withIntermediateDirectories: true)
            let destination = holder.appending(path: (admin as NSString).lastPathComponent)
            try fm.moveItem(atPath: admin, toPath: destination.path)
            record.parkedAdmins[admin] = destination.path
            record.parkingBatch = batch.path
        }
        return record
    }

    /// True only for `<repo>/.git/worktrees/<id>` folders that look like git made them.
    static func isWorktreeMetadata(_ path: String) -> Bool {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: Scanner.normalize(path))
        let worktrees = url.deletingLastPathComponent()
        let gitDir = worktrees.deletingLastPathComponent()
        return worktrees.lastPathComponent == "worktrees"
            && fm.fileExists(atPath: gitDir.appending(path: "HEAD").path)
            && fm.fileExists(atPath: gitDir.appending(path: "objects").path)
            && fm.fileExists(atPath: url.appending(path: "gitdir").path)
            && fm.fileExists(atPath: url.appending(path: "HEAD").path)
    }

    @concurrent
    static func restore(_ record: RemovalRecord) async -> [String] {
        let fm = FileManager.default
        var failures: [String] = []
        for (original, parked) in record.parkedAdmins {
            do { try fm.moveItem(atPath: parked, toPath: original) } catch { failures.append(original) }
        }
        for (original, trashed) in record.trashed {
            do { try fm.moveItem(atPath: trashed, toPath: original) } catch { failures.append(original) }
        }
        for repo in record.repositoriesToRepair where fm.fileExists(atPath: repo) {
            _ = await Git.run(repo, ["worktree", "repair"])
        }
        if failures.isEmpty, let batch = record.parkingBatch {
            try? fm.removeItem(atPath: batch)
        }
        return failures
    }

    /// Deletes branches and returns the ones that actually went, with their tips for undo.
    @concurrent
    static func deleteBranches(_ request: BranchDeletion) async -> BranchDeletion {
        var deleted: [BranchRef] = []
        for branch in request.branches {
            let result = await Git.run(request.repository, ["branch", "-D", branch.name])
            if result.ok { deleted.append(branch) }
        }
        return BranchDeletion(repository: request.repository, branches: deleted)
    }

    @concurrent
    static func restoreBranches(_ request: BranchDeletion) async {
        for branch in request.branches {
            _ = await Git.run(request.repository, ["branch", branch.name, branch.sha])
        }
    }

    /// Drops parked metadata older than a week; by then it's just what `git worktree prune` would have removed.
    @concurrent
    static func sweepParkingLot(_ support: SupportFolder = .standard) async {
        let fm = FileManager.default
        guard let batches = try? fm.contentsOfDirectory(at: support.parkingLot, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        for batch in batches {
            let created = (try? batch.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if created < cutoff { try? fm.removeItem(at: batch) }
        }
    }
}

enum Cache {
    static func load(root: String, from support: SupportFolder) -> [GroveItem] {
        guard let data = try? Data(contentsOf: support.cacheFile(for: root)) else { return [] }
        return (try? JSONDecoder().decode([GroveItem].self, from: data)) ?? []
    }

    static func save(_ items: [GroveItem], root: String, to support: SupportFolder) {
        let url = support.cacheFile(for: root)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
