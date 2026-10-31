import Foundation

struct Discovery: Sendable {
    struct Entry: Sendable {
        var path: String
        var group: String?
    }

    var repositories: [Entry] = []
    var worktrees: [Entry] = []
    var folders: [Entry] = []
}

struct CheckoutScan: Sendable {
    var git: GitInfo
    var activity: Date?
}

enum Scanner {
    private enum Marker { case repository, worktree, none }

    /// Canonical path via `realpath`, so `/tmp` and `/private/tmp` agree. Paths that no longer
    /// exist (missing worktrees) are resolved through their nearest existing ancestor.
    static func normalize(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        if let resolved = realpath(standardized, nil) {
            defer { free(resolved) }
            return String(cString: resolved)
        }
        let parent = (standardized as NSString).deletingLastPathComponent
        guard parent != standardized, !parent.isEmpty else { return standardized }
        return (normalize(parent) as NSString).appendingPathComponent((standardized as NSString).lastPathComponent)
    }

    // MARK: Discovery

    /// Lists the root one level deep, and peeks one more level into plain folders
    /// so `clients/acme`-style groups of repositories are found too.
    @concurrent
    static func discover(root: String) async -> Discovery {
        let rootURL = URL(fileURLWithPath: normalize(root), isDirectory: true)
        var result = Discovery()

        for url in directories(in: rootURL) {
            switch marker(url) {
            case .repository:
                result.repositories.append(.init(path: url.path))
            case .worktree:
                result.worktrees.append(.init(path: url.path))
            case .none:
                var nested = false
                for child in directories(in: url) {
                    switch marker(child) {
                    case .repository:
                        nested = true
                        result.repositories.append(.init(path: child.path, group: url.lastPathComponent))
                    case .worktree:
                        nested = true
                        result.worktrees.append(.init(path: child.path, group: url.lastPathComponent))
                    case .none:
                        break
                    }
                }
                if !nested { result.folders.append(.init(path: url.path)) }
            }
        }
        return result
    }

    private static func directories(in url: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.filter { entry in
            guard let values = try? entry.resourceValues(forKeys: Set(keys)) else { return false }
            return values.isDirectory == true && values.isSymbolicLink != true && values.isPackage != true
        }
        .map { URL(fileURLWithPath: normalize($0.path)) }
    }

    private static func marker(_ url: URL) -> Marker {
        let dotGit = url.appending(path: ".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) else { return .none }
        if isDirectory.boolValue { return .repository }
        if let contents = try? String(contentsOf: dotGit, encoding: .utf8), contents.contains("/worktrees/") {
            return .worktree
        }
        return .repository
    }

    /// Where a linked worktree's `.git` file points.
    static func gitdirTarget(ofWorktree path: String) -> String? {
        let dotGit = URL(fileURLWithPath: path).appending(path: ".git")
        guard let contents = try? String(contentsOf: dotGit, encoding: .utf8),
              let line = contents.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") })
        else { return nil }
        let gitdir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        return normalize(gitdir.hasPrefix("/") ? gitdir : (path as NSString).appendingPathComponent(gitdir))
    }

    /// Main repository path for a linked worktree, from its `.git` file.
    static func parentRepository(ofWorktree path: String) -> String? {
        guard let gitdir = gitdirTarget(ofWorktree: path),
              let range = gitdir.range(of: "/.git/worktrees/") else { return nil }
        return String(gitdir[..<range.lowerBound])
    }

    // MARK: Folders

    @concurrent
    static func folderActivity(_ path: String) async -> Date? {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        var latest = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        if let children = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
            for child in children.prefix(500) {
                if let date = (try? child.resourceValues(forKeys: Set(keys)))?.contentModificationDate {
                    latest = max(latest ?? date, date)
                }
            }
        }
        return latest
    }

    // MARK: Git

