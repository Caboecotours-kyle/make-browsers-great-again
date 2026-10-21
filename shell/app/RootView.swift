import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: BrowserStore
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 260

    var body: some View {
        let chrome = !store.contentFullscreen
        let colors = store.snapshot.spaces.map(\.color)
        ZStack(alignment: .topLeading) {
            SpaceBackdrop(pager: store.pager, colors: colors)

            HStack(spacing: 0) {
                if chrome && store.sidebarVisible {
                    Sidebar()
                        .frame(width: sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    SidebarResizeHandle(width: $sidebarWidth)
                }
                WebArea(container: store.webContainer, cornerRadius: chrome ? 9 : 0)
                    .background {
                        if chrome {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(.white)
                                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                        }
                    }
                    .overlay {
                        if store.visibleTabID == nil && store.commandBar == nil {
                            EmptySpaceHint()
                        }
                    }
                    .padding(.vertical, chrome ? 8 : 0)
                    .padding(.trailing, chrome ? 8 : 0)
                    .padding(.leading, chrome && !store.sidebarVisible ? 8 : 0)
            }

            if chrome && !store.sidebarVisible {
                SidebarPeek(width: sidebarWidth, colors: colors)
            }

            if let mode = store.commandBar {
                CommandBar(mode: mode)
            }
        }
        .ignoresSafeArea()
        .sheet(item: $store.spaceEditor) { request in
            SpaceEditor(request: request)
                .environmentObject(store)
        }
    }
}

private struct EmptySpaceHint: View {
    @EnvironmentObject private var store: BrowserStore

    var body: some View {
        VStack(spacing: 8) {
            Text(store.activeSpace.icon).font(.system(size: 40))
            Text("No tab open in \(store.activeSpace.name)")
                .font(.system(size: 15, weight: .medium))
            Button("Search or Enter URL  ⌘T") { store.commandBar = .newTab }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.black.opacity(0.7))
    }
}

private struct SidebarResizeHandle: View {
    @Binding var width: Double
    @State private var startWidth: Double?

    var body: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = startWidth ?? width
                        startWidth = start
                        width = min(max(start + value.translation.width, 200), 420)
                    }
                    .onEnded { _ in startWidth = nil }
            )
    }
}

/// With the sidebar hidden, hovering the left edge slides it in over the page.
private struct SidebarPeek: View {
    @EnvironmentObject private var store: BrowserStore
    let width: Double
    let colors: [UInt32]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: 12)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onHover { if $0 { store.sidebarPeek = true } }

            if store.sidebarPeek {
                Sidebar()
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .background(SpaceBackdrop(pager: store.pager, colors: colors))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 18, x: 4)
                    .padding(6)
                    .onHover { if !$0 { store.sidebarPeek = false } }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: store.sidebarPeek)
    }
}
