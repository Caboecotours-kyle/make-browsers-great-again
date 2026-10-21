import AppKit

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

    /// Parses "#rgb", "#rrggbb" and "rgb(a)(r, g, b[, a])" as engines report
    /// them. Translucent colors are rejected: they don't describe the page.
    init?(css: String) {
        let s = css.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix("#") {
            var hex = String(s.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
            self.init(value)
        } else if s.hasPrefix("rgb"), let open = s.firstIndex(of: "("), let close = s.lastIndex(of: ")") {
            let parts = s[s.index(after: open)..<close].split(separator: ",").map {
                Double($0.trimmingCharacters(in: .whitespaces)) ?? -1
            }
            guard parts.count >= 3, parts.prefix(3).allSatisfy({ (0...255).contains($0) }),
                  parts.count == 3 || parts[3] >= 0.99
            else { return nil }
            self.init(r: parts[0] / 255, g: parts[1] / 255, b: parts[2] / 255)
        } else {
            return nil
        }
    }

    /// Relative luminance, 0 (black) to 1 (white).
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    var hex: UInt32 {
        let c = { (v: Double) in UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return c(r) << 16 | c(g) << 8 | c(b)
    }

    func mixed(with other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }

    static let white = RGB(0xFFFFFF)
    static let black = RGB(0x000000)
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
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
    static func gradient(for base: RGB, dark: Bool, active: Bool, style: TintStyle) -> [RGB] {
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
        return [base.mixed(with: neutral, top), base.mixed(with: neutral, bottom)]
    }

    // Fills for controls drawn on the tinted window background. Hover is
    // always weaker than selection, in both appearances. They resolve against
    // the appearance current while drawing (or in updateLayer).

    static let hoverFill = NSColor(name: nil) {
        $0.isDark ? .white.withAlphaComponent(0.07) : .white.withAlphaComponent(0.3)
    }

    static let controlFill = NSColor(name: nil) {
        $0.isDark ? .white.withAlphaComponent(0.06) : .white.withAlphaComponent(0.4)
    }

    static let controlHoverFill = NSColor(name: nil) {
        $0.isDark ? .white.withAlphaComponent(0.1) : .white.withAlphaComponent(0.55)
    }

    /// The selected tab: an opaque pill that stands out in both appearances.
    static let selectedFill = NSColor(name: nil) {
        $0.isDark ? NSColor(srgbRed: 0.3, green: 0.3, blue: 0.32, alpha: 1) : .white
    }

    static let selectedShadow = NSColor(name: nil) {
        $0.isDark ? .black.withAlphaComponent(0.3) : .black.withAlphaComponent(0.09)
    }

    /// Hairlines and quiet fills drawn in the text color.
    static func faint(_ alpha: CGFloat) -> NSColor { NSColor.labelColor.withAlphaComponent(alpha) }

    /// Solid surfaces floating over the page: command bar, toasts.
    static let cardFill = NSColor(name: nil) {
        $0.isDark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.99, alpha: 1)
    }

    static let toastFill = NSColor(name: nil) {
        $0.isDark ? NSColor(white: 0.2, alpha: 1) : .white
    }

    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }
}

/// How strongly a space's color tints the window.
enum TintStyle: String, CaseIterable {
    case vivid, calm, neutral

    static let defaultsKey = "tintStyle"
    /// The window takes the visible page's theme color instead of the space's.
    static let matchPageKey = "matchPageColor"

    static var saved: TintStyle {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(TintStyle.init) ?? .calm
    }

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
    struct Curve {
        let duration: TimeInterval
        let timing: CAMediaTimingFunction
    }

    /// MBGA_DEBUG_SLOW_MOTION=8 plays every animation 8 times slower, for
    /// captures of transitions mid-way.
    private static let slow = Double(ProcessInfo.processInfo.environment["MBGA_DEBUG_SLOW_MOTION"] ?? "") ?? 1