    /// Scans one checkout. `full` adds branches and worktrees, which only main repositories need.
    @concurrent
    static func scanCheckout(path: String, full: Bool) async -> CheckoutScan {
        var info = GitInfo()
        var changedPaths: [String] = []

        let dirs = await Git.run(path, ["rev-parse", "--path-format=absolute", "--git-dir", "--git-common-dir"])
        let dirLines = dirs.lines.map(String.init)
        if dirLines.count >= 2 {
            info.gitDir = dirLines[0]
            info.commonDir = dirLines[1]
        }

        // If git can't say which filters the repository defines, don't read through any of them.
        let filterOverrides = await untrustedFilterOverrides(path)
        let status = filterOverrides == nil ? ShellResult(status: -1, stdout: "", stderr: "") : await Git.run(path, [
            "status", "--porcelain=v2", "--branch", "--show-stash", "--untracked-files=normal", "--ignore-submodules=all",
        ], overrides: filterOverrides ?? [])
        var sawAheadBehind = false
        for line in status.lines {
            if line.hasPrefix("# ") {
                let parts = line.split(separator: " ", maxSplits: 2)
                guard parts.count == 3 else { continue }
                let value = String(parts[2])
                switch parts[1] {
                case "branch.oid":
                    info.headSHA = value == "(initial)" ? nil : value
                case "branch.head":
                    info.branch = value == "(detached)" ? nil : value
                case "branch.upstream":
                    info.upstream = value
                case "branch.ab":
                    sawAheadBehind = true
                    let nums = value.split(separator: " ")
                    if nums.count == 2 {
                        info.ahead = Int(nums[0].dropFirst()) ?? 0
                        info.behind = Int(nums[1].dropFirst()) ?? 0
                    }
                case "stash":
                    info.stashes = Int(value) ?? 0
                default:
                    break
                }
                continue
            }
            switch line.first {
            case "1":
                info.changes += 1
                if let p = entryPath(line, fields: 8) { changedPaths.append(p) }
            case "2":
                info.changes += 1
                if let p = entryPath(line, fields: 9) { changedPaths.append(String(p.split(separator: "\t").first ?? "")) }
            case "u":
                info.conflicts += 1
            case "?":
                info.untracked += 1
                changedPaths.append(String(line.dropFirst(2)))
            default:
                break
            }
        }
        // An upstream with no ahead/behind line means the remote branch is gone.
        info.upstreamGone = info.upstream != nil && !sawAheadBehind

        let log = await Git.run(path, ["log", "-1", "--format=%H%x1f%h%x1f%s%x1f%an%x1f%ct"])
        let fields = log.trimmed.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
        if log.ok, fields.count == 5, let ts = TimeInterval(fields[4]) {
            info.lastCommit = CommitInfo(sha: fields[0], shortSHA: fields[1], subject: fields[2], author: fields[3], date: Date(timeIntervalSince1970: ts))
        }

        let remotes = await Git.run(path, ["remote", "-v"])
        let remoteLines = remotes.lines.filter { $0.hasSuffix("(fetch)") }
        let preferred = remoteLines.first { $0.hasPrefix("origin\t") } ?? remoteLines.first
        if let preferred {
            let parts = preferred.split(separator: "\t")
            if parts.count >= 2 {
                info.remoteURL = String(parts[1].split(separator: " ").first ?? "")
            }
        }

        let candidates = await Git.run(path, [
            "for-each-ref", "--format=%(refname)%1f%(symref)",
            "refs/remotes/origin/HEAD", "refs/remotes/origin/main", "refs/remotes/origin/master",
            "refs/heads/main", "refs/heads/master",
        ])
        var refs: [String: String] = [:]
        for line in candidates.lines {
            let parts = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            if parts.count == 2 { refs[parts[0]] = parts[1] }
        }
        if let target = refs["refs/remotes/origin/HEAD"], !target.isEmpty {
            info.defaultRef = target
        } else {
            info.defaultRef = ["refs/remotes/origin/main", "refs/remotes/origin/master", "refs/heads/main", "refs/heads/master"]
                .first { refs[$0] != nil }
        }

        if info.headSHA != nil {
            if let defaultRef = info.defaultRef, !info.isOnDefaultBranch {
                let ancestor = await Git.run(path, ["merge-base", "--is-ancestor", "HEAD", defaultRef])
                info.isMerged = ancestor.ok
            }
            if info.remoteURL != nil {
                let count = await Git.run(path, ["rev-list", "--count", "HEAD", "--not", "--remotes"])
                info.unpushed = Int(count.trimmed) ?? 0
            } else {
                info.unpushed = 0
            }
        }

        // Branches and worktrees only for a plain repository whose data lives in its own `.git`:
        // a real folder (not a symlink) that git agrees is both its git dir and common dir.
        // Otherwise a symlink or `commondir` file could borrow another repository's.
        let ownGitDir = normalize(path) + "/.git"
        let gitFolderType = (try? FileManager.default.attributesOfItem(atPath: ownGitDir))?[.type] as? FileAttributeType
        if full, gitFolderType == .typeDirectory,
           info.gitDir.map(normalize) == ownGitDir, info.commonDir.map(normalize) == ownGitDir {
            await scanBranches(path: path, into: &info)
            await scanWorktrees(path: path, into: &info)
        }

        let activity = activityDate(path: path, info: info, changedPaths: changedPaths)
        return CheckoutScan(git: info, activity: activity)
    }

