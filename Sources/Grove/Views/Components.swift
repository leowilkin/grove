import SwiftUI

extension ItemKind {
    var symbol: String {
        switch self {
        case .repository: "shippingbox.fill"
        case .worktree: "arrow.triangle.branch"
        case .folder: "folder.fill"
        }
    }

    var tint: Color {
        switch self {
        case .repository: .blue
        case .worktree: .green
        case .folder: .gray
        }
    }

    var label: String {
        switch self {
        case .repository: "Repository"
        case .worktree: "Worktree"
        case .folder: "Folder"
        }
    }
}

/// A System Settings–style rounded glyph tile.
struct IconTile: View {
    var symbol: String
    var tint: Color
    var size: CGFloat = 26

    init(kind: ItemKind, missing: Bool = false, size: CGFloat = 26) {
        self.symbol = missing ? "questionmark.folder.fill" : kind.symbol
        self.tint = missing ? .red : kind.tint
        self.size = size
    }

    init(symbol: String, tint: Color, size: CGFloat = 26) {
        self.symbol = symbol
        self.tint = tint
        self.size = size
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(tint.gradient)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.10), radius: 1, y: 0.5)
    }
}

struct Pill: View {
    var text: String
    var symbol: String?
    var tint: Color

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol).imageScale(.small)
            }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .foregroundStyle(tint)
        .background(tint.opacity(0.13), in: .capsule)
    }
}

extension Issue {
    var pill: Pill {
        switch self {
        case .missing: Pill(text: "Folder missing", symbol: "questionmark.folder", tint: .red)
        case .conflicts(let n): Pill(text: "\(n) conflict\(n == 1 ? "" : "s")", symbol: "exclamationmark.triangle.fill", tint: .red)
        case .uncommitted(let n): Pill(text: "\(n) change\(n == 1 ? "" : "s")", symbol: "pencil", tint: .orange)
        case .unpushed(let n): Pill(text: "\(n) unpushed", symbol: "arrow.up", tint: .blue)
        case .remoteDeleted: Pill(text: "Remote deleted", symbol: "cloud.slash", tint: .purple)
        case .merged: Pill(text: "Merged", symbol: "checkmark", tint: .green)
        case .behind(let n): Pill(text: "\(n) behind", symbol: "arrow.down", tint: .secondary)
        case .stashes(let n): Pill(text: "\(n) stash\(n == 1 ? "" : "es")", symbol: "tray", tint: .secondary)
        case .noRemote: Pill(text: "No remote", symbol: "externaldrive", tint: .secondary)
        case .locked: Pill(text: "Locked", symbol: "lock.fill", tint: .secondary)
        }
    }
}

struct StatusPills: View {
    var item: GroveItem
    var limit = 2

    var body: some View {
        let issues = item.issues
        HStack(spacing: 4) {
            if item.kind == .folder {
                Text("Not a git repository").foregroundStyle(.tertiary)
            } else if issues.isEmpty {
                Text("Clean").foregroundStyle(.tertiary)
            } else {
                // Show as many pills as fit, then a count of the rest.
                ViewThatFits(in: .horizontal) {
                    ForEach((1...max(1, min(limit, issues.count))).reversed(), id: \.self) { shown in
                        pills(issues, shown: shown)
                    }
                }
            }
        }
    }

    private func pills(_ issues: [Issue], shown: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(issues.prefix(shown)), id: \.self) { $0.pill.fixedSize() }
            if issues.count > shown {
                Text("+\(issues.count - shown)").font(.caption).foregroundStyle(.tertiary).fixedSize()
            }
        }
    }
}

struct ActivityDot: View {
    var activity: Activity
    var body: some View {
        Circle().fill(activity.color.gradient).frame(width: 7, height: 7)
    }
}

extension Date {
    var relativeLabel: String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: self), to: Calendar.current.startOfDay(for: .now)).day ?? 0
        if days <= 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        if days < 7 { return "\(days) days ago" }
        if days < 30 { let w = days / 7; return "\(w) week\(w == 1 ? "" : "s") ago" }
        if days < 365 { let m = max(1, days / 30); return "\(m) month\(m == 1 ? "" : "s") ago" }
        let y = days / 365
        return "\(y) year\(y == 1 ? "" : "s") ago"
    }
}

extension Int64 {
    var bytesLabel: String { formatted(.byteCount(style: .file)) }
}

/// A card surface matching grouped forms.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
            }
    }
}

extension View {
    func card(padding: CGFloat = 0) -> some View { modifier(CardBackground(padding: padding)) }
}

/// Icon-over-caption button, like the action row in Contacts or Maps.
struct ActionTile: View {
    var title: String
    var image: Image
    var isTemplate = false
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                image
                    .resizable()
                    .renderingMode(isTemplate ? .template : .original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: isTemplate ? 18 : 26, height: isTemplate ? 18 : 26)
                    .frame(height: 26)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(.fill.opacity(hovering ? 0.9 : 0.55), in: .rect(cornerRadius: 10, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(title)
    }
}

extension Color {
    /// Tints floating glass bars so table rows scrolling underneath don't show through the text.
    static let floatingBarTint = Color(nsColor: .windowBackgroundColor).opacity(0.75)
}
