import SwiftUI

/// macOS sidebar scale, as in Dia, rather than Arc's larger rows.
private let rowHeight: CGFloat = 30

/// Row background shared by tabs and folders.
private struct RowBackground: View {
    let active: Bool
    let hovering: Bool
    var highlighted = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(highlighted ? Color.accentColor.opacity(0.2)
                  : active ? Theme.selectedFill(dark: dark)
                  : hovering ? Theme.hoverFill(dark: dark) : .clear)
            .shadow(color: .black.opacity(active ? (dark ? 0.3 : 0.09) : 0), radius: active ? 1.5 : 0, y: 0.5)
    }
}

private struct DropLine: View {
    let edge: DropEdge

    var body: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: 2)
            .padding(.horizontal, 6)
            .offset(y: edge == .before ? -1 : 1)
    }
}

struct TabRow: View {
    @EnvironmentObject private var store: BrowserStore
    let tab: TabInfo
    let space: SpaceInfo
    let depth: Int
    let pinned: Bool
    let target: DropTarget
    let index: Int
    @State private var hovering = false

    var body: some View {
        let active = space.activeTab == tab.id
        let key = "tab-\(tab.id)"
        let edge = store.dropIndicator?.key == key ? store.dropIndicator?.edge : nil
        HStack(spacing: 8) {
            // Sleeping tabs are dimmed: they hold no memory until selected.
            HStack(spacing: 8) {
                FaviconImage(tab: tab)
                Text(tab.displayTitle)
                    .font(.system(size: 13, weight: active ? .medium : .regular))
                    .lineLimit(1)
                    .opacity(active ? 1 : 0.85)
            }
            .opacity(tab.live || active ? 1 : 0.55)
            Spacer(minLength: 0)
            if hovering && (!pinned || tab.live) {
                Button { store.close(tab.id) } label: {
                    Image(systemName: pinned ? "minus" : "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.primary.opacity(0.08)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(pinned ? "Unload tab" : "Close tab")
            } else if store.isInLittleWindow(tab.id) {
                Image(systemName: "macwindow")
                    .font(.system(size: 10))
                    .opacity(0.5)
                    .help("Open in a little window")
            } else if tab.audible {
                Equalizer(playing: store.pausedMediaTab != tab.id)
                    .frame(width: 12, height: 11)
                    .opacity(0.6)
                    .help("Playing")
            }
        }
        .padding(.leading, 10 + CGFloat(depth) * 14)
        .padding(.trailing, 6)
        .frame(height: rowHeight)
        .background(RowBackground(active: active, hovering: hovering))
        .overlay(alignment: edge == .before ? .top : .bottom) {
            if let edge { DropLine(edge: edge) }
        }
        .contentShape(Rectangle())
        // A plain tap gesture loses quick clicks to the drag recognizer.
        .simultaneousGesture(TapGesture().onEnded { store.select(tab.id, in: space.id) })
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .onDrag({ store.dragProvider(for: tab.id, url: tab.url) }, preview: { TabDragPreview(tab: tab) })
        .onDrop(of: [.sidebarItem, .url], delegate: ItemDropDelegate(
            store: store, key: key, target: target, index: index, folderID: nil))
        .contextMenu { TabMenu(tab: tab, space: space) }
    }
}

struct FolderRow: View {
    @EnvironmentObject private var store: BrowserStore
    let row: PinnedRow
    let space: SpaceInfo
    @State private var hovering = false
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        let key = "folder-\(row.id)"
        let edge = store.dropIndicator?.key == key ? store.dropIndicator?.edge : nil
        let renaming = store.renamingFolder == row.id
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .rotationEffect(.degrees(row.expanded ? 90 : 0))
                .frame(width: 10)
                .opacity(0.45)
            Image(systemName: row.expanded ? "folder" : "folder.fill")
                .font(.system(size: 12))
                .opacity(0.7)
            if renaming {
                TextField("Folder name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onAppear {
                        name = row.folderName ?? ""
                        focused = true
                    }
                    .onSubmit { store.renameFolder(row.id, to: name) }
                    .onExitCommand { store.renamingFolder = nil }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused && store.renamingFolder == row.id {
                            store.renameFolder(row.id, to: name)
                        }
                    }
            } else {
                Text(row.folderName ?? "Folder")
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .opacity(0.8)
            }
            Spacer(minLength: 0)
            if !row.expanded && row.childCount > 0 {
                Text("\(row.childCount)")
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .padding(.horizontal, 6)
                    .frame(height: 17)
                    .background(Capsule().fill(.primary.opacity(0.08)))
                    .opacity(0.6)
            }
        }
        .padding(.leading, 8 + CGFloat(row.depth) * 14)
        .padding(.trailing, 8)
        .frame(height: rowHeight)
        .background(RowBackground(active: false, hovering: hovering, highlighted: edge == .into))
        .overlay(alignment: edge == .before ? .top : .bottom) {
            if let edge, edge != .into { DropLine(edge: edge) }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            if !renaming { store.setFolder(row.id, expanded: !row.expanded) }
        })
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .onDrag { store.dragProvider(for: row.id, url: nil) }
        .onDrop(of: [.sidebarItem, .url], delegate: ItemDropDelegate(
            store: store, key: key, target: .pinned(spaceId: space.id, folderId: row.parentId),
            index: Int(row.index), folderID: row.id))
        .contextMenu {
            Button("Rename") { store.renamingFolder = row.id }
            Button("New Folder Inside") { store.newFolder(in: space.id, parent: row.id) }
            Divider()
            Button("Delete Folder and Tabs", role: .destructive) { store.deleteFolder(row.id) }
        }
    }
}

