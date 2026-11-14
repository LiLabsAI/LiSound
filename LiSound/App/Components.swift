import SwiftUI

/// Crisp vector emblem matching the LiSound icon ("Li" monogram + 3 stepped soundwave bars).
struct LiSoundLogo: View {
    var showBadge: Bool = false

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let originX = (size.width - side) / 2
            let originY = (size.height - side) / 2

            if showBadge {
                let badgeRect = CGRect(x: originX + side * 0.04, y: originY + side * 0.04,
                                       width: side * 0.92, height: side * 0.92)
                let badge = Path(roundedRect: badgeRect, cornerRadius: badgeRect.width * 0.225, style: .continuous)
                context.fill(badge, with: .radialGradient(
                    Gradient(colors: [
                        Color(red: 0.10, green: 0.08, blue: 0.035),
                        Color(red: 0.02, green: 0.02, blue: 0.02),
                    ]),
                    center: CGPoint(x: size.width / 2, y: originY + side * 0.38),
                    startRadius: 2,
                    endRadius: side * 0.6))
                context.stroke(badge, with: .linearGradient(
                    Gradient(colors: [Color.lightGold.opacity(0.9), Color.gold.opacity(0.7), Color.deepGold.opacity(0.6)]),
                    startPoint: CGPoint(x: badgeRect.minX, y: badgeRect.minY),
                    endPoint: CGPoint(x: badgeRect.maxX, y: badgeRect.maxY)),
                    lineWidth: max(1, side * 0.018))
            }

            // Map 550x448 design box (x: 236..786, y: 286..734) into the available square
            let inset = showBadge ? side * 0.20 : side * 0.06
            let target = CGRect(x: originX + inset, y: originY + inset,
                                width: side - 2 * inset, height: side - 2 * inset)
            let scale = min(target.width / 550, target.height / 448)
            let tx = target.midX - 511 * scale
            let ty = target.midY - 510 * scale

            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: tx + (x + 18) * scale, y: ty + y * scale)
            }
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: tx + (x + 18) * scale, y: ty + y * scale, width: w * scale, height: h * scale)
            }

            let lPath = Path { p in
                let rCap = 37 * scale
                let rInner = 18 * scale
                let rOuter = 38 * scale
                p.move(to: pt(218, 327))
                p.addArc(center: pt(255, 327), radius: rCap, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                p.addLine(to: pt(292, 660 - 18))
                p.addQuadCurve(to: pt(292 + 18, 660), control: pt(292, 660))
                _ = rInner
                p.addLine(to: pt(429, 660))
                p.addArc(center: pt(429, 697), radius: rCap, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
                p.addLine(to: pt(218 + 38, 734))
                p.addQuadCurve(to: pt(218, 734 - 38), control: pt(218, 734))
                _ = rOuter
                p.closeSubpath()
            }
            let iStem = Path(roundedRect: rect(388, 426, 74, 182), cornerRadius: 37 * scale)
            let iDot = Path(ellipseIn: rect(386, 286, 78, 78))
            let wave1 = Path(roundedRect: rect(536, 386, 48, 252), cornerRadius: 24 * scale)
            let wave2 = Path(roundedRect: rect(628, 304, 48, 416), cornerRadius: 24 * scale)
            let wave3 = Path(roundedRect: rect(720, 422, 48, 180), cornerRadius: 24 * scale)

            let goldFill = GraphicsContext.Shading.linearGradient(
                LiTheme.barGradient,
                startPoint: pt(220, 280),
                endPoint: pt(760, 740))

            for shape in [lPath, iStem, wave1, wave2, wave3] {
                context.fill(shape, with: goldFill)
            }
            context.fill(iDot, with: .radialGradient(
                Gradient(colors: [.white, LiTheme.peakColor]),
                center: pt(420, 318),
                startRadius: 0,
                endRadius: 42 * scale))
        }
        .accessibilityHidden(true)
    }
}

struct PowerButton: View {
    let isOn: Bool
    let action: () -> Void

    @State private var pulsing = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isOn {
                    Circle()
                        .stroke(LiTheme.accent.opacity(pulsing ? 0.15 : 0.55), lineWidth: 6)
                        .scaleEffect(pulsing ? 1.3 : 1.0)
                        .blur(radius: 2)
                }
                Circle()
                    .fill(isOn ? AnyShapeStyle(LiTheme.accent) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)))
                    .overlay(Circle().strokeBorder(isOn ? LiTheme.accent : Color.white.opacity(0.25), lineWidth: 1.5))
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
        .accessibilityLabel(isOn ? "Turn LiSound off" : "Turn LiSound on")
    }
}

/// Custom vertical slider drawn with the theme (gold fill, white knob) — rotated
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
                    .fill(LiTheme.barGradient)
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

/// Mirrored thin-stick spectrum visualizer: draws 128 log-spaced FFT sticks
/// driven by beat energy with fast attack / smooth release.
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
                    glow.fill(path, with: .color(LiTheme.accent.opacity(0.45 * ageFade)))
                    context.fill(path, with: .linearGradient(
                        Gradient(colors: [
                            LiTheme.peakColor.opacity(ageFade),
                            LiTheme.accent.opacity(ageFade),
                        ]),
                        startPoint: CGPoint(x: x, y: 0),
                        endPoint: CGPoint(x: x, y: size.height)))
                }

                let baseline = Path { p in
                    p.move(to: CGPoint(x: 0, y: centerY))
                    p.addLine(to: CGPoint(x: size.width, y: centerY))
                }
                context.stroke(baseline, with: .color(LiTheme.textTertiary), lineWidth: 0.5)
            }
        }
        .accessibilityLabel("Audio waveform")
    }
}
