import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: BrowserStore
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 260
    @AppStorage(TintStyle.matchPageKey) private var matchPage = false
    @Environment(\.colorScheme) private var colorScheme

    /// Space between the page and the window edge. Focus mode (sidebar
    /// hidden) keeps only a thin frame to drag the window by.
    private var inset: CGFloat { store.layout == .focus ? 5 : 8 }

    var body: some View {
        let chrome = !store.contentFullscreen
        let colors = store.tintColors(matchPage: matchPage, dark: colorScheme == .dark)
        // The page's corners are concentric with the window's.
        let radius = chrome ? max(store.windowRadius - inset, 6) : 0
        ZStack(alignment: .topLeading) {
            // The frame around the page (and empty sidebar space) drags the window.
            SpaceBackdrop(pager: store.pager, colors: colors)
                .overlay(WindowDragArea())

            HStack(spacing: 0) {
                if chrome && store.layout == .full {
                    Sidebar()
                        .frame(width: sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    SidebarResizeHandle(width: $sidebarWidth)
                } else if chrome && store.layout == .compact {
                    SidebarRail()
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                WebArea(container: store.webContainer, cornerRadius: radius,
                        border: chrome ? (colorScheme == .dark ? .white.withAlphaComponent(0.1)
                                                               : .black.withAlphaComponent(0.08)) : nil)
                    .background {
                        if chrome {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(.white)
                                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.07), radius: 6, y: 1)
                        }
                    }
                    .overlay {
                        if store.visibleTabID == nil && store.commandBar == nil {
                            EmptySpaceHint()
                        }
                    }
                    .overlay {
                        if let id = store.dragOverPage, let tab = store.core.tab(id: id) {
                            LittleWindowDropPreview(tab: tab)
                                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                        }
                    }
                    .padding(.vertical, chrome ? inset : 0)
                    .padding(.trailing, chrome ? inset : 0)
                    .padding(.leading, chrome && store.layout == .focus ? inset : 0)
            }

            if chrome && store.layout != .full {
                SidebarPeek(width: sidebarWidth, colors: colors)
            }

            if let toast = store.toast {
                ToastView(toast: toast)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 22)
                    .padding(.leading, !chrome ? 0 : store.layout == .full ? sidebarWidth
                             : store.layout == .compact ? SidebarRail.width : 0)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
        .sheet(item: $store.importSheet) { request in
            ImportSheet(request: request)
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

    static let range = 200.0...420.0

    private static func rubberBand(_ raw: Double) -> Double {
        if raw < range.lowerBound { return range.lowerBound - (range.lowerBound - raw) / 4 }
        if raw > range.upperBound { return range.upperBound + (raw - range.upperBound) / 4 }
        return raw
    }

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
                        width = Self.rubberBand(start + value.translation.width)
                    }
                    .onEnded { _ in
                        startWidth = nil
                        // Past a limit the sidebar stretches a little, then springs back.
                        withAnimation(Motion.settle) { width = min(max(width, Self.range.lowerBound), Self.range.upperBound) }
                    }
            )
    }
}

/// With the sidebar hidden, the sidebar slides in over the page as a floating
/// card when SidebarReveal says so.
private struct SidebarPeek: View {
    @EnvironmentObject private var store: BrowserStore
    let width: Double
    let colors: [UInt32]

    var body: some View {
        ZStack(alignment: .topLeading) {
            if store.sidebarPeek {
                Sidebar()
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .background(SpaceBackdrop(pager: store.pager, colors: colors))
                    .clipShape(RoundedRectangle(cornerRadius: max(store.windowRadius - 6, 8), style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: max(store.windowRadius - 6, 8), style: .continuous)
                        .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.28), radius: 18, x: 4)
                    .padding(6)
                    // Slides rather than resizes, so the sidebar's layout never reflows.
                    .transition(.move(edge: .leading))
            }
        }
        .animation(store.sidebarPeek ? Motion.foldOut : Motion.foldIn, value: store.sidebarPeek)
    }
}
