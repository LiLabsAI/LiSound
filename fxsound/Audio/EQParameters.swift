import Foundation

enum EQBandCount: Int, CaseIterable, Codable, Identifiable {
    case five = 5
    case ten = 10
    case fifteen = 15
    case twenty = 20
    case thirtyOne = 31

    var id: Int { rawValue }

    var label: String { "\(rawValue) Bands" }
}

enum EQParameters {
    static let gainRange: ClosedRange<Float> = -12...12
    static let qRange: ClosedRange<Float> = 1.0...3.0
    static let minCenterHz: Float = 20
    static let maxCenterHz: Float = 20000

    static let defaultTenBandCenters: [Float] = [
        62.5, 121.5, 225, 416.5, 770.5, 1425, 2645, 4895, 9060, 13885,
    ]

    static func defaultCenters(count: Int) -> [Float] {
        if count == 10 { return defaultTenBandCenters }
        let lo = log2(Float(31.5))
        let hi = log2(Float(16000))
        return (0..<count).map { i in
            let t = count == 1 ? 0 : Float(i) / Float(count - 1)
            return pow(2, lo + t * (hi - lo))
        }
    }

    static func clampFrequency(_ f: Float, index: Int, count: Int) -> Float {
        let all = defaultCenters(count: count)
        let lower: Float = index == 0 ? minCenterHz : (all[index - 1] + all[index]) / 2
        let upper: Float = index == count - 1 ? maxCenterHz : (all[index] + all[index + 1]) / 2
        return min(max(f, lower), upper)
    }

    static func bandwidthOctaves(count: Int, q: Float) -> Float {
        let lo = log2(Float(31.5))
        let hi = log2(Float(16000))
        let span = (hi - lo) / Float(max(1, count - 1))
        let bandwidth = span / max(q, 0.1)
        return min(max(bandwidth, 0.1), 2.0)
    }

    /// Interpolates existing band gains (piecewise-linear over log-frequency) onto a
    /// new band-count layout, so switching band count keeps the user's curve shape.
    static func resample(_ bands: [PresetBand], to count: Int) -> [PresetBand] {
        let targets = defaultCenters(count: count)
        let sorted = bands.sorted { $0.frequency < $1.frequency }
        guard let first = sorted.first, let last = sorted.last else {
            return targets.map { PresetBand(frequency: $0, gain: 0) }
        }
        return targets.map { target in
            let t = log2(max(target, minCenterHz))
            if t <= log2(first.frequency) { return PresetBand(frequency: target, gain: first.gain) }
            if t >= log2(last.frequency) { return PresetBand(frequency: target, gain: last.gain) }
            for i in 0..<(sorted.count - 1) {
                let lo = log2(sorted[i].frequency)
                let hi = log2(sorted[i + 1].frequency)
                if t >= lo, t <= hi {
                    let f = (t - lo) / max(hi - lo, 0.0001)
                    let gain = sorted[i].gain + f * (sorted[i + 1].gain - sorted[i].gain)
                    return PresetBand(frequency: target, gain: gain.rounded())
                }
            }
            return PresetBand(frequency: target, gain: 0)
        }
    }
}
