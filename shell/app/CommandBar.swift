import SwiftUI

/// Arc-style command bar: type a URL or search, or jump to an open tab.
struct CommandBar: View {
    @EnvironmentObject private var store: BrowserStore
    let mode: CommandBarMode

    @State private var text = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private enum Suggestion: Hashable {
        case go(String)
        case tab(TabInfo, spaceID: UInt64)
    }

    private var suggestions: [Suggestion] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        var results: [Suggestion] = [.go(query)]
        var seen = Set<UInt64>()
        for space in store.snapshot.spaces {
            for tab in space.favorites + space.pinned.compactMap(\.tab) + space.today
            where !seen.contains(tab.id)
                && (tab.title.localizedCaseInsensitiveContains(query)
                    || tab.url.localizedCaseInsensitiveContains(query)) {
                seen.insert(tab.id)
                results.append(.tab(tab, spaceID: space.id))
                if results.count > 6 { return results }
            }
        }
        return results
    }

    var body: some View {
        let items = suggestions
        ZStack(alignment: .top) {
            Color.black.opacity(0.12)
                .contentShape(Rectangle())
                .onTapGesture { close() }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField(mode == .newTab ? "Search or Enter URL…" : "Enter URL…", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18))
                        .focused($focused)
                        .onSubmit { commit(items) }
                }
                .padding(.horizontal, 16)
                .frame(height: 54)

                if !items.isEmpty {
                    Divider()
                    VStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element) { index, item in
                            row(item, selected: index == selection)
                                .onTapGesture {
                                    selection = index
                                    commit(items)
                                }
                        }
                    }
                    .padding(6)
                }
            }
            .frame(width: 600)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
            .padding(.top, 110)
        }
        .onAppear {
            if mode == .editCurrent { text = store.visibleTab?.url ?? "" }
            focused = true
        }
        .onChange(of: text) { selection = 0 }
        .onKeyPress(.downArrow) {
            selection = min(selection + 1, max(items.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            selection = max(selection - 1, 0)
            return .handled
        }
        .onExitCommand { close() }
    }

    @ViewBuilder
    private func row(_ item: Suggestion, selected: Bool) -> some View {
        HStack(spacing: 10) {
            switch item {
            case .go(let query):
                let url = store.core.resolveInput(text: query)
                let isSearch = url != query && !url.hasPrefix("http://\(query)") && !url.hasPrefix("https://\(query)")
                Image(systemName: isSearch ? "magnifyingglass" : "globe")
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(isSearch ? "Search for “\(query)”" : "Go to \(url)").lineLimit(1)
            case .tab(let tab, _):
                FaviconImage(tab: tab)
                Text(tab.displayTitle).lineLimit(1)
                Text(tab.host).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text("Switch to Tab").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.opacity(selected ? 0.18 : 0)))
        .contentShape(Rectangle())
    }

    private func commit(_ items: [Suggestion]) {
        guard items.indices.contains(selection) else {
            store.submit(text, mode: mode)
            return
        }
        switch items[selection] {
        case .go(let query):
            store.submit(query, mode: mode)
        case .tab(let tab, let spaceID):
            store.commandBar = nil
            store.select(tab.id, in: spaceID)
        }
    }

    private func close() {
        store.commandBar = nil
    }
}
