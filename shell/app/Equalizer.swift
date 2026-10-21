import AppKit
import SwiftUI

/// Three bars bouncing like Arc's "now playing" indicator. The animation is
/// handed to Core Animation, which runs it in the render server, so the app
/// itself doesn't wake up for every frame. Static with Reduce Motion.
struct Equalizer: NSViewRepresentable {
    var playing = true
    var color: NSColor = .labelColor

    func makeNSView(context: Context) -> EqualizerView { EqualizerView() }

    func updateNSView(_ view: EqualizerView, context: Context) {
        view.barColor = color
        view.playing = playing && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EqualizerView, context: Context) -> CGSize? {
        CGSize(width: 12, height: 12)
    }
}

final class EqualizerView: NSView {
    private let bars = (0..<3).map { _ in CALayer() }
    // Each bar bounces at its own pace so the three never move in step.
    private let durations: [CFTimeInterval] = [0.42, 0.31, 0.53]
    private let rest: [CGFloat] = [0.45, 0.8, 0.6]

    var barColor: NSColor = .labelColor {
        didSet { updateColors() }
    }

    var playing = false {
        didSet { if playing != oldValue { updateAnimations() } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for bar in bars {
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.cornerRadius = 1
            layer?.addSublayer(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        let width: CGFloat = 2.5, gap = (bounds.width - width * 3) / 2
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(i) * (width + gap) + width / 2, y: 0)
            if !playing { bar.transform = CATransform3DMakeScale(1, rest[i], 1) }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for bar in bars { bar.backgroundColor = barColor.cgColor }
        }
    }

    private func updateAnimations() {
        for (i, bar) in bars.enumerated() {
            bar.removeAllAnimations()
            bar.transform = CATransform3DMakeScale(1, rest[i], 1)
            guard playing else { continue }
            let bounce = CABasicAnimation(keyPath: "transform.scale.y")
            bounce.fromValue = 0.25
            bounce.toValue = 1.0
            bounce.duration = durations[i]
            bounce.autoreverses = true
            bounce.repeatCount = .infinity
            bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            // Survives the view leaving and rejoining a window.
            bounce.isRemovedOnCompletion = false
            bar.add(bounce, forKey: "bounce")
        }
    }
}
