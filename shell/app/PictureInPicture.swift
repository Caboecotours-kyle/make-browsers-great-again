import Foundation

extension BrowserStore {
    /// From one tab to another: the page left is asked whether it still plays
    /// sound, so a tab left playing shows the mini player right away rather
    /// than at the next idle check, and the video it plays carries on in a
    /// picture-in-picture window, unless the tab went to a little window. The
    /// page shown takes back a video it had in the window.
    func handOffMedia(from previous: UInt64?, to visible: UInt64?) {
        if let previous, let view = views[previous] {
            view.probeMedia()
            if !isInLittleWindow(previous) { view.enterPictureInPicture() }
        }
        if let visible { views[visible]?.exitPictureInPicture() }
    }
}
