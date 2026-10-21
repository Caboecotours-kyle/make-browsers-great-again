import SwiftUI

struct Sidebar: View {
    @EnvironmentObject private var store: BrowserStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidebarToolbar()
            AddressPill()
            FavoritesGrid(space: store.activeSpace)
            SpacePager(pager: store.pager)
            if let media = store.mediaTab {
                MiniPlayer(tab: media.tab, space: media.space)
            }
            SidebarBottomBar()
        }
        .animation(Motion.settle, value: store.mediaTab?.tab.id)
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            store.pager.sidebarFrame = frame
        }
    }
}

struct SidebarIconButton: View {
    let systemName: String
    var disabled = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering && !disabled ? Theme.hoverFill(dark: colorScheme == .dark) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.35 : 0.8)
        .disabled(disabled)
        .onHover { hovering = $0 }
    }
}

private struct SidebarToolbar: View {
    @EnvironmentObject private var store: BrowserStore

    var body: some View {
        HStack(spacing: 2) {
            // Room for the window's traffic lights.
            Spacer().frame(width: 66)
            SidebarIconButton(systemName: "sidebar.left") { store.toggleSidebar() }
            Spacer(minLength: 0)
            SidebarIconButton(systemName: "arrow.left", disabled: !store.nav.canGoBack) { store.goBack() }
            SidebarIconButton(systemName: "arrow.right", disabled: !store.nav.canGoForward) { store.goForward() }
            SidebarIconButton(systemName: store.nav.isLoading ? "xmark" : "arrow.clockwise",
                              disabled: store.visibleTabID == nil) { store.reloadOrStop() }
        }
        .frame(height: 30)
        .padding(.top, 6)
        .background(WindowDragArea())
    }
}

private struct AddressPill: View {
    @EnvironmentObject private var store: BrowserStore
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tab = store.visibleTab
        Button { store.commandBar = tab == nil ? .newTab : .editCurrent } label: {
            HStack(spacing: 6) {
                if let tab, tab.url.hasPrefix("https://") {
                    Image(systemName: "lock.fill").font(.system(size: 10)).opacity(0.5)
                }
                Text(tab.map(\.host) ?? "Search or Enter URL…")
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .opacity(tab == nil ? 0.5 : 0.85)
                Spacer(minLength: 0)
                if store.nav.isLoading {
                    ProgressView().controlSize(.mini)
                }
                if let tab, let blocked = store.blockedCounts[tab.id], blocked > 0 {
                    // What the blocker kept off this page, quietly.
                    HStack(spacing: 3) {
                        Image(systemName: "shield.lefthalf.filled").font(.system(size: 10))
                        Text("\(blocked)").font(.system(size: 11, weight: .medium).monospacedDigit())
                    }
                    .opacity(0.5)
                    .help("\(blocked) ads and trackers blocked on this page")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.controlFill(dark: colorScheme == .dark, hovering: hovering))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Favorites belong to the profile, so every space using it shows the same grid.
private struct FavoritesGrid: View {
    @EnvironmentObject private var store: BrowserStore
    let space: SpaceInfo
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        let target = DropTarget.favorites(profileId: space.profileId)
        if space.favorites.isEmpty {
            // Invisible until a tab is dragged over it.
            DropZone(key: "fav-empty-\(space.profileId)", label: "Drop to add to Favorites",
                     target: target, index: 0)
        } else {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(space.favorites.enumerated()), id: \.element.id) { index, tab in
                    FavoriteTile(tab: tab, space: space, index: index)
                }
            }
        }
    }
}

