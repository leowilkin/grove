import Foundation
import Testing
@testable import Grove

struct ReleasesTests {
    @Test func comparesVersionsPartByPart() {
        #expect(Releases.isNewer("1.0.1", than: "1.0.0"))
        #expect(Releases.isNewer("1.10.0", than: "1.9.0"))
        #expect(Releases.isNewer("2", than: "1.9.9"))
        #expect(!Releases.isNewer("1.0.0", than: "1.0.0"))
        #expect(!Releases.isNewer("1.0.0", than: "1.0"))
        #expect(!Releases.isNewer("1.0", than: "1.0.0"))
        #expect(!Releases.isNewer("0.9.9", than: "1.0"))
    }

    @Test func readsTheLatestReleaseFromGitHub() throws {
        let release = try Releases.parse(Data(Self.payload(assets: [
            ("Grove.pkg", "sha256:ABCDEF0123"),
            ("notes.txt", nil),
        ]).utf8))
        #expect(release.version == "1.2.0")
        #expect(release.pageURL.absoluteString == "https://github.com/example/grove/releases/tag/v1.2.0")
        #expect(release.packageURL.absoluteString == "https://github.com/example/grove/releases/download/v1.2.0/Grove.pkg")
        #expect(release.digest == "abcdef0123")
    }

    @Test func refusesToInstallWithoutADigest() async throws {
        let release = try Releases.parse(Data(Self.payload(assets: [("Grove.pkg", nil)]).utf8))
        #expect(release.digest == nil)
        await #expect(throws: Releases.Failure.self) { try await Releases.download(release) }
    }

    @Test func refusesAReleaseWithoutTheInstaller() {
        #expect(throws: Releases.Failure.self) {
            try Releases.parse(Data(Self.payload(assets: [("Grove.dmg", nil)]).utf8))
        }
    }

    @Test func hashesTheDownload() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "grove-hash-\(UUID().uuidString)")
        try Data("grove".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try Releases.sha256(of: file) == "8a0e7f923a4d3e55bf8e1db51a54602fb8a3e4f458b7c19f34c360b4525def1f")
    }

    @Test func tidiesTheInstallerMessage() {
        #expect(Releases.installerMessage("0:310: execution error: installer: Error - the package is damaged. (1)\n")
            == "installer: Error - the package is damaged.")
        #expect(Releases.installerMessage("") == "The installer didn't finish.")
    }

    private static func payload(assets: [(name: String, digest: String?)]) -> String {
        let list = assets.map { asset in
            """
            {"name": "\(asset.name)", "digest": \(asset.digest.map { "\"\($0)\"" } ?? "null"),
             "browser_download_url": "https://github.com/example/grove/releases/download/v1.2.0/\(asset.name)"}
            """
        }
        return """
            {"tag_name": "v1.2.0", "draft": false, "prerelease": false,
             "html_url": "https://github.com/example/grove/releases/tag/v1.2.0",
             "assets": [\(list.joined(separator: ","))]}
            """
    }
}
