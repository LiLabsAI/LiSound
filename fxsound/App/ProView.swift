import SwiftUI

struct ProView: View {
    @Environment(AppController.self) private var controller
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                equalizerSection
                effectsSection
                tuningSection
                VisualizerView(levels: state.spectrum, isOn: state.powerOn)
                    .frame(height: 72)
                    .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .disabled(!state.powerOn)
        .opacity(state.powerOn ? 1 : 0.55)
    }

    private var equalizerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    eqHeaderControls
                    qControl
                }
                VStack(alignment: .leading, spacing: 8) {
                    eqHeaderControls
                    qControl
                }
            }
            // Adaptive grid: bands reflow into rows as the window resizes.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 52, maximum: 84), spacing: 6)],
                spacing: 10) {
                ForEach(state.bands.indices, id: \.self) { index in
                    VStack(spacing: 4) {
                        VerticalSlider(
                            value: Binding(
                                get: { Double(state.bands[index].gain) },
                                set: { controller.setEQBandGain(Float($0), index: index) }),
                            range: Double(PresetBand.gainRange.lowerBound)...Double(PresetBand.gainRange.upperBound),
                            length: 118,
                            bipolar: true,
                            onDoubleTap: { controller.setEQBandGain(0, index: index) },
                            accessibilityLabel: "EQ band \(Int(state.bands[index].frequency)) hertz")
                        Text(Self.frequencyLabel(state.bands[index].frequency))
                            .font(.caption2)
                            .foregroundStyle(FxTheme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
            Text("±12 dB · double-click a band to reset")
                .font(.caption2)
                .foregroundStyle(FxTheme.textTertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FxTheme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(FxTheme.cardBorder))
    }

    private var eqHeaderControls: some View {
        HStack(spacing: 12) {
            Toggle("Equalizer", isOn: Binding(
                get: { state.eqOn },
                set: { controller.setEQOn($0) }))
                .toggleStyle(.checkbox)
                .foregroundStyle(FxTheme.textPrimary)
            Menu("\(state.bands.count) Bands") {
                ForEach(EQBandCount.allCases) { count in
                    Button("\(count.rawValue) Bands") { controller.setBandCount(count) }
                }
            }
            .fixedSize()
        }
    }

    private var qControl: some View {
        HStack(spacing: 8) {
            Text("Q").font(.caption).foregroundStyle(FxTheme.textSecondary)
            Slider(value: Binding(
                get: { Double(state.filterQ) },
                set: { controller.setFilterQ(Float($0)) }),
                in: Double(EQParameters.qRange.lowerBound)...Double(EQParameters.qRange.upperBound))
                .frame(width: 150)
            Text(String(format: "%.1f", state.filterQ))
                .monospacedDigit()
                .font(.caption)
                .foregroundStyle(FxTheme.textSecondary)
        }
    }

    private var effectsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Effects").font(.headline).foregroundStyle(FxTheme.textPrimary)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 92, maximum: 130), spacing: 10)],
                spacing: 10) {
                effectSlider("Bass", value: Binding(
                    get: { Double(state.effects.bass) },
                    set: { controller.setEffect(\EffectValues.bass, to: Float($0)) }))
                effectSlider("Fidelity", value: Binding(
                    get: { Double(state.effects.fidelity) },
                    set: { controller.setEffect(\EffectValues.fidelity, to: Float($0)) }))
                effectSlider("Ambience", value: Binding(
                    get: { Double(state.effects.ambience) },
                    set: { controller.setEffect(\EffectValues.ambience, to: Float($0)) }))
                effectSlider("Surround", value: Binding(
                    get: { Double(state.effects.surround) },
                    set: { controller.setEffect(\EffectValues.surround, to: Float($0)) }))
                effectSlider("Dynamic Boost", value: Binding(
                    get: { Double(state.effects.dynamicBoost) },
                    set: { controller.setEffect(\EffectValues.dynamicBoost, to: Float($0)) }))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FxTheme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(FxTheme.cardBorder))
    }

    private func effectSlider(_ title: String, value: Binding<Double>) -> some View {
        VStack(spacing: 4) {
            VerticalSlider(value: value, range: 0...10, length: 92,
                           accessibilityLabel: "\(title) effect")
            Text("\(value.wrappedValue, specifier: "%.1f")")
                .font(.caption2).monospacedDigit().foregroundStyle(FxTheme.textSecondary)
            Text(title)
                .font(.caption).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(FxTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var tuningSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Output").font(.headline).foregroundStyle(FxTheme.textPrimary)
            tuningRow(label: "Master", value: Binding(
                get: { Double(state.masterGainDB) },
                set: { controller.setMasterGain(Float($0)) }),
                range: -20...20,
                format: { ($0 >= 0 ? "+" : "") + String(format: "%.1f dB", $0) })
            tuningRow(label: "Balance", value: Binding(
                get: { Double(state.balanceDB) },
                set: { controller.setBalance(Float($0)) }),
                range: -20...20,
                format: { ($0 >= 0 ? "R " : $0 < 0 ? "L " : "") + String(format: "%.1f", abs($0)) + " dB" })
            tuningRow(label: "Leveling", value: Binding(
                get: { Double(state.levelingDB) },
                set: { controller.setLeveling(Float($0)) }),
                range: 0...4,
                format: { String(format: "%.1f dB", $0) })
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FxTheme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(FxTheme.cardBorder))
    }

    private func tuningRow(label: String, value: Binding<Double>, range: ClosedRange<Double>,
                           format: @escaping (Double) -> String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .frame(width: 60, alignment: .leading)
                .font(.callout)
                .foregroundStyle(FxTheme.textSecondary)
            Slider(value: value, in: range)
            Text(format(value.wrappedValue))
                .monospacedDigit()
                .foregroundStyle(FxTheme.textSecondary)
                .frame(width: 76, alignment: .trailing)
        }
    }

    static func frequencyLabel(_ hz: Float) -> String {
        hz >= 1000 ? String(format: "%.1fk", hz / 1000) : String(format: "%.0f", hz)
    }
}