private struct FavoriteTile: View {
    @EnvironmentObject private var store: BrowserStore
    let tab: TabInfo
    let space: SpaceInfo
    let index: Int
    @State private var hovering = false
    @State private var width: CGFloat = 50
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let active = space.activeTab == tab.id
        let dark = colorScheme == .dark
        // The selected favorite lights up in its site's color, as in Dia.
        let brand = active ? tab.faviconPath.flatMap { FaviconCache.shared.brandColor(atPath: $0) } : nil
        let key = "fav-\(tab.id)"
        let indicator = store.dropIndicator?.key == key ? store.dropIndicator?.edge : nil
        FaviconImage(tab: tab, size: 18)
            .opacity(tab.live || active ? 1 : 0.6)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(active ? Theme.selectedFill(dark: dark) : Theme.controlFill(dark: dark, hovering: hovering))
                    .overlay {
                        if let brand {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(brand.color.opacity(dark ? 0.32 : 0.2))
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(brand.color.opacity(dark ? 0.6 : 0.45), lineWidth: 1)
                        }
                    }
                    .shadow(color: .black.opacity(active ? (dark ? 0.3 : 0.09) : 0), radius: 1.5, y: 0.5)
            )
            .overlay(alignment: indicator == .before ? .leading : .trailing) {
                if indicator != nil {
                    Capsule().fill(Color.accentColor).frame(width: 3).padding(.vertical, 6).offset(x: indicator == .before ? -5 : 5)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .contentShape(Rectangle())
            // A plain tap gesture loses quick clicks to the drag recognizer.
            .simultaneousGesture(TapGesture().onEnded { store.select(tab.id, in: space.id) })
            .onHover { hovering = $0 }
            .help(tab.displayTitle)
            .onDrag { store.dragProvider(for: tab.id, url: tab.url) }
            .onDrop(of: [.sidebarItem, .url], delegate: ItemDropDelegate(
                store: store, key: key, target: .favorites(profileId: space.profileId),
                index: index, folderID: nil, horizontal: true, length: width))
            .contextMenu { TabMenu(tab: tab, space: space) }
    }
}

/// Swipeable pages, one per space. Only the pages next to the current
/// position are built.
private struct SpacePager: View {
    @EnvironmentObject private var store: BrowserStore
    @ObservedObject var pager: PagerModel
    private let gap: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let stride = geo.size.width + gap
            ZStack(alignment: .topLeading) {
                ForEach(Array(store.snapshot.spaces.enumerated()), id: \.element.id) { index, space in
                    let offset = CGFloat(index) - pager.position
                    if abs(offset) < 1.2 {
                        SpacePage(space: space)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .offset(x: offset * stride)
                    }
                }
            }
            .onAppear { pager.pageWidth = stride }
            .onChange(of: geo.size.width) { pager.pageWidth = stride }
        }
    }
}

private struct SpacePage: View {
    @EnvironmentObject private var store: BrowserStore
    let space: SpaceInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SpaceHeader(space: space)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(space.pinned, id: \.id) { row in
                        if let tab = row.tab {
                            TabRow(tab: tab, space: space, depth: Int(row.depth), pinned: true,
                                   target: .pinned(spaceId: space.id, folderId: row.parentId),
                                   index: Int(row.index))
                        } else {
                            FolderRow(row: row, space: space)
                        }
                    }
                    if space.pinned.isEmpty {
                        DropZone(key: "pin-empty-\(space.id)", label: "Drop to pin",
                                 target: .pinned(spaceId: space.id, folderId: nil), index: 0)
                    }
                    TodayDivider(space: space)
                    if space.id == store.activeSpace.id, let count = store.cleanupOffer {
                        CleanupCard(count: count)
                    }
                    NewTabRow(space: space)
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(space.today.enumerated()), id: \.element.id) { index, tab in
                            TabRow(tab: tab, space: space, depth: 0, pinned: false,
                                   target: .today(spaceId: space.id), index: index)
                                .transition(.archive)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }
}

private struct SpaceHeader: View {
    @EnvironmentObject private var store: BrowserStore
    let space: SpaceInfo

    var body: some View {
        HStack(spacing: 6) {
            Text(space.icon.isEmpty ? "•" : space.icon).font(.system(size: 14))
            Text(space.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .opacity(0.8)
            Spacer(minLength: 0)
            if store.snapshot.profiles.count > 1 {
                Text(store.profileName(space.profileId))
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.primary.opacity(0.08)))
                    .opacity(0.8)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 24)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.spaceEditor = SpaceEditorRequest(spaceID: space.id) }
        .contextMenu {
            Button("Edit Space…") { store.spaceEditor = SpaceEditorRequest(spaceID: space.id) }
            Button("New Folder") { store.newFolder(in: space.id) }
            Menu("Profile") {
                ForEach(store.snapshot.profiles, id: \.id) { profile in
                    Toggle(profile.name, isOn: Binding(
                        get: { space.profileId == profile.id },
                        set: { if $0 { store.setProfile(profile.id, for: space.id) } }))
                }
            }
            Divider()
            Button("Delete Space", role: .destructive) { store.deleteSpace(space.id) }
                .disabled(store.snapshot.spaces.count <= 1)
        }
    }
}

