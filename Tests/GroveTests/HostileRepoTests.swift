import Foundation
import Testing
@testable import Grove

/// Grove runs git in every folder it finds, so a folder's own `.git` contents must never be
/// able to run commands or steer a removal somewhere else.
@MainActor
@Suite(.serialized)
final class HostileRepoTests {
    let base: String
    let root: String

    init() async throws {
        base = Scanner.normalize(FileManager.default.temporaryDirectory.path) + "/grove-hostile-\(UUID().uuidString)"
        root = base + "/code"
        AppSupport.directory = URL(fileURLWithPath: base).appending(path: "support", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    isolated deinit {
        try? FileManager.default.removeItem(atPath: base)
    }

    private func sh(_ script: String) async throws {
        let result = await Shell.run("/bin/bash", ["-c", "set -euo pipefail\nexport GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1\n" + script], timeout: 60)
        try #require(result.ok, "\(result.stderr)")
    }

    @Test func repositoryConfigCannotRunCommandsDuringAScan() async throws {
        let repo = root + "/unpacked-archive"
        let marker = base + "/ran"
        try await sh("""
        git init -q -b main '\(repo)'
        cd '\(repo)'
        echo hello > a.txt
        echo '* filter=sneaky' > .gitattributes
        git add -A
        git -c user.name=t -c user.email=t@example.com commit -qm init
        git config core.fsmonitor "touch '\(marker)-fsmonitor'; false"
        git config filter.sneaky.clean "touch '\(marker)-filter'; cat"
        git config filter.sneaky.required true
        git config log.showSignature true
        git config gpg.program "touch '\(marker)-gpg'; false"
        # Make the files look changed so status has to re-read them through the filter.
        touch -t 202001010000 a.txt .gitattributes
        """)

        let store = GroveStore(rootPath: root)
        await store.scan()

        let item = try #require(store.items.first { $0.name == "unpacked-archive" })
        #expect(item.git?.branch == "main")
        for suffix in ["fsmonitor", "filter", "gpg"] {
            #expect(!FileManager.default.fileExists(atPath: "\(marker)-\(suffix)"), "\(suffix) command ran")
        }
    }

    @Test func removingAWorktreeNeverMovesWhatItsGitFilePointsAt() async throws {
        // A folder whose `.git` file points at something shaped like worktree metadata,
        // outside any repository Grove scanned.
        let precious = base + "/precious/.git/worktrees/data"
        try await sh("""
        mkdir -p '\(precious)'
        git init -q --bare '\(precious)'
        echo important > '\(precious)/keep-me'
        mkdir -p '\(root)/rogue'
        echo "gitdir: \(precious)" > '\(root)/rogue/.git'
        echo '\(root)/rogue/.git' > '\(precious)/gitdir'
        """)

        let store = GroveStore(rootPath: root)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        store.undoManager = undoManager
        await store.scan()

        let rogue = try #require(store.items.first { $0.name == "rogue" })
        #expect(rogue.adminDir == nil)

        let plan = store.makeTrashPlan([rogue.id])
        #expect(plan.admins.isEmpty)
        undoManager.beginUndoGrouping()
        await store.performTrash(plan)
        undoManager.endUndoGrouping()
        #expect(FileManager.default.fileExists(atPath: precious + "/keep-me"))

        undoManager.undo()
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: rogue.path) {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(FileManager.default.fileExists(atPath: rogue.path))
    }

    @Test func worktreesWithRelativePathsStillLinkUp() async throws {
        try await sh("""
        git init -q -b main '\(root)/app'
        cd '\(root)/app'
        git -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
        git -c worktree.useRelativePaths=true worktree add -q -b feature '\(root)/app-feature'
        """)
        let store = GroveStore(rootPath: root)
        await store.scan()
        let worktree = try #require(store.items.first { $0.name == "app-feature" })
        #expect(worktree.parentPath == root + "/app")
        #expect(worktree.adminDir?.hasSuffix("/app/.git/worktrees/app-feature") == true)
    }

    @Test func parkingRefusesAnythingThatIsNotWorktreeMetadata() async throws {
        let folder = base + "/not-metadata"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let record = try await Actions.remove(folders: [], admins: [folder], repair: [])
        #expect(record.parkedAdmins.isEmpty)
        #expect(FileManager.default.fileExists(atPath: folder))
    }
}
