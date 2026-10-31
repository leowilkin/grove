import AppKit
import CryptoKit
import Security

struct Release: Equatable, Sendable {
    var version: String
    var pageURL: URL
    var packageURL: URL
    /// The SHA-256 GitHub records for the installer, as lowercase hex.
    var digest: String?
}

/// Grove's releases on GitHub, and installing one over the running app.
enum Releases {
    static let repository = "leowilkin/grove"
    static let packageName = "Grove.pkg"
    /// Where Grove.pkg puts the app, wherever the running copy happens to be.
    static let installedApp = URL(fileURLWithPath: "/Applications/Grove.app")

    enum Failure: LocalizedError {
        case status(Int)
        case noPackage(String)
        case digestMismatch
        case untrusted
        case installFailed(String)

        var errorDescription: String? {
            switch self {
            case .status(let code): "GitHub answered with status \(code)."
            case .noPackage(let version): "Grove \(version) doesn't have an installer attached yet."
            case .digestMismatch: "The download doesn't match the installer GitHub published."
            case .untrusted: "The installer isn't signed by the developer who signed this copy of Grove."
            case .installFailed(let message): message
            }
        }
    }

    /// The newest published release, or nil if there isn't one. Drafts and prereleases don't count.
    static func latest() async throws -> Release? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard status == 200 else { throw Failure.status(status) }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> Release {
        struct Payload: Decodable {
            struct Asset: Decodable {
                var name: String
                var browserDownloadUrl: URL
                var digest: String?
            }
            var tagName: String
            var htmlUrl: URL
            var assets: [Asset]
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(Payload.self, from: data)
        let version = payload.tagName.hasPrefix("v") ? String(payload.tagName.dropFirst()) : payload.tagName
        guard let asset = payload.assets.first(where: { $0.name == packageName }) else { throw Failure.noPackage(version) }
        let digest = asset.digest.flatMap { $0.hasPrefix("sha256:") ? $0.dropFirst(7).lowercased() : nil }
        return Release(version: version, pageURL: payload.htmlUrl, packageURL: asset.browserDownloadUrl, digest: digest)
    }

    /// Compares dotted version numbers, treating missing parts as zero, so 1.0 and 1.0.0 are the same.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            version.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Downloads the installer into a folder of its own and checks it's the one GitHub published.
    /// Returns its SHA-256, which the install checks again. The caller removes the folder.
    static func download(_ release: Release) async throws -> (package: URL, digest: String) {
        let (temporary, response) = try await URLSession.shared.download(from: release.packageURL)
        let folder = FileManager.default.temporaryDirectory.appending(path: "Grove-\(release.version)-\(UUID().uuidString)")
        do {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw Failure.status(status) }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let package = folder.appending(path: packageName)
            try FileManager.default.moveItem(at: temporary, to: package)
            let digest = try sha256(of: package)
            if let expected = release.digest, expected != digest { throw Failure.digestMismatch }
            return (package, digest)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    static func sha256(of file: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: file, options: .mappedIfSafe))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Once Grove ships with a Developer ID, an update has to be signed by the same team. A copy
    /// signed ad hoc has no team to match, so the digest is the only check.
    static func checkSigner(of package: URL) async throws {
        guard let team = teamIdentifier else { return }
        let result = await Shell.run("/usr/sbin/pkgutil", ["--check-signature", package.path])
        let leaf = result.stdout.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("1. ") }
        guard result.ok,
              result.stdout.contains("issued by Apple for distribution"),
              let leaf, leaf.hasSuffix("(\(team))")
        else { throw Failure.untrusted }
    }

    /// The developer team that signed the running app, if any.
    static var teamIdentifier: String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Runs the installer as root, behind the system's password prompt. Throws `CancellationError`
    /// if the prompt is dismissed. The package is first copied somewhere only root can write and
    /// its digest checked again there, so nothing can swap it between the checks and the install.
    static func install(_ package: URL, digest: String, version: String) async throws {
        let shell = """
            set -e
            dir=$(/usr/bin/mktemp -d)
            trap '/bin/rm -rf "$dir"' EXIT
            /bin/cp "$1" "$dir/Grove.pkg"
            if [ "$(/usr/bin/openssl dgst -sha256 -r "$dir/Grove.pkg" | /usr/bin/cut -d' ' -f1)" != "$2" ]; then
              echo "The installer changed after it was downloaded." >&2
              exit 1
            fi
            /usr/sbin/installer -pkg "$dir/Grove.pkg" -target /
            """
        // Everything reaches AppleScript as an argument, and the shell through `quoted form of`.
        let script = [
            "on run argv",
            #"do shell script "/bin/sh -c " & quoted form of (item 1 of argv) & " sh " & quoted form of (item 2 of argv) & " " & quoted form of (item 3 of argv) with prompt (item 4 of argv) with administrator privileges"#,
            "end run",
        ]
        let result = await Shell.run(
            "/usr/bin/osascript",
            script.flatMap { ["-e", $0] } + [shell, package.path, digest, "Grove wants to install version \(version)."]
        )
        if result.ok { return }
        if result.stderr.contains("(-128)") { throw CancellationError() }
        throw Failure.installFailed(installerMessage(result.stderr))
    }

    /// osascript reports `0:123: execution error: <what the command printed> (<status>)`.
    static func installerMessage(_ stderr: String) -> String {
        var message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = message.range(of: "execution error: ") { message = String(message[range.upperBound...]) }
        if let range = message.range(of: #" \(-?\d+\)$"#, options: .regularExpression) { message.removeSubrange(range) }
        return message.isEmpty ? "The installer didn't finish." : message
    }

    /// Quits, and opens the newly installed copy once this one has gone.
    @MainActor
    static func relaunch() throws {
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        waiter.arguments = [
            "-c", #"while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open "$2""#,
            "sh", String(getpid()), installedApp.path,
        ]
        try waiter.run()
        NSApp.terminate(nil)
    }
}
