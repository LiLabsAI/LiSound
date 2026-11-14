import Foundation
import Accelerate

/// Fixed-stick spectrum feed for the visualizer: 128 log-spaced frequency bands,
/// each stick animating up and down in place (no scrolling). Band levels map a
/// Hann-windowed FFT onto a fixed dB range so loud beats pop and quiet passages
/// fall — with fast attack / slow release smoothing for the dance feel.
final class SpectrumBars: @unchecked Sendable {
    static let bandCount = 128
    static let fftSize = 2048

    private let sampleRate: Float
    private let fftSetup: FFTSetup
    private let log2n: vDSP_Length = 11
    private var window = [Float](repeating: 0, count: SpectrumBars.fftSize)
    private var ring = [Float](repeating: 0, count: SpectrumBars.fftSize)
    private var ringWrite = 0
    private var ringFilled = 0
    private var realBuf: UnsafeMutablePointer<Float>
    private var imagBuf: UnsafeMutablePointer<Float>
    private var magnitudes = [Float](repeating: 0, count: SpectrumBars.fftSize / 2)
    private var bandRanges: [(lower: Int, upper: Int)] = []
    private var bands = [Float](repeating: 0, count: SpectrumBars.bandCount)
    private var lock = os_unfair_lock()

    init(sampleRate: Float) {
        self.sampleRate = max(8000, sampleRate)
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        vDSP_hann_window(&window, vDSP_Length(SpectrumBars.fftSize), Int32(vDSP_HANN_NORM))
        self.realBuf = UnsafeMutablePointer<Float>.allocate(capacity: SpectrumBars.fftSize / 2)
        self.imagBuf = UnsafeMutablePointer<Float>.allocate(capacity: SpectrumBars.fftSize / 2)
        self.bandRanges = Self.computeBandRanges(sampleRate: self.sampleRate, fftSize: SpectrumBars.fftSize)
    }

    deinit {
        realBuf.deallocate()
        imagBuf.deallocate()
        vDSP_destroy_fftsetup(fftSetup)
    }

    private static func computeBandRanges(sampleRate: Float, fftSize: Int) -> [(lower: Int, upper: Int)] {
        let binHz = (sampleRate / 2) / Float(fftSize / 2)
        let edges: [Float] = (0...SpectrumBars.bandCount).map { i in
            let t = Float(i) / Float(SpectrumBars.bandCount)
            let f = exp(log(40) + t * (log(16000) - log(40)))
            return min(max(f, 20), sampleRate / 2 - 1)
        }
        return (0..<SpectrumBars.bandCount).map { i in
            let lower = max(1, Int(edges[i] / binHz))
            let upper = max(lower + 1, Int(edges[i + 1] / binHz))
            return (lower, min(upper, fftSize / 2))
        }
    }

    /// Render thread: slide the analysis window, FFT, map band power onto 0–1 with a
    /// fixed dB range (−30 → 0, +15 → 1 covers music's ~45 dB of band dynamics), then
    /// smooth with fast attack / slow release so bars dance without flicker.
    func analyze(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?,
                 frames: Int, sampleRate: Float) {
        let dt = Float(frames) / max(sampleRate, 8000)
        let n = SpectrumBars.fftSize
        for i in 0..<frames {
            let mono = right.map { (left[i] + $0[i]) * 0.5 } ?? left[i]
            ring[ringWrite] = mono
            ringWrite = (ringWrite + 1) % n
        }
        ringFilled = min(ringFilled + frames, n)
        guard ringFilled >= n else { return }

        for i in 0..<(n / 2) {
            realBuf[i] = ring[(ringWrite + i * 2) % n] * window[i * 2]
            imagBuf[i] = ring[(ringWrite + i * 2 + 1) % n] * window[i * 2 + 1]
        }
        var split = DSPSplitComplex(realp: realBuf, imagp: imagBuf)
        vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
        vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(n / 2))

        let attack = 1 - exp(-dt * 80)
        let release = 1 - exp(-dt * 7)

        os_unfair_lock_lock(&lock)
        for (i, range) in bandRanges.enumerated() {
            var sum: Float = 0
            for b in range.lower..<range.upper {
                sum += magnitudes[b]
            }
            let avg = sum / Float(range.upper - range.lower)
            let db = 10 * log10(max(avg, 1e-12))
            let target = min(max((db + 30) / 45, 0), 1)
            if target > bands[i] {
                bands[i] += (target - bands[i]) * attack
            } else {
                bands[i] += (target - bands[i]) * release
            }
            if bands[i] < 0.004 { bands[i] = 0 }
        }
        os_unfair_lock_unlock(&lock)
    }

    func snapshot() -> [Float] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return bands
    }

    var peakLevel: Float {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return bands.max() ?? 0
    }

}
