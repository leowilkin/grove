import Foundation

enum ItemKind: String, Codable, Sendable, CaseIterable {
    case repository
    case worktree
    case folder
}

struct CommitInfo: Codable, Hashable, Sendable {
    var sha: String
    var shortSHA: String
    var subject: String
    var author: String
    var date: Date
}

struct BranchInfo: Codable, Hashable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var sha: String
    var upstream: String?
    var upstreamGone: Bool
    var ahead: Int
    var behind: Int
    var date: Date?
    var isMerged: Bool
    /// Set when this branch is checked out in some worktree (including the main one).
    var worktreePath: String?
}

struct WorktreeRecord: Codable, Hashable, Sendable {
    var path: String
    var head: String?
    var branch: String?
    var isLocked: Bool
    var isPrunable: Bool
    /// `.git/worktrees/<id>` inside the main repository.
    var adminDir: String?
}

struct GitInfo: Codable, Hashable, Sendable {
    var branch: String?
    var headSHA: String?
    var upstream: String?
    var upstreamGone = false
    var ahead = 0
    var behind = 0
    var changes = 0
    var untracked = 0
    var conflicts = 0
    var stashes = 0
    /// Commits reachable from HEAD that aren't on any remote.
    var unpushed = 0
    /// Commits on any local branch that aren't on any remote (main repos only).
    var unpushedAllBranches = 0
    var lastCommit: CommitInfo?
    var remoteURL: String?
    /// Fully qualified ref, e.g. `refs/remotes/origin/main`.
    var defaultRef: String?
    var isMerged = false
    var branches: [BranchInfo] = []
    var worktrees: [WorktreeRecord] = []
    var gitDir: String?
    var commonDir: String?

    var defaultBranchName: String? {
        guard let defaultRef else { return nil }
        for prefix in ["refs/remotes/origin/", "refs/heads/"] where defaultRef.hasPrefix(prefix) {
            return String(defaultRef.dropFirst(prefix.count))
        }
        return defaultRef
    }

    var isOnDefaultBranch: Bool {
        branch != nil && branch == defaultBranchName
    }
}

struct GroveItem: Codable, Hashable, Sendable, Identifiable {
    var id: String { path }
    var path: String
    var name: String
    var kind: ItemKind
    /// Enclosing folder name for repositories found one level down (e.g. `clients/foo`).
    var group: String?
    /// For worktrees: the main repository's path.
    var parentPath: String?
    var isInsideRoot = true
    /// True when this worktree lives inside its parent repository's folder (e.g. `.claude/worktrees`).
    var isNestedInParent = false
    var isMissing = false
    var isLocked = false
    var adminDir: String?
    var git: GitInfo?
    /// Activity of this checkout alone.
    var ownActivity: Date?
    /// Activity including linked worktrees (for repositories).
    var lastActivity: Date?
    var size: Int64?
    var sizedAt: Date?
}

extension GroveItem {
    var uncommitted: Int {
        guard let git else { return 0 }
        return git.changes + git.untracked + git.conflicts
    }

    var unpushed: Int { git?.unpushed ?? 0 }
    var hasRemote: Bool { git?.remoteURL != nil }

    var activityKey: Date { lastActivity ?? .distantPast }
    var sizeKey: Int64 { size ?? -1 }
    var branchKey: String { git?.branch ?? git?.headSHA ?? "" }
    var statusRank: Int { issues.first?.rank ?? 99 }

    var displayPath: String { (path as NSString).abbreviatingWithTildeInPath }

    var branchLabel: String? {
        guard let git else { return nil }
        if let branch = git.branch { return branch }
        if let sha = git.headSHA { return "detached @ \(sha.prefix(7))" }
        return nil
    }

    var webURL: URL? {
        guard let remote = git?.remoteURL else { return nil }
        return RemoteURL.web(remote)
    }

    var issues: [Issue] {
        var result: [Issue] = []
        if isMissing { return [.missing] }
        guard let git else { return [] }
        if git.conflicts > 0 { result.append(.conflicts(git.conflicts)) }
        if git.changes + git.untracked > 0 { result.append(.uncommitted(git.changes + git.untracked)) }
        if git.remoteURL != nil, git.unpushed > 0, !git.upstreamGone { result.append(.unpushed(git.unpushed)) }
        if git.upstreamGone { result.append(.remoteDeleted) }
        if git.isMerged, !git.upstreamGone { result.append(.merged) }
        if git.behind > 0 { result.append(.behind(git.behind)) }
        if git.stashes > 0 { result.append(.stashes(git.stashes)) }
        if git.remoteURL == nil { result.append(.noRemote) }
        if isLocked { result.append(.locked) }
        return result
    }
}

enum Issue: Hashable, Sendable {
    case missing
    case conflicts(Int)
    case uncommitted(Int)
    case unpushed(Int)
    case remoteDeleted
    case merged
    case behind(Int)
    case stashes(Int)
    case noRemote
    case locked

    var rank: Int {
        switch self {
        case .missing: 0
        case .conflicts: 1
        case .uncommitted: 2
        case .unpushed: 3
        case .remoteDeleted: 4
        case .merged: 5
        case .behind: 6
        case .stashes: 7
        case .noRemote: 8
        case .locked: 9
        }
    }
}

enum RemoteURL {
    /// Turns `git@github.com:owner/repo.git` or `https://github.com/owner/repo.git` into a browsable URL.
    static func web(_ remote: String) -> URL? {
        var s = remote.trimmingCharacters(in: .whitespaces)
        if s.hasSuffix(".git") { s.removeLast(4) }
        if s.hasPrefix("git@") {
            s.removeFirst(4)
            s = "https://" + s.replacingOccurrences(of: ":", with: "/", options: [], range: s.range(of: ":"))
        } else if s.hasPrefix("ssh://") {
            s.removeFirst(6)
            if let at = s.firstIndex(of: "@") { s = String(s[s.index(after: at)...]) }
            s = "https://" + s
        } else if s.hasPrefix("http://") || s.hasPrefix("https://") {
            if let url = URL(string: s), var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                c.user = nil
                c.password = nil
                return c.url
            }
        } else {
            return nil
        }
        return URL(string: s)
    }

    /// `owner/repo` style short name for display.
    static func short(_ remote: String) -> String {
        if remote.hasPrefix("/") || remote.hasPrefix("file://") {
            return "\((remote as NSString).lastPathComponent) (local)"
        }
        guard let url = web(remote) else { return remote }
        let parts = url.path.split(separator: "/")
        let host = url.host() ?? ""
        let path = parts.joined(separator: "/")
        return host == "github.com" ? path : "\(host)/\(path)"
    }
}
