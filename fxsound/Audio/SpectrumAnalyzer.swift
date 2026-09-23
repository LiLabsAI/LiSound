import Foundation
import Accelerate
import os

final class SpectrumAnalyzer: @unchecked Sendable {
    static let bandCount = 10
    static let windowSize = 2048

    private let sampleRate: Float
    private let fftSetup: FFTSetup
    private let log2n: vDSP_Length = 11
    private var window: [Float]
    private var windowAccum: [Float] = []
    private var realBuf: UnsafeMutablePointer<Float>
    private var imagBuf: UnsafeMutablePointer<Float>
    private var magnitudes: [Float]
    private var bandRanges: [(lower: Int, upper: Int)] = []
    private var bandSmoothing: [Float] = Array(repeating: 0, count: SpectrumAnalyzer.bandCount)

    private let levelsLock = OSAllocatedUnfairLock<[Float]>(
        initialState: Array(repeating: 0, count: SpectrumAnalyzer.bandCount))

    init(sampleRate: Float) {
        self.sampleRate = max(8000, sampleRate)
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        self.window = [Float](repeating: 0, count: SpectrumAnalyzer.windowSize)
        vDSP_hann_window(&window, vDSP_Length(SpectrumAnalyzer.windowSize), Int32(vDSP_HANN_NORM))
        self.realBuf = UnsafeMutablePointer<Float>.allocate(capacity: SpectrumAnalyzer.windowSize / 2)
        self.imagBuf = UnsafeMutablePointer<Float>.allocate(capacity: SpectrumAnalyzer.windowSize / 2)
        self.magnitudes = [Float](repeating: 0, count: SpectrumAnalyzer.windowSize / 2)
        self.bandRanges = Self.computeBandRanges(sampleRate: self.sampleRate, fftSize: SpectrumAnalyzer.windowSize)
    }

    deinit {
        realBuf.deallocate()
        imagBuf.deallocate()
        vDSP_destroy_fftsetup(fftSetup)
    }

    private static func computeBandRanges(sampleRate: Float, fftSize: Int) -> [(Int, Int)] {
        let nyquist = sampleRate / 2
        let binHz = nyquist / Float(fftSize / 2)
        let bandEdges: [Float] = (0...SpectrumAnalyzer.bandCount).map { i in
            let t = Float(i) / Float(SpectrumAnalyzer.bandCount)
            let f = exp(log(50) + t * (log(16000) - log(50)))
            return min(max(f, 20), nyquist)
        }
        return (0..<SpectrumAnalyzer.bandCount).map { i in
            let lower = Int(bandEdges[i] / binHz)
            let upper = max(Int(bandEdges[i + 1] / binHz), lower + 1)
            return (lower, min(upper, fftSize / 2))
        }
    }

    /// Called from the audio IO thread with direct L/R pointers.
    func process(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?, frames: Int) {
        guard frames > 0 else { return }
        let l = left
        if let r = right {
            for i in 0..<frames { windowAccum.append((l[i] + r[i]) * 0.5) }
        } else {
            for i in 0..<frames { windowAccum.append(l[i]) }
        }
        runFFTIfReady(consume: frames)
    }

    /// Called from the audio IO thread. Input is a planar copy of the tapped frames.
    func process(planar: UnsafeMutablePointer<UnsafeMutablePointer<Float>>, frames: Int, channels: Int) {
        guard frames > 0 else { return }
        let l = planar[0]
        if channels > 1 {
            let r = planar[1]
            for i in 0..<frames { windowAccum.append((l[i] + r[i]) * 0.5) }
        } else {
            for i in 0..<frames { windowAccum.append(l[i]) }
        }
        runFFTIfReady(consume: frames)
    }

    private func runFFTIfReady(consume frames: Int) {
        let n = SpectrumAnalyzer.windowSize
        guard windowAccum.count >= n else { return }
        if windowAccum.count > n * 4 {
            windowAccum.removeFirst(windowAccum.count - n)
        }
        let chunk = Array(windowAccum.suffix(n))
        windowAccum.removeFirst(min(windowAccum.count, frames))

        var mono = chunk
        window.withUnsafeBufferPointer { windowPtr in
            mono.withUnsafeMutableBufferPointer { monoPtr in
                chunk.withUnsafeBufferPointer { chunkPtr in
                    vDSP_vmul(chunkPtr.baseAddress!, 1, windowPtr.baseAddress!, 1, monoPtr.baseAddress!, 1, vDSP_Length(n))
                }
            }
        }

        for i in 0..<(n / 2) {
            realBuf[i] = mono[i * 2]
            imagBuf[i] = mono[i * 2 + 1]
        }
        var split = DSPSplitComplex(realp: realBuf, imagp: imagBuf)
        vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
        vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(n / 2))

        let levels: [Float] = bandRanges.enumerated().map { bi, range in
            var sum: Float = 0
            for b in range.lower..<max(range.upper, range.lower + 1) {
                sum += magnitudes[b]
            }
            let avg = sum / Float(max(1, range.upper - range.lower))
            let db = 10 * log10(max(avg, 1e-12))
            return min(max((db + 72) / 60, 0), 1)
        }
        levelsLock.withLock { stored in
            stored = zip(levels, stored).map { max($0, $1 * 0.82) }
        }
    }

    func currentLevels() -> [Float] {
        levelsLock.withLock { $0 }
    }

    func reset() {
        windowAccum.removeAll(keepingCapacity: true)
        levelsLock.withLock { $0 = Array(repeating: 0, count: Self.bandCount) }
    }
}
