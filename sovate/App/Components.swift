import SwiftUI

struct PowerButton: View {
    let isOn: Bool
    let action: () -> Void

    @State private var pulsing = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isOn {
                    Circle()
                        .stroke(FxTheme.accent.opacity(pulsing ? 0.15 : 0.55), lineWidth: 6)
                        .scaleEffect(pulsing ? 1.3 : 1.0)
                        .blur(radius: 2)
                }
                Circle()
                    .fill(isOn ? AnyShapeStyle(FxTheme.accent) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)))
                    .overlay(Circle().strokeBorder(isOn ? FxTheme.accent : Color.white.opacity(0.25), lineWidth: 1.5))
                Image(systemName: "power")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : Color.white.opacity(0.45))
            }
            .frame(width: 54, height: 54)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .animation(.easeInOut(duration: 0.25), value: isOn)
        .onAppear { pulsing = isOn }
        .onChange(of: isOn) { _, newValue in pulsing = newValue }
        .accessibilityLabel(isOn ? "Turn Sovate off" : "Turn Sovate on")
    }
}

/// Custom vertical slider drawn with the theme (red fill, white knob) — rotated
/// NSSliders render inconsistently on dark backgrounds.
struct VerticalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var length: CGFloat = 130
    var bipolar = false
    var onDoubleTap: (() -> Void)? = nil
    var accessibilityLabel: String = "Slider"
    private var adjustStep: Double { (range.upperBound - range.lowerBound) / 24 }

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let knobY = height - CGFloat(fraction) * height
            let centerY = bipolar ? height / 2 : height
            let fillTop = min(knobY, centerY)
            let fillHeight = max(abs(centerY - knobY), 2)
            ZStack {
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 5)
                Capsule()
                    .fill(FxTheme.barGradient)
                    .frame(width: 5, height: fillHeight)
                    .position(x: geo.size.width / 2, y: fillTop + fillHeight / 2)
                Circle()
                    .fill(Color.white)
                    .frame(width: 15, height: 15)
                    .shadow(color: .black.opacity(0.55), radius: 2.5, y: 1)
                    .position(x: geo.size.width / 2, y: knobY)
            }
            .frame(width: geo.size.width, height: height)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onDoubleTap?() }
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { gesture in
                    let f = 1 - min(max(gesture.location.y / height, 0), 1)
                    value = range.lowerBound + f * (range.upperBound - range.lowerBound)
                }
            )
        }
        .frame(width: 26, height: length)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(value, specifier: "%.1f")")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + adjustStep, range.upperBound)
            case .decrement: value = max(value - adjustStep, range.lowerBound)
            @unknown default: break
            }
        }
    }
}

/// Mirrored thin-stick waveform visualizer: draws the scrolling amplitude history
/// (one stick per ~10 ms of audio) so beats and syllables spike and fall away.
struct VisualizerView: View {
    let levels: [Float]
    var isOn: Bool = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let count = max(1, levels.count)
                let slot = size.width / CGFloat(count)
                let barWidth = max(1.2, slot * 0.58)
                let centerY = size.height / 2
                let maxHalf = size.height / 2 - 2

                for (index, level) in levels.enumerated() {
                    let ageFade = 0.4 + 0.6 * CGFloat(index) / CGFloat(count)
                    let half = CGFloat(level) * maxHalf
                    guard half >= 0.75 else { continue }
                    let x = CGFloat(index) * slot + (slot - barWidth) / 2
                    let rect = CGRect(x: x, y: centerY - half, width: barWidth, height: half * 2)
                    let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)

                    var glow = context
                    glow.addFilter(.blur(radius: 2))
                    glow.fill(path, with: .color(FxTheme.accent.opacity(0.45 * ageFade)))
                    context.fill(path, with: .linearGradient(
                        Gradient(colors: [
                            FxTheme.peakColor.opacity(ageFade),
                            FxTheme.accent.opacity(ageFade),
                        ]),
                        startPoint: CGPoint(x: x, y: 0),
                        endPoint: CGPoint(x: x, y: size.height)))
                }

                let baseline = Path { p in
                    p.move(to: CGPoint(x: 0, y: centerY))
                    p.addLine(to: CGPoint(x: size.width, y: centerY))
                }
                context.stroke(baseline, with: .color(FxTheme.textTertiary), lineWidth: 0.5)
            }
        }
        .accessibilityLabel("Audio waveform")
    }
}