private struct TodayDivider: View {
    @EnvironmentObject private var store: BrowserStore
    let space: SpaceInfo

    var body: some View {
        let key = "today-top-\(space.id)"
        HStack(spacing: 8) {
            Rectangle().fill(.primary.opacity(0.12)).frame(height: 1)
            if !space.today.isEmpty {
                Button { store.clearToday(space.id) } label: {
                    Label("Clear", systemImage: "arrow.down")
                        .font(.system(size: 11, weight: .medium))
                        .labelStyle(.titleAndIcon)
                        .opacity(0.55)
                }
                .buttonStyle(.plain)
                .help("Archive all Today tabs in this space")
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(store.dropIndicator?.key == key ? Color.accentColor.opacity(0.15) : .clear)
        .onDrop(of: [.sidebarItem, .url], delegate: ItemDropDelegate(
            store: store, key: key, target: .today(spaceId: space.id), index: 0,
            folderID: nil, fixedEdge: .before))
    }
}

private struct NewTabRow: View {
    @EnvironmentObject private var store: BrowserStore
    let space: SpaceInfo
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus").font(.system(size: 12, weight: .medium)).frame(width: 16)
            Text("New Tab").font(.system(size: 13))
            Spacer()
        }
        .opacity(0.6)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(hovering ? Theme.hoverFill(dark: colorScheme == .dark) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            store.activateSpace(space.id)
            store.commandBar = .newTab
        }
    }
}

private struct SidebarBottomBar: View {
    @EnvironmentObject private var store: BrowserStore

    var body: some View {
        HStack(spacing: 4) {
            SidebarIconButton(systemName: "arrow.down.circle") {
                if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                    NSWorkspace.shared.open(downloads)
                }
            }
            .help("Downloads")
            Spacer(minLength: 4)
            // Most people use one space (5.5% of Arc's daily users used
            // several), so the switcher only appears once there is a second.
            if store.snapshot.spaces.count > 1 {
                // Icons shrink, then turn into dots, then scroll, so many spaces
                // never make the bar (and with it the sidebar) wider.
                ViewThatFits(in: .horizontal) {
                    spaceDots(size: 24, icons: true)
                    spaceDots(size: 18, icons: true)
                    ScrollView(.horizontal, showsIndicators: false) { spaceDots(size: 14, icons: false) }
                }
                Spacer(minLength: 4)
            }
            Menu {
                Button("New Space…") { store.spaceEditor = SpaceEditorRequest(spaceID: nil) }
                Button("New Folder") { store.newFolder() }
            } label: {
                Image(systemName: "plus").font(.system(size: 13, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 28, height: 24)
            .opacity(0.8)
        }
        .frame(height: 28)
    }

    private func spaceDots(size: CGFloat, icons: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(store.snapshot.spaces, id: \.id) { space in
                SpaceDot(space: space, active: space.id == store.snapshot.activeSpace, size: size, icon: icons)
            }
        }
    }
}

private struct SpaceDot: View {
    @EnvironmentObject private var store: BrowserStore
    let space: SpaceInfo
    let active: Bool
    var size: CGFloat = 24
    /// False shows a dot even for spaces with an icon.
    var icon = true
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let key = "space-\(space.id)"
        Group {
            if space.icon.isEmpty || !icon {
                Circle().fill(.primary).frame(width: 6, height: 6)
            } else {
                Text(space.icon).font(.system(size: size * 0.54))
            }
        }
        .frame(width: size, height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(store.dropIndicator?.key == key ? Theme.controlFill(dark: colorScheme == .dark, hovering: true)
                      : hovering ? Theme.hoverFill(dark: colorScheme == .dark) : .clear)
        )
        .opacity(active ? 1 : 0.45)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { store.activateSpace(space.id) }
        .help(space.name)
        .onDrop(of: [.sidebarItem, .url], delegate: ItemDropDelegate(
            store: store, key: key, target: .today(spaceId: space.id), index: 0,
            folderID: nil, fixedEdge: .before))
        .contextMenu {
            Button("Edit Space…") { store.spaceEditor = SpaceEditorRequest(spaceID: space.id) }
        }
    }
}
