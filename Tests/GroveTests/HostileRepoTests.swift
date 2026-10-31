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

    private var stores: [GroveStore] = []

    isolated deinit {
        stores.forEach { $0.stop() }
        try? FileManager.default.removeItem(atPath: base)
    }

    private func makeStore() -> GroveStore {
        let store = GroveStore(rootPath: root)
        defer { store.stop() }
        stores.append(store)
        return store
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
        defer { store.stop() }
        await store.scan()

        let item = try #require(store.items.first { $0.name == "unpacked-archive" })
        #expect(item.git?.branch == "main")
        for suffix in ["fsmonitor", "filter", "gpg"] {
            #expect(!FileManager.default.fileExists(atPath: "\(marker)-\(suffix)"), "\(suffix) command ran")
        }
    }

    @Test func filterNamesCannotDodgeTheOverride() async throws {
        let repo = root + "/odd-filter"
        let marker = base + "/ran-odd"
        try await sh("""
        git init -q -b main '\(repo)'
        cd '\(repo)'
        echo hello > a.txt
        echo '* filter=a=b' > .gitattributes
        git add -A
        git -c user.name=t -c user.email=t@example.com commit -qm init
        git config 'filter.a=b.clean' "touch '\(marker)'; cat"
        touch -t 202001010000 a.txt .gitattributes
        """)
        let store = GroveStore(rootPath: root)
        defer { store.stop() }
        await store.scan()
        #expect(store.items.first { $0.name == "odd-filter" }?.git?.branch == "main")
        #expect(!FileManager.default.fileExists(atPath: marker))
    }

    @Test func aRepositoryCannotBorrowAnotherOnesWorktrees() async throws {
        try await sh("""
        git init -q -b main '\(base)/elsewhere/real'
        git -C '\(base)/elsewhere/real' -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
        git -C '\(base)/elsewhere/real' worktree add -q -b side '\(base)/elsewhere/real-side'
        git init -q -b main '\(root)/impostor'
        echo '\(base)/elsewhere/real/.git' > '\(root)/impostor/.git/commondir'
        """)
        let store = GroveStore(rootPath: root)
        defer { store.stop() }
        await store.scan()
        let impostor = try #require(store.items.first { $0.name == "impostor" })
        #expect(impostor.git?.worktrees.isEmpty == true)
        #expect(impostor.git?.branches.isEmpty == true)
        #expect(!store.items.contains { $0.name == "real-side" })
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
        defer { store.stop() }
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

    @Test func fetchAllSkipsRepositoriesThatDefineTheirOwnFetchCommands() async throws {
        let marker = base + "/ran"
        try await sh("""
        git init -q --bare -b main '\(base)/remote.git'
        for name in honest sneaky; do
          git init -q -b main "\(root)/$name"
          git -C "\(root)/$name" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
          git -C "\(root)/$name" remote add origin '\(base)/remote.git'
        done
        git -C '\(root)/honest' push -q origin main
        git -C '\(root)/sneaky' config remote.origin.uploadpack "touch '\(marker)-uploadpack'; git-upload-pack"
        git -C '\(root)/sneaky' config credential.helper "!touch '\(marker)-credential'"
        """)

        let store = GroveStore(rootPath: root)
        defer { store.stop() }
        await store.scan()
        store.fetchAll()
        for _ in 0..<200 where store.toast == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(store.toast?.message == "Fetched 1 of 2 · skipped sneaky, which sets its own fetch commands")
        #expect(!FileManager.default.fileExists(atPath: marker + "-uploadpack"))
        #expect(!FileManager.default.fileExists(atPath: marker + "-credential"))
        for _ in 0..<200 where store.phase != .idle {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func worktreesWithRelativePathsStillLinkUp() async throws {
        try await sh("""
        git init -q -b main '\(root)/app'
        cd '\(root)/app'
        git -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
        git -c worktree.useRelativePaths=true worktree add -q -b feature '\(root)/app-feature'
        """)
        let store = GroveStore(rootPath: root)
        defer { store.stop() }
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
