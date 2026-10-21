import Foundation

/// Ad and tracker blocking: the core decides, the engine asks it about every
/// request on its network thread, and the filter lists are kept current here.
enum AdBlocking {
    /// How old a downloaded list may get before it is fetched again.
    private static let maxAge: TimeInterval = 4 * 86_400

    /// Hands the core's filter to the engine. Call before the first web view
    /// is created. The closures run on the engine's network thread, so they
    /// only touch the core, which is thread-safe.
    nonisolated static func install(core: BrowserCore) {
        MBEngine.setRequestFilter({ url, page, kind in
            core.shouldBlock(url: url, page: page, kind: kind)
        }, pageScript: { page in
            core.pageScript(page: page)
        }, pageReply: { page, report in
            core.cosmeticReply(page: page, report: report)
        })
    }

    /// Reloads the engine, for after editing My Filters.
    nonisolated static func reload(core: BrowserCore) async -> Bool {
        await Task.detached(priority: .userInitiated) { core.loadFilters() }.value
    }

    /// Loads the compiled engine if it is up to date (tens of milliseconds),
    /// so the first pages after launch are filtered too. Call before the
    /// first web view is created.
    nonisolated static func loadCached(core: BrowserCore) -> Bool {
        core.loadCachedFilters()
    }

    /// Compiles the lists if the cache wasn't usable, then refreshes stale
    /// lists in the background and reloads the engine if any changed.
    nonisolated static func updateLists(core: BrowserCore, loaded: Bool) {
        Task.detached(priority: .utility) {
            if !loaded { _ = core.loadFilters() }
            let dir = URL(fileURLWithPath: core.filterDir(), isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var changed = false
            for list in core.filterLists() {
                let file = dir.appendingPathComponent(list.fileName)
                let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                guard modified.map({ Date().timeIntervalSince($0) > maxAge }) ?? true,
                      let url = URL(string: list.url),
                      let (data, response) = try? await URLSession.shared.data(from: url),
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      // A real list is hundreds of kilobytes; anything tiny
                      // is an error page.
                      data.count > 10_000
                else { continue }
                if (try? data.write(to: file, options: .atomic)) != nil { changed = true }
            }
            if changed { _ = core.loadFilters() }
        }
    }
}
