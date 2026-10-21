import SwiftUI

/// The Compact layout: the sidebar as a narrow column of icons, Brave's
/// "rail". Favorites, pinned and Today tabs show as their favicons, the
/// selected one on a pill; the full sidebar slides out at the window edge.
struct SidebarRail: View {
    @EnvironmentObject private var store: BrowserStore

    static let width: CGFloat = 72

    var body: some View {
        let space = store.activeSpace
        VStack(spacing: 6) {
            // Room for the traffic lights, then the way back to the full sidebar.
            Color.clear.frame(height: 30).background(WindowDragArea())
            SidebarIconButton(systemName: "sidebar.left") { store.setLayout(.full) }
                .help("Full Sidebar")
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(space.favorites, id: \.id) { tab in
                        RailTab(tab: tab, space: space)
                    }
                    let pinned = space.pinned.compactMap(\.tab)
                    if !space.favorites.isEmpty && !pinned.isEmpty { RailDivider() }
                    ForEach(pinned, id: \.id) { tab in
                        RailTab(tab: tab, space: space)
                    }
                    RailDivider()
                    SidebarIconButton(systemName: "plus") {
                        store.commandBar = .newTab
                    }
                    .help("New Tab  ⌘T")
                    ForEach(space.today, id: \.id) { tab in
                        RailTab(tab: tab, space: space)
                    }
                }
                .padding(.bottom, 8)
            }
            RailSpaceSwitcher()
        }
        .padding(.bottom, 8)
        .frame(width: Self.width)
    }
}

private struct RailDivider: View {
    var body: some View {
        Rectangle().fill(.primary.opacity(0.12)).frame(width: 28, height: 1).padding(.vertical, 4)
    }
}

private struct RailTab: View {
    @EnvironmentObject private var store: BrowserStore
    let tab: TabInfo
    let space: SpaceInfo
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let active = space.activeTab == tab.id
        let dark = colorScheme == .dark
        FaviconImage(tab: tab, size: 18)
            .opacity(tab.live || active ? 1 : 0.55)
            .frame(width: 40, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? Theme.selectedFill(dark: dark) : hovering ? Theme.hoverFill(dark: dark) : .clear)
                    .shadow(color: .black.opacity(active ? (dark ? 0.3 : 0.09) : 0), radius: 1.5, y: 0.5)
            )
            .overlay(alignment: .bottomTrailing) {
                if tab.audible {
                    Equalizer(playing: store.pausedMediaTab != tab.id)
                        .frame(width: 9, height: 8)
                        .opacity(0.7)
                        .offset(x: -3, y: -3)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { store.select(tab.id, in: space.id) }
            .onHover { hovering = $0 }
            .help(tab.displayTitle)
            .contextMenu { TabMenu(tab: tab, space: space) }
    }
}

/// The active space's icon; a menu switches to another one.
private struct RailSpaceSwitcher: View {
    @EnvironmentObject private var store: BrowserStore

    var body: some View {
        let space = store.activeSpace
        Menu {
            ForEach(store.snapshot.spaces, id: \.id) { other in
                Button("\(other.icon) \(other.name)") { store.activateSpace(other.id) }
            }
            Divider()
            Button("New Space…") { store.spaceEditor = SpaceEditorRequest(spaceID: nil) }
        } label: {
            Text(space.icon.isEmpty ? "•" : space.icon).font(.system(size: 16))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 40, height: 32)
        .help(space.name)
    }
}