struct TabMenu: View {
    @EnvironmentObject private var store: BrowserStore
    let tab: TabInfo
    let space: SpaceInfo

    var body: some View {
        let favorite = store.isFavorite(tab.id, in: space)
        let pinned = store.isPinned(tab.id, in: space)
        if favorite {
            Button("Remove from Favorites") { store.togglePin(tab.id, in: space) }
        } else {
            Button("Add to Favorites") { store.addFavorite(tab.id) }
            Button(pinned ? "Unpin Tab" : "Pin Tab") { store.togglePin(tab.id, in: space) }
        }
        let others = store.snapshot.spaces.filter { $0.id != space.id }
        if !favorite && !others.isEmpty {
            Menu("Move to Space") {
                ForEach(others, id: \.id) { other in
                    Button("\(other.icon) \(other.name)") {
                        store.move(tab.id, to: .today(spaceId: other.id), index: 0)
                    }
                }
            }
        }
        Divider()
        if let site = tab.site {
            Toggle("Keep \(site) Awake", isOn: Binding(
                get: { tab.keepAwake },
                set: { store.setKeepAwake($0, for: tab) }))
            if store.blockAds {
                Toggle("Allow Ads on \(site)", isOn: Binding(
                    get: { tab.adsAllowed },
                    set: { store.setAdsAllowed($0, for: tab) }))
            }
        }
        Button("Copy Link") { store.copyLink(tab.url) }
        Button("Duplicate") { store.duplicate(tab, in: space) }
        Button(store.isInLittleWindow(tab.id) ? "Show Little Window" : "Open in Little Window") {
            store.openInLittleWindow(tab.id)
        }
        Divider()
        if tab.live && !(favorite || pinned) {
            Button("Sleep Tab") { store.sleep(tab.id) }
        }
        Button(favorite || pinned ? "Unload Tab" : "Close Tab") { store.close(tab.id) }
    }
}

/// A drop target that is nearly invisible until something is dragged over it.
struct DropZone: View {
    @EnvironmentObject private var store: BrowserStore
    let key: String
    let label: String
    let target: DropTarget
    let index: Int

    var body: some View {
        let active = store.dropIndicator?.key == key
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .opacity(active ? 0.6 : 0)
            .frame(maxWidth: .infinity)
            .frame(height: active ? rowHeight : 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .opacity(active ? 0.35 : 0)
            )
            .contentShape(Rectangle())
            .animation(Motion.quick, value: active)
            .onDrop(of: [.sidebarItem, .url], delegate: ItemDropDelegate(
                store: store, key: key, target: target, index: index, folderID: nil, fixedEdge: .before))
    }
}

/// Turns a drop position on a row into a move: before/after the row, or into
/// it for folders.
struct ItemDropDelegate: DropDelegate {
    let store: BrowserStore
    let key: String
    let target: DropTarget
    let index: Int
    let folderID: UInt64?
    var horizontal = false
    var fixedEdge: DropEdge?
    var length: CGFloat = rowHeight

    private func edge(_ info: DropInfo) -> DropEdge {
        if let fixedEdge { return fixedEdge }
        let t = (horizontal ? info.location.x : info.location.y) / max(length, 1)
        if folderID != nil { return t < 0.25 ? .before : t > 0.75 ? .after : .into }
        return t < 0.5 ? .before : .after
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.sidebarItem, .url])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        // Rows that slide under the pointer after a drop still get a hover
        // update; ignore it once the button is up.
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return nil }
        let indicator = DropIndicator(key: key, edge: edge(info))
        if store.dropIndicator != indicator {
            store.dropIndicator = indicator
            // A light tick on Force Touch trackpads as the drop spot moves.
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .drawCompleted)
        }
        return DropProposal(operation: info.hasItemsConforming(to: [.sidebarItem]) ? .move : .copy)
    }

    func dropExited(info: DropInfo) {
        if store.dropIndicator?.key == key { store.dropIndicator = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        let edge = edge(info)
        if ProcessInfo.processInfo.environment["MBGA_DEBUG_EVENTS"] != nil {
            NSLog("drop on %@ at %@ -> %@", key, NSStringFromPoint(info.location), String(describing: edge))
        }
        if edge == .into, let folderID, case .pinned(let spaceId, _) = target {
            return store.performDrop(info, target: .pinned(spaceId: spaceId, folderId: folderID), index: Int(UInt32.max))
        }
        return store.performDrop(info, target: target, index: edge == .after ? index + 1 : index)
    }
}
