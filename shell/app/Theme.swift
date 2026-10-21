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

    /// The window's own background, which space colors are washed toward.
    static func neutral(dark: Bool) -> RGB {
        dark ? RGB(0x1E1E20) : RGB(0xEFEEEC)
    }

    /// A vertical wash: the space color at the top fading toward the neutral
    /// window background, and further still while the window is inactive,
    /// as system materials do.
    static func gradient(for base: RGB, dark: Bool, active: Bool, style: TintStyle) -> [Color] {
        // Share of the neutral background mixed in at the top and bottom.
        var (top, bottom): (Double, Double) = switch style {
        case .vivid: dark ? (0.42, 0.6) : (0.4, 0.58)
        case .calm: dark ? (0.62, 0.8) : (0.6, 0.8)
        case .neutral: (0.94, 0.97)
        }
        if !active {
            top += (1 - top) * 0.5
            bottom += (1 - bottom) * 0.5
        }
        let neutral = neutral(dark: dark)
        return [base.mixed(with: neutral, top).color, base.mixed(with: neutral, bottom).color]
    }

    /// Fills for controls drawn on the tinted window background. Hover is
    /// always weaker than selection, in both appearances.
    static func hoverFill(dark: Bool) -> Color {
        dark ? .white.opacity(0.07) : .white.opacity(0.3)
    }

    static func controlFill(dark: Bool, hovering: Bool = false) -> Color {
        dark ? .white.opacity(hovering ? 0.1 : 0.06) : .white.opacity(hovering ? 0.55 : 0.4)
    }

    /// The selected tab: an opaque pill that stands out in both appearances.
    static func selectedFill(dark: Bool) -> Color {
        dark ? Color(red: 0.3, green: 0.3, blue: 0.32) : .white
    }
}

/// How strongly a space's color tints the window.
enum TintStyle: String, CaseIterable, Identifiable {
    case vivid, calm, neutral

    static let defaultsKey = "tintStyle"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vivid: "Vivid"
        case .calm: "Calm"
        case .neutral: "Neutral"
        }
    }
}

/// The app's few animations. Moves between two places glide, things that
/// appear settle, hover feedback is quick, and the hidden sidebar folds out
/// and back in at the speed Arc and Dia use (about 95 ms out, 70 ms back).
/// Actions done hundreds of times a day (new tab, close tab, switching)
/// are not animated at all. With Reduce Motion everything is instant.
enum Motion {
    static var quick: Animation? { reduced ? nil : .easeOut(duration: 0.14) }
    static var glide: Animation? { reduced ? nil : .spring(response: 0.34, dampingFraction: 0.82) }
    static var settle: Animation? { reduced ? nil : .spring(response: 0.3, dampingFraction: 0.86) }
    static var foldOut: Animation? { reduced ? nil : .spring(response: 0.14, dampingFraction: 0.86) }
    static var foldIn: Animation? { reduced ? nil : .spring(response: 0.13, dampingFraction: 1) }

    private static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

extension NSWindow {
    /// The window's corner radius: 16 pt for titlebar windows on macOS 26
    /// (26 pt with a toolbar) and 10 pt before. AppKit has no public API for
    /// it, so read the private value when it exists.
    var systemCornerRadius: CGFloat {
        let selector = Selector(("_cornerRadius"))
        if responds(to: selector), let radius = value(forKey: "_cornerRadius") as? CGFloat, radius > 0 {
            return radius
        }
        if #available(macOS 26, *) { return 16 }
        return 10
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
    @Environment(\.controlActiveState) private var activeState
    @AppStorage(TintStyle.defaultsKey) private var style = TintStyle.calm

    var animatableData: CGFloat {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        LinearGradient(
            colors: Theme.gradient(for: Theme.blend(colors, at: position), dark: colorScheme == .dark,
                                   active: activeState != .inactive, style: style),
            startPoint: .top,
            endPoint: .bottom
        )
        .animation(Motion.quick, value: activeState)
    }
}

extension TabInfo {
    var host: String {
        guard let host = URL(string: url)?.host() else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The site for "Keep … Awake", nil for pages without a host.
    var site: String? {
        guard let host = URL(string: url)?.host(), !host.isEmpty else { return nil }
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
    /// Brand colors sampled from favicons; a stored nil means the icon has none.
    private var colors: [String: RGB?] = [:]

    func image(atPath path: String) -> NSImage? {
        if let image = cache.object(forKey: path as NSString) { return image }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }

    func invalidate(_ path: String) {
        cache.removeObject(forKey: path as NSString)
        colors[path] = nil
    }

    /// The icon's most prominent saturated color (Spotify's green, YouTube's
    /// red), or nil for monochrome icons such as GitHub's.
    func brandColor(atPath path: String) -> RGB? {
        if let known = colors[path] { return known }
        let color = image(atPath: path).flatMap(Self.dominantColor)
        colors[path] = color
        return color
    }

    private static func dominantColor(_ image: NSImage) -> RGB? {
        let size = 16
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.bitmapData else { return nil }
        // Average the opaque, saturated pixels, weighted by saturation.
        var r = 0.0, g = 0.0, b = 0.0, weight = 0.0
        for i in 0..<(size * size) {
            let p = data.advanced(by: i * 4)
            let alpha = Double(p[3]) / 255
            guard alpha > 0.5 else { continue }
            let (pr, pg, pb) = (Double(p[0]) / 255 / alpha, Double(p[1]) / 255 / alpha, Double(p[2]) / 255 / alpha)
            let maxC = max(pr, pg, pb), minC = min(pr, pg, pb)
            let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
            guard saturation > 0.35, maxC > 0.25 else { continue }
            r += pr * saturation
            g += pg * saturation
            b += pb * saturation
            weight += saturation
        }
        // Too few colored pixels: the icon is essentially monochrome.
        guard weight > 6 else { return nil }
        return RGB(r: min(r / weight, 1), g: min(g / weight, 1), b: min(b / weight, 1))
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
