import SwiftUI

/// The Software Update window: a check's result, the offer of a new release, and its progress.
struct UpdateView: View {
    @Environment(Updater.self) private var updater
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title3.weight(.semibold))
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if case .available(let release) = updater.state {
                        Link("What's new in \(release.version)", destination: release.pageURL)
                            .padding(.top, 2)
                    }
                    if showsProgress {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .padding(.top, 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                buttons
            }
        }
        .padding(20)
        .frame(width: 460)
        .onDisappear { updater.windowClosed() }
    }

    @ViewBuilder
    private var buttons: some View {
        switch updater.state {
        case .available(let release):
            Button("Skip This Version") {
                updater.skip(release)
                dismiss()
            }
            Spacer()
            Button("Later") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Install and Relaunch") { updater.install(release) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        case .checking, .downloading:
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        case .installing:
            Spacer()
        case .idle:
            Spacer()
            Button("Check Now") { updater.checkNow() }
                .keyboardShortcut(.defaultAction)
        case .upToDate, .failed:
            Spacer()
            Button("OK") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    private var showsProgress: Bool {
        switch updater.state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    private var title: String {
        switch updater.state {
        case .idle: "Grove \(updater.currentVersion)"
        case .checking: "Checking for updates…"
        case .upToDate: "Grove is up to date"
        case .available(let release): "Grove \(release.version) is available"
        case .downloading(let release): "Downloading Grove \(release.version)…"
        case .installing(let release): "Installing Grove \(release.version)…"
        case .failed(let title, _): title
        }
    }

    private var detail: String {
        switch updater.state {
        case .idle: "See whether there's a newer release on GitHub."
        case .checking: "Looking for a newer release on GitHub."
        case .upToDate: "\(updater.currentVersion) is the newest version."
        case .available: "You have \(updater.currentVersion). It installs into Applications, which takes your password, and Grove reopens when it's done."
        case .downloading: "Grove checks the download against the release on GitHub before installing it."
        case .installing: "Enter your password to let the installer replace Grove in Applications."
        case .failed(_, let detail): detail
        }
    }
}
