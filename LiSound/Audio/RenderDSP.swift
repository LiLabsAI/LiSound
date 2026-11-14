import Foundation
import os

final class RenderDSP: @unchecked Sendable {
    struct Params: Sendable, Equatable {
        var balanceDB: Float = 0
        var width: Float = 0
        var levelingDB: Float = 0
    }

    private let lock = OSAllocatedUnfairLock<Params>(initialState: Params())
    private var envelope: Float = 0
    private var appliedGain: Float = 1

    func setParams(_ p: Params) {
        lock.withLock { $0 = p }
    }

    func reset() {
        envelope = 0
        appliedGain = 1
    }

    /// In-place stereo processing directly on L/R channel pointers.
    func process(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?,
                 frames: Int) {
        guard frames > 0 else { return }
        withPlanarBuffers(left: left, right: right, frames: frames) { planar, channels in
            process(planar: planar, frames: frames, channels: channels)
        }
    }

    private func withPlanarBuffers(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?,
                                   frames: Int, _ body: (UnsafeMutablePointer<UnsafeMutablePointer<Float>>, Int) -> Void) {
        var pointers: (UnsafeMutablePointer<Float>, UnsafeMutablePointer<Float>) = (left, right ?? left)
        withUnsafeMutablePointer(to: &pointers) { base in
            base.withMemoryRebound(to: UnsafeMutablePointer<Float>.self, capacity: 2) { ptrs in
                body(ptrs, right != nil ? 2 : 1)
            }
        }
    }

    /// In-place planar processing on the render thread: balance, stereo width, leveling AGC.
    func process(planar: UnsafeMutablePointer<UnsafeMutablePointer<Float>>, frames: Int, channels: Int) {
        guard frames > 0, channels >= 1 else { return }
        let p = lock.withLock { $0 }

        let leftGain: Float = p.balanceDB >= 0 ? pow(10, -p.balanceDB / 20) : 1
        let rightGain: Float = p.balanceDB <= 0 ? pow(10, p.balanceDB / 20) : 1

        let l = planar[0]
        let r = channels > 1 ? planar[1] : nil

        if let r {
            for i in 0..<frames {
                l[i] *= leftGain
                r[i] *= rightGain
            }
            if p.width > 0.001 {
                let sideGain = 1 + p.width * 0.55
                let midCut = p.width * 1.2
                let midGain = pow(10, -midCut / 20)
                for i in 0..<frames {
                    let mid = (l[i] + r[i]) * 0.5
                    let side = (l[i] - r[i]) * 0.5
                    l[i] = (mid + side * sideGain) * midGain
                    r[i] = (mid - side * sideGain) * midGain
                }
            }
        } else {
            let g = (leftGain + rightGain) * 0.5
            for i in 0..<frames { l[i] *= g }
        }

        if p.levelingDB > 0.01 {
            applyLeveling(planar: planar, frames: frames, channels: channels, cap: p.levelingDB)
        }
    }

    private func applyLeveling(planar: UnsafeMutablePointer<UnsafeMutablePointer<Float>>,
                               frames: Int, channels: Int, cap: Float) {
        var sum: Float = 0
        let l = planar[0]
        let r = channels > 1 ? planar[1] : nil
        for i in 0..<frames {
            let s: Float = r.map { (l[i] * l[i] + $0[i] * $0[i]) * 0.5 } ?? (l[i] * l[i])
            sum += s
        }
        let rms = sqrt(sum / Float(max(1, frames)))
        let alpha: Float = rms > envelope ? 0.02 : 0.005
        envelope += (rms - envelope) * alpha
        guard envelope > 1e-5 else { return }

        let target: Float = 0.18
        var wanted = target / envelope
        let maxGain = pow(10, cap / 20)
        wanted = min(max(wanted, 1.0), maxGain)
        let smooth: Float = wanted > appliedGain ? 0.001 : 0.01
        appliedGain += (wanted - appliedGain) * smooth

        for ch in 0..<channels {
            let ptr = planar[ch]
            for i in 0..<frames { ptr[i] *= appliedGain }
        }
    }
}
