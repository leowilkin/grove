import Foundation
import Testing
@testable import Grove

/// End-to-end checks against real git repositories built by `scripts/make-fixtures.sh`.
/// Removals go to the Trash and are undone at the end of each test, so nothing is left behind.
@MainActor
@Suite(.serialized)
final class GroveTests {
    let base: String
    let root: String
    let store: GroveStore

    init() async throws {
        base = FileManager.default.temporaryDirectory.appending(path: "grove-tests-\(UUID().uuidString)").path
        AppSupport.directory = URL(fileURLWithPath: base).appending(path: "support", directoryHint: .isDirectory)
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "scripts/make-fixtures.sh").path
        let result = await Shell.run("/bin/bash", [script, base], timeout: 120)
        try #require(result.ok, "fixture script failed: \(result.stderr)")
        root = Scanner.normalize(base + "/code")
        store = GroveStore(rootPath: root)
        await store.scan()
    }

    isolated deinit {
        try? FileManager.default.removeItem(atPath: base)
    }

    private func item(_ name: String) throws -> GroveItem {
        try #require(store.items.first { $0.name == name }, "no item named \(name)")
    }

    private func git(_ path: String, _ args: String...) async -> ShellResult {
        await Git.run(path, args)
    }

    private func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func undo(_ undoManager: UndoManager) async {
        undoManager.undo()
        // The undo handler hops to a task; give it a moment to start.
        try? await Task.sleep(for: .milliseconds(100))
    }

    private func undoManager() -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        store.undoManager = manager
        return manager
    }

    // MARK: Scanning

    @Test func classifiesEveryKindOfCheckout() throws {
        #expect(store.items.filter { $0.kind == .repository }.count == 8)
        #expect(store.items.filter { $0.kind == .worktree }.count == 6)
        #expect(store.items.filter { $0.kind == .folder }.count == 2)

        let login = try item("nebula-api-login")
        #expect(login.parentPath == root + "/nebula-api")
        #expect(login.git?.isMerged == true)
        #expect(store.cleanupReason(login) == .merged)

        let pagination = try item("nebula-api-pagination")
        #expect(pagination.git?.upstreamGone == true)
        #expect(store.cleanupReason(pagination) == .remoteDeleted)

        let search = try item("nebula-api-search")
        #expect(search.uncommitted == 1)
        #expect(store.needsAttention(search))
        #expect(store.cleanupReason(search) == nil)

        let missing = try item("nebula-api-experiment")
        #expect(missing.isMissing)
        #expect(missing.isInsideRoot)
        #expect(missing.adminDir != nil)

        let nested = try item("review-pr-42")
        #expect(nested.isNestedInParent)

        let external = try item("nebula-cache-spike")
        #expect(!external.isInsideRoot)

        #expect(try item("acme-portal").group == "clients")
        #expect(store.cleanupReason(try item("pixel-garden")) == .dormantRepository)
        #expect(store.cleanupReason(try item("retro-weather")) == .dormantRepository)
        #expect(store.cleanupReason(try item("ledger-cli")) == nil, "has an unpushed commit")
        #expect(try item("ledger-cli").git?.unpushed == 1)
        #expect(try item("recipe-notes").git?.remoteURL == nil)
    }

    @Test func repeatedScansAgree() async throws {
        let first = store.items.map { "\($0.path) \($0.git?.branch ?? "-") \($0.uncommitted) \($0.unpushed)" }.sorted()
        await store.scan()
        let second = store.items.map { "\($0.path) \($0.git?.branch ?? "-") \($0.uncommitted) \($0.unpushed)" }.sorted()
        #expect(first == second)
    }

    // MARK: Removing

    @Test func trashingAWorktreeCanBeUndone() async throws {
        let undoManager = undoManager()
        let login = try item("nebula-api-login")
        let admin = try #require(login.adminDir)

        let plan = store.makeTrashPlan([login.path])
        #expect(plan.folders == [login.path])
        #expect(plan.admins == [admin])
        #expect(plan.warningCount == 0)

        undoManager.beginUndoGrouping()
        await store.performTrash(plan)
        undoManager.endUndoGrouping()

        #expect(!FileManager.default.fileExists(atPath: login.path))
        #expect(!FileManager.default.fileExists(atPath: admin))
        #expect(!(await git(root + "/nebula-api", "worktree", "list")).stdout.contains("nebula-api-login"))

        await undo(undoManager)
        await waitFor { FileManager.default.fileExists(atPath: login.path) && FileManager.default.fileExists(atPath: admin) }

        #expect(FileManager.default.fileExists(atPath: login.path))
        #expect((await git(root + "/nebula-api", "worktree", "list")).stdout.contains("nebula-api-login"))
        #expect((await git(login.path, "status", "--porcelain")).ok)
    }

    @Test func trashingARepositoryTakesItsWorktreesAndCanBeUndone() async throws {
        let undoManager = undoManager()
        let repo = try item("nebula-api")
        let plan = store.makeTrashPlan([repo.path])

        let names = Set(plan.entries.map(\.item.name))
        #expect(names == ["nebula-api", "nebula-api-login", "nebula-api-search", "nebula-api-pagination",
                          "nebula-cache-spike", "nebula-api-experiment", "review-pr-42"])
        // The nested worktree goes along inside the repository folder; nothing to park separately.
        #expect(!plan.folders.contains { $0.hasSuffix("review-pr-42") })
        #expect(plan.admins.isEmpty)
        #expect(plan.warningCount > 0, "the search worktree has uncommitted work")

        undoManager.beginUndoGrouping()
        await store.performTrash(plan)
        undoManager.endUndoGrouping()
        for folder in plan.folders {
            #expect(!FileManager.default.fileExists(atPath: folder))
        }

        await undo(undoManager)
        await waitFor { plan.folders.allSatisfy { FileManager.default.fileExists(atPath: $0) } }
        for folder in plan.folders {
            #expect(FileManager.default.fileExists(atPath: folder))
        }
        #expect((await git(root + "/nebula-api-search", "status", "--porcelain")).stdout.contains("draft.md"))

        // The restored items come back into the list once the follow-up scan finishes.
        await waitFor { store.phase == .idle && store.items.contains { $0.name == "nebula-api-search" } }
        #expect(store.items.contains { $0.name == "nebula-api-search" })
        #expect(store.items.count == 16)
    }

    @Test func forgettingAMissingWorktreeCanBeUndone() async throws {
        let undoManager = undoManager()
        let missing = try item("nebula-api-experiment")
        let plan = store.makeTrashPlan([missing.path])
        #expect(plan.onlyForgetsMissing)
        #expect(plan.folders.isEmpty)

        undoManager.beginUndoGrouping()
        await store.performTrash(plan)
        undoManager.endUndoGrouping()
        #expect(!(await git(root + "/nebula-api", "worktree", "list")).stdout.contains("experiment"))
        // The branch is free again once git forgets the worktree.
        #expect((await git(root + "/nebula-api", "branch", "--format=%(worktreepath)", "--list", "old/experiment")).trimmed.isEmpty)

        await undo(undoManager)
        await waitFor { FileManager.default.fileExists(atPath: missing.adminDir ?? "") }
        #expect((await git(root + "/nebula-api", "worktree", "list")).stdout.contains("experiment"))
    }

    // MARK: Branches

    @Test func deletingStaleBranchesCanBeUndone() async throws {
        let undoManager = undoManager()
        let repo = try item("nebula-api")
        let plan = store.makeBranchPlan(scope: [repo.path])
        let names = Set(plan.groups.flatMap(\.branches).map(\.name))
        #expect(names == ["chore/deps", "docs/readme", "fix/typo"], "checked-out branches stay out of the list")

        let before = (await git(repo.path, "rev-parse", "docs/readme")).trimmed
        undoManager.beginUndoGrouping()
        await store.deleteBranches([repo.path: names], from: plan)
        undoManager.endUndoGrouping()
        #expect(!(await git(repo.path, "rev-parse", "--verify", "--quiet", "docs/readme")).ok)

        await undo(undoManager)
        try? await Task.sleep(for: .milliseconds(500))
        #expect((await git(repo.path, "rev-parse", "docs/readme")).trimmed == before)
    }

    @Test func fetchAllUpdatesEveryRemote() async throws {
        store.fetchAll()
        await waitFor { store.toast != nil }
        #expect(store.toast?.message == "Fetched 5 repositories")
        await waitFor { store.phase == .idle }
        #expect(try item("nebula-api-pagination").git?.upstreamGone == true)
    }

    // MARK: Remotes

    @Test func remoteURLsBecomeBrowsableLinks() {
        #expect(RemoteURL.web("git@github.com:fern/moss.git")?.absoluteString == "https://github.com/fern/moss")
        #expect(RemoteURL.web("https://github.com/fern/moss.git")?.absoluteString == "https://github.com/fern/moss")
        #expect(RemoteURL.web("ssh://git@gitlab.com/fern/moss.git")?.absoluteString == "https://gitlab.com/fern/moss")
        #expect(RemoteURL.short("git@github.com:fern/moss.git") == "fern/moss")
        #expect(RemoteURL.short("/srv/git/moss.git") == "moss.git (local)")
    }
}
