import Darwin
import Foundation

struct ShellResult: Sendable {
    var status: Int32
    var stdout: String
    var stderr: String

    var ok: Bool { status == 0 }
    var lines: [Substring] { stdout.split(separator: "\n", omittingEmptySubsequences: true) }
    var trimmed: String { stdout.trimmingCharacters(in: .whitespacesAndNewlines) }
}

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

enum Shell {
    /// Runs a process off the cooperative pool and returns its output. Never throws.
    ///
    /// Uses `posix_spawn` directly rather than `Process`: with dozens of git calls in flight,
    /// `Process`/`Pipe` occasionally lose output to file-descriptor races. Here each call owns
    /// its pipes outright, and the child inherits nothing but stdin/stdout/stderr.
    static func run(
        _ executable: String,
        _ arguments: [String],
        environment: [String: String] = [:],
        timeout: TimeInterval? = nil
    ) async -> ShellResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var env = ProcessInfo.processInfo.environment
                env.merge(environment) { _, new in new }
                continuation.resume(returning: spawn(executable, arguments, env: env, timeout: timeout))
            }
        }
    }

    private static func spawn(_ executable: String, _ arguments: [String], env: [String: String], timeout: TimeInterval?) -> ShellResult {
        var outFDs: [Int32] = [-1, -1]
        var errFDs: [Int32] = [-1, -1]
        guard pipe(&outFDs) == 0 else { return failure("pipe failed: \(errno)") }
        guard pipe(&errFDs) == 0 else {
            close(outFDs[0]); close(outFDs[1])
            return failure("pipe failed: \(errno)")
        }

        var actions = posix_spawn_file_actions_t(bitPattern: 0)
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, outFDs[1], 1)
        posix_spawn_file_actions_adddup2(&actions, errFDs[1], 2)

        var attributes = posix_spawnattr_t(bitPattern: 0)
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))

        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, executable, &actions, &attributes, argv, envp)
        close(outFDs[1])
        close(errFDs[1])
        guard rc == 0 else {
            close(outFDs[0]); close(errFDs[0])
            return failure(String(cString: strerror(rc)))
        }

        let child = pid
        let finished = Box(false)
        let lock = NSLock()
        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                lock.withLock { if !finished.value { kill(child, SIGTERM) } }
            }
        }

        // Drain stderr on another thread so a chatty process can't fill its pipe and stall.
        let errData = Box(Data())
        let group = DispatchGroup()
        group.enter()
        let errFD = errFDs[0]
        DispatchQueue.global(qos: .utility).async {
            errData.value = readAll(errFD)
            group.leave()
        }
        let outData = readAll(outFDs[0])
        group.wait()
        close(outFDs[0])
        close(errFDs[0])

        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        lock.withLock { finished.value = true }

        let exitCode: Int32 = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        return ShellResult(
            status: exitCode,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData.value, as: UTF8.self)
        )
    }

    private static func readAll(_ fd: Int32) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                data.append(buffer, count: n)
            } else if n == 0 || errno != EINTR {
                break
            }
        }
        return data
    }

    private static func failure(_ message: String) -> ShellResult {
        ShellResult(status: -1, stdout: "", stderr: message)
    }
}

/// Prints to stderr when `GROVE_DEBUG` is set.
func debugLog(_ message: @autoclosure () -> String) {
    guard ProcessInfo.processInfo.environment["GROVE_DEBUG"] != nil else { return }
    FileHandle.standardError.write(Data((message() + "\n").utf8))
}

enum Git {
    static let executable: String = {
        for candidate in ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"]
        where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return "/usr/bin/git"
    }()

    /// Read-only environment: never take the index lock, never prompt.
    static let baseEnvironment: [String: String] = [
        "GIT_OPTIONAL_LOCKS": "0",
        "GIT_TERMINAL_PROMPT": "0",
        "LC_ALL": "C",
    ]