    // Springs approximated by an ease-out with a soft landing, so AppKit's
    // animator and Core Animation can both use them.
    static let quick = Curve(duration: 0.14 * slow, timing: CAMediaTimingFunction(name: .easeOut))
    static let glide = Curve(duration: 0.34 * slow, timing: CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1))
    static let settle = Curve(duration: 0.3 * slow, timing: CAMediaTimingFunction(controlPoints: 0.25, 0.85, 0.3, 1))
    static let foldOut = Curve(duration: 0.16 * slow, timing: CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1))
    static let foldIn = Curve(duration: 0.13 * slow, timing: CAMediaTimingFunction(name: .easeIn))
    /// The sidebar's list moving to make room or close a gap: a gentle
    /// start, so what it moves over can fade first.
    static let reflow = Curve(duration: 0.3 * slow, timing: CAMediaTimingFunction(name: .easeInEaseOut))
    /// How long a spring takes to (nearly) settle.
    static let springResponse = 0.3 * slow
    /// A page giving way to another space's.
    static let fade = Curve(duration: 0.22 * slow, timing: CAMediaTimingFunction(name: .easeInEaseOut))

    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Runs `changes` through the views' and layers' animators, or instantly
    /// with Reduce Motion or no curve.
    @MainActor
    static func animate(_ curve: Curve?, _ changes: () -> Void, completion: (@MainActor () -> Void)? = nil) {
        guard let curve, !reduced else {
            changes()
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = curve.duration
            context.timingFunction = curve.timing
            context.allowsImplicitAnimation = true
            changes()
        } completionHandler: {
            MainActor.assumeIsolated { completion?() }
        }
    }

    /// Runs `changes` with no animation, even inside an animated change: a
    /// view that just appeared takes its place instead of flying in from
    /// the corner.
    @MainActor
    static func instantly(_ changes: () -> Void) {
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
        NSAnimationContext.endGrouping()
    }
}

/// A critically damped spring for moves that can be turned around: it heads
/// for its target without overshooting, and keeps its speed when the target
/// changes mid-way, so a move reversed (a quick second ⌘S) slows and turns
/// instead of snapping into the new direction.
struct Spring {
    var value: CGFloat
    var velocity: CGFloat = 0
    var target: CGFloat
    let response: Double

    init(_ value: CGFloat, response: Double = Motion.springResponse) {
        self.value = value
        target = value
        self.response = response
    }

    var isSettled: Bool { abs(value - target) < 0.0005 && abs(velocity) < 0.005 }

    /// Advances `dt` seconds (exactly, however long the frame was).
    mutating func step(_ dt: Double) {
        let w = 2 * Double.pi / response
        let x0 = Double(value - target), v0 = Double(velocity)
        let c = v0 + w * x0
        let decay = exp(-w * dt)
        value = target + CGFloat((x0 + c * dt) * decay)
        velocity = CGFloat((v0 - w * c * dt) * decay)
        if isSettled {
            value = target
            velocity = 0
        }
    }

    mutating func settle() {
        value = target
        velocity = 0
    }
}

extension Motion.Curve {
    /// How far along the curve is at time fraction `t` (0...1), for moves
    /// stepped frame by frame.
    func progress(at t: Double) -> Double {
        var a = [Float](repeating: 0, count: 2), b = [Float](repeating: 0, count: 2)
        timing.getControlPoint(at: 1, values: &a)
        timing.getControlPoint(at: 2, values: &b)
        func bezier(_ s: Double, _ p1: Float, _ p2: Float) -> Double {
            let p1 = Double(p1), p2 = Double(p2)
            return 3 * p1 * s * (1 - s) * (1 - s) + 3 * p2 * s * s * (1 - s) + s * s * s
        }
        func slope(_ s: Double, _ p1: Float, _ p2: Float) -> Double {
            let p1 = Double(p1), p2 = Double(p2)
            return 3 * p1 * (1 - s) * (1 - s) + 6 * (p2 - p1) * s * (1 - s) + 3 * (1 - p2) * s * s
        }
        // The curve's x is time: find where it reaches t, then read y there.
        var s = t
        for _ in 0..<8 {
            let d = slope(s, a[0], b[0])
            guard abs(d) > 1e-6 else { break }
            s = min(max(s - (bezier(s, a[0], b[0]) - t) / d, 0), 1)
        }
        return bezier(s, a[1], b[1])
    }
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
    private static let globe = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)!

    func image(atPath path: String) -> NSImage? {
        if let image = cache.object(forKey: path as NSString) { return image }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }

    /// The tab's favicon, or a globe template image.
    func image(for tab: TabInfo) -> NSImage {
        tab.faviconPath.flatMap { image(atPath: $0) } ?? Self.globe
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
