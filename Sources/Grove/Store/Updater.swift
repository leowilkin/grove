import Foundation
import Observation

/// Keeps Grove up to date from its GitHub releases. Everything it shows lives in the
/// Software Update window, which reads `state`.
@Observable
@MainActor
final class Updater {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(Release)
        case installing(Release)
        case failed(title: String, detail: String)
    }

    var state: State = .idle
    var checksAutomatically: Bool { didSet { defaults.set(checksAutomatically, forKey: "checksForUpdates") } }
    private(set) var lastChecked: Date? { didSet { defaults.set(lastChecked, forKey: "lastUpdateCheck") } }
    private var skippedVersion: String? { didSet { defaults.set(skippedVersion, forKey: "skippedVersion") } }

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    /// An update always installs into /Applications, so only the copy there checks on its own.
    let isInstalledCopy = Bundle.main.bundleURL.standardizedFileURL == Releases.installedApp

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var work: Task<Void, Never>?

    init() {
        let d = UserDefaults.standard
        checksAutomatically = d.object(forKey: "checksForUpdates") as? Bool ?? true
        lastChecked = d.object(forKey: "lastUpdateCheck") as? Date
        skippedVersion = d.string(forKey: "skippedVersion")
    }

    var isWorking: Bool {
        switch state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    /// For the menu command and Settings. Does nothing while a check or install is under way,
    /// so opening the window just shows its progress.
    func checkNow() {
        guard !isWorking else { return }
        state = .checking
        work = Task { await check(manual: true) }
    }

    /// While the main window is open, looks for a new release once a day and calls `present`
    /// when there's one to offer.
    func checkAutomatically(present: () -> Void) async {
        try? await Task.sleep(for: .seconds(10))
        while !Task.isCancelled {
            if checksAutomatically, isInstalledCopy, !isWorking,
               Date().timeIntervalSince(lastChecked ?? .distantPast) > 86_400 {
                await check(manual: false)
                if case .available = state { present() }
            }
            try? await Task.sleep(for: .seconds(3600))
        }
    }

    private func check(manual: Bool) async {
        do {
            let release = try await Releases.latest()
            lastChecked = Date()
            guard !Task.isCancelled else { return }
            if let release, Releases.isNewer(release.version, than: currentVersion),
               manual || release.version != skippedVersion {
                state = .available(release)
            } else if manual {
                state = .upToDate
            }
        } catch {
            guard manual, !Task.isCancelled else { return debugLog("update check failed: \(error)") }
            state = .failed(title: "Couldn't check for updates", detail: error.localizedDescription)
        }
    }

    func skip(_ release: Release) {
        skippedVersion = release.version
    }

    func install(_ release: Release) {
        state = .downloading(release)
        work = Task {
            do {
                let (package, digest) = try await Releases.download(release)
                defer { try? FileManager.default.removeItem(at: package.deletingLastPathComponent()) }
                try await Releases.checkSigner(of: package)
                try Task.checkCancellation()
                state = .installing(release)
                try await Releases.install(package, digest: digest, version: release.version)
            } catch is CancellationError {
                // Dismissing the password prompt goes back to the offer.
                if case .installing = state { state = .available(release) }
                return
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(title: "Couldn't install Grove \(release.version)", detail: error.localizedDescription)
                return
            }
            do {
                try Releases.relaunch()
            } catch {
                state = .failed(title: "Grove \(release.version) is installed", detail: "Quit Grove and open it again to start using it.")
            }
        }
    }

    /// Closing the window means "not now": it stops a check or a download, but never an install
    /// that's already running as root.
    func windowClosed() {
        if case .installing = state { return }
        work?.cancel()
        work = nil
        state = .idle
    }
}
