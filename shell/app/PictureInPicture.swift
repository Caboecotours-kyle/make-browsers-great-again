import Foundation

extension BrowserStore {
    /// Shows the visible tab's page. The page left is asked whether it still
    /// plays sound, so a tab left playing shows the mini player right away
    /// rather than at the next idle check, and the video it plays carries on
    /// in a picture-in-picture window, unless the tab went to a little window.
    /// It keeps drawing, out of sight, until the window is open, as a hidden
    /// page pauses a muted video. A page coming on screen, even the same tab's
    /// moved here from another window, takes back a video it had in the window.
    func showPage(_ visible: UInt64?, leaving previous: UInt64?, crossfade: Bool) {
        if previous != visible, let previous, let left = views[previous] {
            left.probeMedia()
            if !isInLittleWindow(previous) {
                let release = webContainer.hold(left)
                left.enterPictureInPicture { MainActor.assumeIsolated { release() } }
            }
        }
        let page = visible.flatMap { views[$0] }
        if let page, page !== webContainer.current { page.exitPictureInPicture() }
        webContainer.show(page, crossfade: crossfade)
    }
}
