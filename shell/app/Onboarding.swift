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
    }

    @State private var phase = Phase.scanning
    @State private var selected: Set<String> = []

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
            }
            buttons
        }
        .padding(24)
        .frame(width: 540)
        .task { await scan() }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(request.firstLaunch ? "Welcome to MBGA" : "Import from Another Browser")
                .font(.system(size: 22, weight: .semibold))
            Text("Bring your spaces, pinned tabs, open tabs and bookmarks from the browsers on this Mac.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                Button(request.firstLaunch ? "Start Fresh" : "Cancel") { finish() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if sources.isEmpty {
                    Button("Get Started") { finish() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Import") { runImport(sources) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(selected.isEmpty)
                }
            case .done:
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
            phase = .done(summary)
        }
    }

    private func finish() {
        dismiss()
        guard request.firstLaunch else { return }
        store.core.finishOnboarding()
        store.refresh()
        // Starting fresh opens the address bar, as any launch with no tab does.
        let imported: Bool
        if case .done = phase { imported = true } else { imported = false }
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
