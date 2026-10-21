import SwiftUI

/// A brief pill at the bottom of the page: "Archived 6 tabs · Undo".
struct ToastView: View {
    @EnvironmentObject private var store: BrowserStore
    let toast: Toast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        HStack(spacing: 8) {
            Image(systemName: toast.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(toast.message)
                .font(.system(size: 13, weight: .medium))
            if toast.undoable {
                Divider().frame(height: 14)
                Button("Undo") { store.undoClose() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("⌘Z").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Capsule().fill(dark ? Color(white: 0.2) : .white))
        .overlay(Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(dark ? 0.4 : 0.14), radius: 14, y: 6)
        .onTapGesture { store.dismissToast() }
    }
}

/// Media playing in a tab you're not looking at, at the bottom of the
/// sidebar: what's playing, play/pause, and a click jumps back to it.
struct MiniPlayer: View {
    @EnvironmentObject private var store: BrowserStore
    let tab: TabInfo
    let space: SpaceInfo
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let paused = store.pausedMediaTab == tab.id
        HStack(spacing: 10) {
            FaviconImage(tab: tab, size: 20)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(tab.displayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Equalizer(playing: !paused)
                        .frame(width: 11, height: 10)
                        .opacity(0.55)
                }
                Text(space.id == store.activeSpace.id ? tab.host : "\(space.icon) \(space.name)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { store.toggleMedia(tab.id) } label: {
                Image(systemName: paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 12))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(paused ? "Play" : "Pause")
            if paused && hovering {
                Button { store.dismissMedia() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Hide")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.controlFill(dark: colorScheme == .dark, hovering: hovering)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { store.select(tab.id, in: space.id) }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Offered once, when old Today tabs pile up: tidy them now, every day, or
/// not at all. Nothing is lost: Undo and Recently Closed bring tabs back.
struct CleanupCard: View {
    @EnvironmentObject private var store: BrowserStore
    let count: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(count) tabs haven't been touched in a while")
                    .font(.system(size: 12.5, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("MBGA can tidy them up. You can always bring them back.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                Button("Not Now") { store.answerCleanup(.notNow) }
                Spacer(minLength: 0)
                Button("Once") { store.answerCleanup(.once) }
                Button("Daily") { store.answerCleanup(.daily) }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.controlFill(dark: colorScheme == .dark)))
        .padding(.vertical, 4)
        .transition(.opacity)
    }
}

extension AnyTransition {
    /// Today tabs dropping away toward Clear when they are tidied up.
    static var archive: AnyTransition {
        .asymmetric(insertion: .identity,
                    removal: .scale(scale: 0.7, anchor: .bottom).combined(with: .offset(y: 24)).combined(with: .opacity))
    }
}
