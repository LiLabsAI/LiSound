import Foundation
import CoreAudio
import os

final class RingBuffer: @unchecked Sendable {
    private struct State {
        var head: UInt64 = 0
        var tail: UInt64 = 0
        var overruns: UInt64 = 0
        var underruns: UInt64 = 0
        var totalWritten: UInt64 = 0
    }

    private let capacityFrames: Int
    private let channels: Int
    private let storage: UnsafeMutablePointer<Float>
    private let mask: Int
    private var state = State()
    private var unfairLock = os_unfair_lock()

    init(capacityFrames: Int, channels: Int) {
        var cap = 1
        while cap < capacityFrames { cap <<= 1 }
        self.capacityFrames = cap
        self.channels = max(1, channels)
        self.mask = cap - 1
        self.storage = UnsafeMutablePointer<Float>.allocate(capacity: cap * self.channels)
        self.storage.initialize(repeating: 0, count: cap * self.channels)
    }

    deinit {
        storage.deinitialize(count: capacityFrames * channels)
        storage.deallocate()
    }

    var capacity: Int { capacityFrames }

    var statistics: (overruns: UInt64, underruns: UInt64, totalWritten: UInt64) {
        os_unfair_lock_lock(&unfairLock)
        defer { os_unfair_lock_unlock(&unfairLock) }
        return (state.overruns, state.underruns, state.totalWritten)
    }

    func reset() {
        os_unfair_lock_lock(&unfairLock)
        state = State()
        os_unfair_lock_unlock(&unfairLock)
        storage.update(repeating: 0, count: capacityFrames * channels)
    }

    /// Producer side (Core Audio IOProc). Copies `frames` frames from an AudioBufferList
    /// (interleaved or non-interleaved, up to 2 channels) into planar storage, dropping
    /// the oldest frames when full.
    ///
    /// Buffer addresses are read via raw pointer arithmetic: reading the collapsed
    /// `mBuffers` member through `pointee` yields garbage for variable-length C arrays.
    func write(from abl: UnsafePointer<AudioBufferList>, frames: Int) {
        guard frames > 0, channels >= 1 else { return }
        let bufferCount = AudioBufferListAccess.bufferCount(abl)
        let buffers = AudioBufferListAccess.buffers(abl)
        let interleaved = bufferCount == 1 && channels > 1
        guard let firstData = buffers[0].mData else { return }
        let left = UnsafePointer(firstData.assumingMemoryBound(to: Float.self))
        let leftStride = interleaved ? channels : 1

        var right: UnsafePointer<Float>?
        var rightStride = 1
        if channels > 1 {
            if interleaved {
                right = left.advanced(by: 1)
                rightStride = channels
            } else if bufferCount > 1 {
                right = buffers[1].mData.flatMap { UnsafePointer($0.assumingMemoryBound(to: Float.self)) }
            }
        }

        os_unfair_lock_lock(&unfairLock)
        defer { os_unfair_lock_unlock(&unfairLock) }

        let used = Int(state.head &- state.tail)
        let free = capacityFrames - used
        if free < frames {
            let drop = frames - free
            state.tail = state.tail &+ UInt64(drop)
            state.overruns &+= UInt64(drop)
        }
        let start = Int(state.head & UInt64(mask))

        for i in 0..<frames {
            storage[(start + i) & mask] = left[i * leftStride]
        }
        if channels > 1, let right {
            let rightBase = storage + capacityFrames
            for i in 0..<frames {
                rightBase[(start + i) & mask] = right[i * rightStride]
            }
        }
        state.head = state.head &+ UInt64(frames)
        state.totalWritten &+= UInt64(frames)
    }

    func availableFrames() -> Int {
        os_unfair_lock_lock(&unfairLock)
        defer { os_unfair_lock_unlock(&unfairLock) }
        return Int(state.head &- state.tail)
    }

    /// Consumer side (AVAudioSourceNode render block) for up to 2 channels. Returns the
    /// number of frames actually read; the caller zero-fills the remainder.
    func read(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?, frames: Int) -> Int {
        guard frames > 0 else { return 0 }
        os_unfair_lock_lock(&unfairLock)
        defer { os_unfair_lock_unlock(&unfairLock) }

        let available = Int(state.head &- state.tail)
        let toRead = min(frames, available)
        if toRead < frames { state.underruns &+= UInt64(frames - toRead) }
        let start = Int(state.tail & UInt64(mask))

        for i in 0..<toRead {
            left[i] = storage[(start + i) & mask]
        }
        if let right {
            let rightBase = storage + capacityFrames
            for i in 0..<toRead {
                right[i] = rightBase[(start + i) & mask]
            }
        }
        state.tail = state.tail &+ UInt64(toRead)
        return toRead
    }

    /// Consumer side for arbitrary channel counts.
    func read(into channelPointers: UnsafeMutablePointer<UnsafeMutablePointer<Float>>, frames: Int) -> Int {
        guard frames > 0, channels >= 1 else { return 0 }
        os_unfair_lock_lock(&unfairLock)
        defer { os_unfair_lock_unlock(&unfairLock) }

        let available = Int(state.head &- state.tail)
        let toRead = min(frames, available)
        if toRead < frames { state.underruns &+= UInt64(frames - toRead) }
        let start = Int(state.tail & UInt64(mask))

        for ch in 0..<channels {
            let dst = channelPointers[ch]
            let srcBase = storage + ch * capacityFrames
            for i in 0..<toRead {
                dst[i] = srcBase[(start + i) & mask]
            }
        }
        state.tail = state.tail &+ UInt64(toRead)
        return toRead
    }
}
