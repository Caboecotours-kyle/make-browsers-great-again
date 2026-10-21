import AppKit
import SwiftUI

struct RGB: Equatable {
    var r, g, b: Double

    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    func mixed(with other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    var color: Color { Color(red: r, green: g, blue: b) }

    static let white = RGB(0xFFFFFF)
    static let black = RGB(0x000000)
}

enum Theme {
    static let spaceColors: [UInt32] = [
        0x8B5CF6, 0x3B82F6, 0x10B981, 0xF59E0B, 0xEF4444, 0xEC4899, 0x14B8A6, 0x6366F1,
    ]

    /// Space color at a fractional pager position, blending neighbours.
    static func blend(_ colors: [UInt32], at position: CGFloat) -> RGB {
        guard !colors.isEmpty else { return RGB(spaceColors[0]) }
        let clamped = min(max(position, 0), CGFloat(colors.count - 1))
        let lower = Int(clamped.rounded(.down))
        let upper = min(lower + 1, colors.count - 1)
        return RGB(colors[lower]).mixed(with: RGB(colors[upper]), Double(clamped - CGFloat(lower)))
    }

    static func gradient(for base: RGB, dark: Bool) -> [Color] {
        dark
            ? [base.mixed(with: .black, 0.55).color, base.mixed(with: .black, 0.72).color]
            : [base.mixed(with: .white, 0.62).color, base.mixed(with: .white, 0.42).color]
    }
}

/// Window background tinted with the current space's color. Animatable so
/// the tint follows the pager continuously during swipes and springs.
struct SpaceBackdrop: View {
    @ObservedObject var pager: PagerModel
    let colors: [UInt32]

    var body: some View {
        BackdropGradient(position: pager.position, colors: colors)
    }
}

private struct BackdropGradient: View, Animatable {
    var position: CGFloat
    let colors: [UInt32]
    @Environment(\.colorScheme) private var colorScheme

    var animatableData: CGFloat {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        LinearGradient(
            colors: Theme.gradient(for: Theme.blend(colors, at: position), dark: colorScheme == .dark),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension TabInfo {
    var host: String {
        guard let host = URL(string: url)?.host() else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if url.isEmpty || url == "about:blank" { return "New Tab" }
        return host
    }
}

/// Decoded favicons, keyed by the file the core stored them in.
@MainActor
final class FaviconCache {
    static let shared = FaviconCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(atPath path: String) -> NSImage? {
        if let image = cache.object(forKey: path as NSString) { return image }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }

    func invalidate(_ path: String) {
        cache.removeObject(forKey: path as NSString)
    }
}

struct FaviconImage: View {
    let tab: TabInfo
    var size: CGFloat = 16

    var body: some View {
        if let path = tab.faviconPath, let image = FaviconCache.shared.image(atPath: path) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        } else {
            Image(systemName: "globe")
                .font(.system(size: size * 0.8))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}

/// Lets the user drag the window by an otherwise empty area.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}