    /// Grove runs git in every folder it finds, including ones nobody has vetted (an unpacked
    /// archive with a `.git` inside, say). These override repository settings that would
    /// otherwise let a folder's own config run programs while Grove looks at it.
    static let hardening = [
        "-c", "core.fsmonitor=false",
        "-c", "core.hooksPath=/dev/null",
        "-c", "core.pager=cat",
        "-c", "log.showSignature=false",
        "-c", "protocol.ext.allow=never",
    ]

    /// `overrides` go through `GIT_CONFIG_KEY_n`/`GIT_CONFIG_VALUE_n` rather than `-c`, so keys
    /// taken from a repository (a filter named `a=b`, say) can't be misread.
    static func run(
        _ path: String,
        _ args: [String],
        overrides: [(key: String, value: String)] = [],
        timeout: TimeInterval? = 30
    ) async -> ShellResult {
        var env = baseEnvironment
        if !overrides.isEmpty {
            env["GIT_CONFIG_COUNT"] = String(overrides.count)
            for (index, override) in overrides.enumerated() {
                env["GIT_CONFIG_KEY_\(index)"] = override.key
                env["GIT_CONFIG_VALUE_\(index)"] = override.value
            }
        }
        let result = await Shell.run(executable, ["-C", path] + hardening + args, environment: env, timeout: timeout)
        if !result.ok, !["merge-base", "config"].contains(args.first) {
            debugLog("git \(args.first ?? "") in \(path) -> \(result.status): \(result.stderr.prefix(160))")
        }
        return result
    }

    enum FetchOutcome: Sendable {
        case fetched, failed, skipped
    }

    /// Settings that make fetch run a program: credential helpers, proxy and askpass commands,
    /// and the upload-pack or remote helper a remote names.
    private static let fetchCommandKeys = #"^(credential\..*helper|core\.(gitproxy|askpass)|remote\..*\.(uploadpack|receivepack|vcs))$"#

    /// Only well-known transports, and no automatic gc or submodule fetches riding along.
    private static let fetchHardening = [
        "-c", "protocol.allow=never",
        "-c", "protocol.https.allow=always",
        "-c", "protocol.http.allow=always",
        "-c", "protocol.ssh.allow=always",
        "-c", "protocol.git.allow=always",
        "-c", "protocol.file.allow=always",
        "-c", "gc.auto=0",
        "-c", "maintenance.auto=false",
    ]

    /// Fetches every remote. A repository whose own config sets a fetch command is skipped
    /// rather than trusted; the same settings in the user's global config still apply.
    static func fetch(_ path: String) async -> FetchOutcome {
        guard let commands = await repositoryConfig(path, matching: fetchCommandKeys) else { return .skipped }
        if !commands.isEmpty { return .skipped }
        var env = baseEnvironment
        env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=10"
        let result = await Shell.run(
            executable,
            ["-C", path] + hardening + fetchHardening
                + ["fetch", "--all", "--prune", "--quiet", "--no-recurse-submodules", "--upload-pack=git-upload-pack"],
            environment: env,
            timeout: 60
        )
        return result.ok ? .fetched : .failed
    }

    /// Keys matching `pattern` that the repository sets itself (any scope but global and system).
    /// Returns nil when git can't say, so callers can fail closed.
    static func repositoryConfig(_ path: String, matching pattern: String) async -> [String]? {
        let result = await run(path, ["config", "--null", "--show-scope", "--get-regexp", pattern])
        guard result.status == 0 || result.status == 1 else { return nil }
        // Entries are `scope NUL key LF value NUL`.
        let fields = result.stdout.split(separator: "\0", omittingEmptySubsequences: false).dropLast()
        guard fields.count % 2 == 0 else { return nil }
        var keys: [String] = []
        for index in stride(from: fields.startIndex, to: fields.endIndex, by: 2) {
            let scope = fields[index]
            guard scope != "global", scope != "system" else { continue }
            let entry = fields[index + 1]
            keys.append(String(entry.prefix { $0 != "\n" }))
        }
        return keys
    }
}
