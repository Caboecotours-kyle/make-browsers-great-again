import AppKit
import SwiftUI

struct ImportRequest: Identifiable {
    let id = UUID()
    /// The welcome sheet at first launch, rather than File ▸ Import.
    let firstLaunch: Bool
}

/// Finds other browsers on this Mac and imports their spaces, tabs and
/// bookmarks. Shown once at first launch, and from File ▸ Import.
struct ImportSheet: View {
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.dismiss) private var dismiss
    let request: ImportRequest

    private enum Phase {
        case scanning
        case choosing([ImportSourceInfo])
        case importing
        case done(ImportSummary)
        /// First launch only: layout and color, after importing or not.
        case style
    }

    @State private var phase = Phase.scanning
    @State private var selected: Set<String> = []
    @State private var imported = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            switch phase {
            case .scanning:
                status("Looking for other browsers…")
            case .choosing(let sources):
                if sources.isEmpty {
                    Text("No other browsers with tabs or bookmarks were found on this Mac.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    sourceList(sources)
                    Text("Tabs and bookmarks are copied; your other browsers stay as they are. Passwords, history and cookies aren't imported, so you'll sign in to sites again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .importing:
                status("Importing…")
            case .done(let summary):
                doneView(summary)
            case .style:
                StylePicker(color: store.activeSpace.color)
            }
            buttons
        }
        .padding(24)
        .frame(width: 540)
        .task {
            // MBGA_DEBUG_ONBOARDING=style opens straight at the style step,
            // for screenshots.
            if ProcessInfo.processInfo.environment["MBGA_DEBUG_ONBOARDING"] == "style" {
                phase = .style
            } else {
                await scan()
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if case .style = phase {
                Text("Make it yours")
                    .font(.system(size: 22, weight: .semibold))
                Text("Pick a layout and how much color your spaces bring. You can change both later from the View menu.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(request.firstLaunch ? "Welcome to MBGA" : "Import from Another Browser")
                    .font(.system(size: 22, weight: .semibold))
                Text("Bring your spaces, pinned tabs, open tabs and bookmarks from the browsers on this Mac.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func status(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func sourceList(_ sources: [ImportSourceInfo]) -> some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(sources, id: \.id) { source in
                    SourceRow(source: source, selected: $selected)
                }
            }
        }
        .frame(maxHeight: 340)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func doneView(_ s: ImportSummary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text(summaryText(s)).font(.system(size: 14, weight: .medium))
                Text("Bookmarks are in folders under each space's pinned tabs. Nothing loads until you open it.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
    }

    @ViewBuilder private var buttons: some View {
        HStack {
            switch phase {
            case .scanning, .importing:
                Spacer()
                Button(request.firstLaunch ? "Skip" : "Cancel") { finish() }
                    .keyboardShortcut(.cancelAction)
            case .choosing(let sources):
                Button(request.firstLaunch ? "Start Fresh" : "Cancel") { next() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if sources.isEmpty {
                    Button("Get Started") { next() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Import") { runImport(sources) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(selected.isEmpty)
                }
            case .done:
                Spacer()
                Button(request.firstLaunch ? "Continue" : "Done") { next() }.keyboardShortcut(.defaultAction)
            case .style:
                Spacer()
                Button("Start Browsing") { finish() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Actions

    private func scan() async {
        let core = store.core
        let home = ProcessInfo.processInfo.environment["MBGA_IMPORT_HOME"] ?? NSHomeDirectory()
        let sources = await Task.detached { core.detectBrowsers(home: home) }.value
        selected = Set(Self.defaultChoice(sources).map { s in s.profiles.map { SourceRow.key(s, $0) } } ?? [])
        phase = .choosing(sources)
    }

    /// The system's default browser if it was found, else the first one.
    private static func defaultChoice(_ sources: [ImportSourceInfo]) -> ImportSourceInfo? {
        let usable = sources.filter { $0.error == nil && !$0.profiles.isEmpty }
        let defaultBrowser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
            .flatMap { Bundle(url: $0)?.bundleIdentifier }
        return usable.first { $0.bundleId != nil && $0.bundleId == defaultBrowser } ?? usable.first
    }

    private func runImport(_ sources: [ImportSourceInfo]) {
        let choices = sources.compactMap { source -> ImportChoice? in
            let ids = source.profiles.filter { selected.contains(SourceRow.key(source, $0)) }.map(\.id)
            return ids.isEmpty ? nil : ImportChoice(sourceId: source.id, profileIds: ids)
        }
        phase = .importing
        let core = store.core
        Task {
            let summary = await Task.detached { core.importBrowsers(choices: choices) }.value
            store.refresh()
            imported = true
            phase = .done(summary)
        }
    }

    /// First launch goes on to choosing a style; otherwise the sheet closes.
    private func next() {
        if request.firstLaunch {
            withAnimation(Motion.settle) { phase = .style }
        } else {
            finish()
        }
    }

    private func finish() {
        dismiss()
        guard request.firstLaunch else { return }
        store.core.finishOnboarding()
        store.refresh()
        // Starting fresh opens the address bar, as any launch with no tab does.
        if !imported && store.visibleTabID == nil { store.commandBar = .newTab }
    }

    private func summaryText(_ s: ImportSummary) -> String {
        var parts: [String] = []
        if s.spaces > 0 { parts.append(plural(s.spaces, "space")) }
        if s.pinned > 0 { parts.append(plural(s.pinned, "pinned tab or bookmark", "pinned tabs and bookmarks")) }
        if s.favorites > 0 { parts.append(plural(s.favorites, "favorite")) }
        if s.today > 0 { parts.append(plural(s.today, "open tab")) }
        return parts.isEmpty ? "Nothing to import." : "Imported " + ListFormatter.localizedString(byJoining: parts) + "."
    }
}

/// Layout (sidebar or Focus) and how strongly spaces tint the window, each
/// with a small live preview. Choices apply at once.
private struct StylePicker: View {
    @EnvironmentObject private var store: BrowserStore
    @AppStorage(TintStyle.defaultsKey) private var style = TintStyle.calm
    let color: UInt32

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Layout").font(.system(size: 13, weight: .semibold))
                HStack(spacing: 12) {
                    ForEach(SidebarLayout.allCases) { layout in
                        choice(layout.title, detail: Self.detail(layout), selected: store.layout == layout) {
                            StylePreview(layout: layout, style: style, color: color)
                        } action: { store.setLayout(layout) }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Color").font(.system(size: 13, weight: .semibold))
                HStack(spacing: 12) {
                    ForEach(TintStyle.allCases) { option in
                        choice(option.title, detail: nil, selected: style == option) {
                            StylePreview(layout: store.layout, style: option, color: color)
                        } action: { style = option }
                    }
                }
            }
        }
    }

    private static func detail(_ layout: SidebarLayout) -> String {
        switch layout {
        case .full: "Tabs and spaces on the left"
        case .compact: "Just the icons"
        case .focus: "Just the page"
        }
    }

    private func choice(_ title: String, detail: String?, selected: Bool,
                        @ViewBuilder preview: () -> some View, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                preview()
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : .primary.opacity(0.12), lineWidth: selected ? 2 : 1))
                Text(title).font(.system(size: 12, weight: .medium))
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A miniature MBGA window.
private struct StylePreview: View {
    let layout: SidebarLayout
    let style: TintStyle
    let color: UInt32
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let sidebar = layout != .focus
        let inset: CGFloat = sidebar ? 5 : 3
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: Theme.gradient(for: RGB(color), dark: dark, active: true, style: style),
                           startPoint: .top, endPoint: .bottom)
            HStack(spacing: inset) {
                if layout == .full {
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().fill(.primary.opacity(0.15)).frame(height: 6)
                        ForEach(0..<4, id: \.self) { i in
                            Capsule().fill(.primary.opacity(i == 1 ? 0.3 : 0.12)).frame(width: i == 1 ? 34 : 28, height: 4)
                        }
                    }
                    .padding(.top, 12)
                    .padding(.leading, 6)
                    .frame(width: 40, alignment: .topLeading)
                } else if layout == .compact {
                    VStack(spacing: 4) {
                        ForEach(0..<5, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1.5).fill(.primary.opacity(i == 1 ? 0.3 : 0.14)).frame(width: 7, height: 7)
                        }
                    }
                    .padding(.top, 12)
                    .frame(width: 14, alignment: .top)
                }
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.1), radius: 1, y: 0.5)
                    .padding(.vertical, inset)
                    .padding(.trailing, inset)
                    .padding(.leading, sidebar ? 0 : inset)
            }
        }
        .frame(height: 74)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// A browser with a checkbox per profile (or one for the whole browser).
private struct SourceRow: View {
    let source: ImportSourceInfo
    @Binding var selected: Set<String>

    static func key(_ source: ImportSourceInfo, _ profile: ImportProfileInfo) -> String {
        source.id + "\n" + profile.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                BrowserIcon(bundleID: source.bundleId)
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name).font(.system(size: 13, weight: .semibold))
                    if let error = source.error {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                    } else if source.profiles.count == 1 {
                        Text(describe(source.profiles[0])).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if source.error != nil, source.kind == .safari {
                    Button("Open Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    }
                    .controlSize(.small)
                } else if source.profiles.count == 1 {
                    toggle(source.profiles[0])
                }
            }
            if source.profiles.count > 1 {
                ForEach(source.profiles, id: \.id) { profile in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(profileLabel(profile)).font(.system(size: 12, weight: .medium))
                            Text(describe(profile)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        toggle(profile)
                    }
                    .padding(.leading, 38)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.5)))
        .opacity(source.error == nil ? 1 : 0.75)
    }

    private func toggle(_ profile: ImportProfileInfo) -> some View {
        let key = Self.key(source, profile)
        return Toggle("", isOn: Binding(
            get: { selected.contains(key) },
            set: { if $0 { selected.insert(key) } else { selected.remove(key) } }
        ))
        .toggleStyle(.checkbox)
        .labelsHidden()
    }

    /// "Chrome · Work" is shown as "Work" under its browser's name.
    private func profileLabel(_ profile: ImportProfileInfo) -> String {
        let prefix = source.name + " · "
        return profile.name.hasPrefix(prefix) ? String(profile.name.dropFirst(prefix.count)) : profile.name
    }

    private func describe(_ p: ImportProfileInfo) -> String {
        var parts: [String] = []
        if source.kind == .arc {
            if p.spaces > 0 { parts.append(plural(p.spaces, "space")) }
            if p.pinned > 0 { parts.append(plural(p.pinned, "pinned tab")) }
            if p.favorites > 0 { parts.append(plural(p.favorites, "favorite")) }
            if p.today > 0 { parts.append(plural(p.today, "Today tab")) }
        } else {
            if p.pinned > 0 { parts.append(plural(p.pinned, "bookmark")) }
            if p.today > 0 { parts.append(plural(p.today, "open tab")) }
        }
        return parts.joined(separator: " · ")
    }
}

private struct BrowserIcon: View {
    let bundleID: String?

    var body: some View {
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: "globe")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
    }
}

private func plural(_ n: UInt32, _ one: String, _ many: String? = nil) -> String {
    "\(n.formatted()) \(n == 1 ? one : many ?? one + "s")"
}
