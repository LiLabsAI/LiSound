import SwiftUI

/// App-wide color system: pure black surfaces with a red accent (user spec).
enum FxTheme {
    static let background = Color.black
    static let card = Color(red: 0.06, green: 0.06, blue: 0.06)
    static let cardBorder = Color.red.opacity(0.22)
    static let accent = Color.red
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.32)

    static let barGradient = Gradient(colors: [
        Color(red: 1.0, green: 0.32, blue: 0.25),
        Color(red: 0.92, green: 0.05, blue: 0.05),
        Color(red: 0.45, green: 0.01, blue: 0.01),
    ])

    static let peakColor = Color(red: 1.0, green: 0.75, blue: 0.72)
}

/// Per-frame smoothing state for the animated visualizer.
@MainActor
final class VisualizerModel {
    struct Bar {
        var current: CGFloat = 0
        var peak: CGFloat = 0
        var peakAge: TimeInterval = 0
    }

    private(set) var bars: [Bar] = []
    private var lastTick: TimeInterval = 0

    /// Called once per display frame from the TimelineView draw pass.
    func tick(targets: [Float], now: TimeInterval, active: Bool) {
        let dt = lastTick == 0 ? 1.0 / 60.0 : min(now - lastTick, 0.1)
        lastTick = now

        if bars.count != targets.count {
            bars = (0..<targets.count).map { _ in Bar() }
        }
        let attack = 1 - exp(-dt * 30)
        let decay = 1 - exp(-dt * 9)
        let gravity: CGFloat = 0.38

        for i in bars.indices {
            let target = active ? CGFloat(targets[i]) : 0
            let rate = target > bars[i].current ? attack : decay
            bars[i].current += (target - bars[i].current) * rate
            if bars[i].current < 0.004 { bars[i].current = 0 }
            if bars[i].current > bars[i].peak {
                bars[i].peak = bars[i].current
                bars[i].peakAge = 0
            } else {
                bars[i].peakAge += dt
                if bars[i].peakAge > 0.35 {
                    bars[i].peak = max(bars[i].current, bars[i].peak - gravity * CGFloat(dt))
                }
            }
        }
    }
}