    /// `git status` re-reads changed files through any clean filter `.gitattributes` names.
    /// Filters defined in the user's global or system config (git-lfs, say) are trusted; ones
    /// defined by the repository itself are switched off for Grove's read.
    private static func untrustedFilterOverrides(_ path: String) async -> [(key: String, value: String)]? {
        guard let keys = await Git.repositoryConfig(path, matching: #"^filter\..*\.(clean|smudge|process)$"#) else { return nil }
        var drivers = Set<String>()
        for key in keys {
            guard key.hasPrefix("filter."),
                  let variable = ["clean", "smudge", "process"].first(where: { key.hasSuffix(".\($0)") }),
                  key.count > "filter.".count + variable.count + 1
            else { return nil }
            drivers.insert(String(key.dropFirst("filter.".count).dropLast(variable.count + 1)))
        }
        return drivers.sorted().flatMap { name in
            ["clean", "smudge", "process"].map { (key: "filter.\(name).\($0)", value: "") }
                + [(key: "filter.\(name).required", value: "false")]
        }
    }

    private static func entryPath(_ line: Substring, fields: Int) -> String? {
        let parts = line.split(separator: " ", maxSplits: fields, omittingEmptySubsequences: false)
        guard parts.count == fields + 1 else { return nil }
        return String(parts[fields])
    }

    private static func scanBranches(path: String, into info: inout GitInfo) async {
        let refs = await Git.run(path, [
            "for-each-ref",
            "--format=%(refname:short)%1f%(objectname:short)%1f%(upstream:short)%1f%(upstream:track)%1f%(committerdate:unix)%1f%(worktreepath)",
            "refs/heads",
        ])
        var merged: Set<String> = []
        if let defaultRef = info.defaultRef {
            let result = await Git.run(path, ["branch", "--merged", defaultRef, "--format=%(refname:short)"])
            merged = Set(result.lines.map(String.init))
        }
        let defaultName = info.defaultBranchName

        info.branches = refs.lines.compactMap { line in
            let f = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 6 else { return nil }
            let track = f[3]
            var ahead = 0
            var behind = 0
            if let m = track.firstMatch(of: /ahead (\d+)/) { ahead = Int(m.1) ?? 0 }
            if let m = track.firstMatch(of: /behind (\d+)/) { behind = Int(m.1) ?? 0 }
            return BranchInfo(
                name: f[0],
                sha: f[1],
                upstream: f[2].isEmpty ? nil : f[2],
                upstreamGone: track.contains("gone"),
                ahead: ahead,
                behind: behind,
                date: TimeInterval(f[4]).map { Date(timeIntervalSince1970: $0) },
                isMerged: f[0] != defaultName && merged.contains(f[0]),
                worktreePath: f[5].isEmpty ? nil : normalize(f[5])
            )
        }

        if info.remoteURL != nil {
            let count = await Git.run(path, ["rev-list", "--count", "--branches", "--not", "--remotes"])
            info.unpushedAllBranches = Int(count.trimmed) ?? 0
        }
    }

    private static func scanWorktrees(path: String, into info: inout GitInfo) async {
        let list = await Git.run(path, ["worktree", "list", "--porcelain"])
        var records: [WorktreeRecord] = []
        var current: WorktreeRecord?
        var isFirst = true

        func flush() {
            if let record = current {
                if !isFirst { records.append(record) }
                isFirst = false
            }
            current = nil
        }

        for line in list.stdout.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("worktree ") {
                flush()
                current = WorktreeRecord(path: normalize(String(line.dropFirst(9))), isLocked: false, isPrunable: false)
            } else if line.hasPrefix("HEAD ") {
                current?.head = String(line.dropFirst(5))
            } else if line.hasPrefix("branch ") {
                current?.branch = String(line.dropFirst(7)).replacingOccurrences(of: "refs/heads/", with: "")
            } else if line.hasPrefix("locked") {
                current?.isLocked = true
            } else if line.hasPrefix("prunable") {
                current?.isPrunable = true
            }
        }
        flush()

        // Map worktree paths to their admin folders so removal can be undone.
        if let common = info.commonDir {
            let adminRoot = URL(fileURLWithPath: common).appending(path: "worktrees")
            let admins = (try? FileManager.default.contentsOfDirectory(at: adminRoot, includingPropertiesForKeys: nil)) ?? []
            var byPath: [String: String] = [:]
            for admin in admins {
                let gitdirFile = admin.appending(path: "gitdir")
                guard let raw = try? String(contentsOf: gitdirFile, encoding: .utf8) else { continue }
                // Relative entries (`worktree.useRelativePaths`) are relative to the admin folder.
                let target = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let absolute = target.hasPrefix("/") ? target : admin.appending(path: target).path
                let worktreePath = (absolute as NSString).deletingLastPathComponent
                byPath[normalize(worktreePath)] = admin.path
                // Prunable entries may point to a path that no longer resolves, so keep the raw form too.
                byPath[(worktreePath as NSString).standardizingPath] = admin.path
            }
            for index in records.indices {
                records[index].adminDir = byPath[records[index].path]
            }
        }
        // A worktree is only this repository's if its folder points back at the same metadata.
        // Otherwise a repository could claim any folder on disk as one of its worktrees.
        records.removeAll { record in
            guard !record.isPrunable, FileManager.default.fileExists(atPath: record.path) else { return false }
            guard let admin = record.adminDir else { return true }
            return gitdirTarget(ofWorktree: record.path) != normalize(admin)
        }
        info.worktrees = records
    }

    /// Latest of: last commit, last HEAD movement (commit, checkout, pull), and edits to changed files.
    private static func activityDate(path: String, info: GitInfo, changedPaths: [String]) -> Date? {
        var dates: [Date] = []
        if let commit = info.lastCommit?.date { dates.append(commit) }
        if let gitDir = info.gitDir {
            for file in ["logs/HEAD", "HEAD"] {
                if let date = modificationDate(URL(fileURLWithPath: gitDir).appending(path: file).path) {
                    dates.append(date)
                }
            }
        }
        let base = URL(fileURLWithPath: path)
        for relative in changedPaths.prefix(200) {
            if let date = modificationDate(base.appending(path: relative).path) { dates.append(date) }
        }
        return dates.max()
    }

    private static func modificationDate(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    // MARK: Size

    @concurrent
    static func diskSize(_ path: String) async -> Int64? {
        let result = await Shell.run("/usr/bin/du", ["-sk", path], timeout: 180)
        guard let first = result.stdout.split(whereSeparator: { $0 == "\t" || $0 == " " }).first,
              let kb = Int64(first) else { return nil }
        return kb * 1024
    }
}
