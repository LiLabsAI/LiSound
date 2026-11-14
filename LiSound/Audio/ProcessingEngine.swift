import Foundation
import CoreAudio
import AudioUnit
import AVFoundation
import os

/// Owns the AVAudioEngine graph:
///   AVAudioSourceNode (ring pull + RenderDSP) → AVAudioUnitEQ (EQ + bass/treble shelves)
///   → pre-gain mixer → peak limiter → main mixer → output node (bound to the aggregate).
final class ProcessingEngine: @unchecked Sendable {
    static let shelfBands = 2

    struct EQNodeBand: Sendable {
        enum FilterType: Sendable {
            case parametric
            case lowShelf
            case highShelf
        }

        var type: FilterType
        var frequency: Float
        var gainDB: Float
        var bandwidthOctaves: Float
        var bypass: Bool
    }

    struct Params: Sendable {
        var eqBands: [EQNodeBand] = []
        var masterGainDB: Float = 0
        var limiterEnabled = false
    }

    let engine = AVAudioEngine()
    private let eq = AVAudioUnitEQ(numberOfBands: 40)
    private let limiter: AVAudioUnitEffect = {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0)
        return AVAudioUnitEffect(audioComponentDescription: description)
    }()
    private var sourceNode: AVAudioSourceNode?
    private var runningFormat: AVAudioFormat?

    private(set) var isRunning = false

    private let paramsLock = OSAllocatedUnfairLock<Params>(initialState: Params())
    private var renderLock = os_unfair_lock()
    private var renderInvocations: UInt64 = 0

    var renderCount: UInt64 {
        os_unfair_lock_lock(&renderLock)
        defer { os_unfair_lock_unlock(&renderLock) }
        return renderInvocations
    }

    func start(ring: RingBuffer, dsp: RenderDSP, bars: SpectrumBars,
               tapFormat: AVAudioFormat, outputDevice: AudioDeviceID) throws {
        guard !isRunning else { return }
        stopNodes()

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: max(tapFormat.sampleRate, 8000),
            channels: AVAudioChannelCount(max(2, Int(tapFormat.channelCount))),
            interleaved: false) else {
            throw AudioChainError.invalidState("Unsupported render format")
        }
        let channelCount = Int(format.channelCount)

        let node = AVAudioSourceNode(format: format) { [weak ring, weak dsp, weak bars] _, _, frameCount, outputData in
            guard let ring, let dsp else { return noErr }
            let frames = Int(frameCount)

            // Read the AudioBufferList exclusively through the raw-pointer helpers:
            // `pointee` access on this variable-length C struct returns garbage.
            let numberBuffers = AudioBufferListAccess.bufferCount(outputData)
            let buffers = AudioBufferListAccess.mutableBuffers(outputData)
            guard numberBuffers >= 1, let leftData = buffers[0].mData else { return noErr }
            let left = leftData.assumingMemoryBound(to: Float.self)
            let right: UnsafeMutablePointer<Float>? = (channelCount > 1 && numberBuffers > 1 && buffers[1].mData != nil)
                ? buffers[1].mData!.assumingMemoryBound(to: Float.self) : nil

            let read = ring.read(left: left, right: right, frames: frames)
            if read < frames {
                let silentFrames = frames - read
                memset(left + read, 0, silentFrames * MemoryLayout<Float>.size)
                if let right { memset(right + read, 0, silentFrames * MemoryLayout<Float>.size) }
            }
            dsp.process(left: left, right: right, frames: frames)
            bars?.analyze(left: left, right: right, frames: frames, sampleRate: Float(format.sampleRate))
            os_unfair_lock_lock(&self.renderLock)
            self.renderInvocations &+= 1
            os_unfair_lock_unlock(&self.renderLock)
            return noErr
        }
        sourceNode = node

        engine.attach(node)
        engine.attach(eq)
        engine.attach(limiter)

        engine.connect(node, to: eq, format: format)
        engine.connect(eq, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)

        guard let outputAudioUnit = engine.outputNode.audioUnit else {
            throw AudioChainError.invalidState("Output node has no audio unit")
        }
        var deviceID = outputDevice
        let status = AudioUnitSetProperty(
            outputAudioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0,
            &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            throw AudioChainError.osStatus(status, "bind output device")
        }

        engine.prepare()
        try engine.start()
        runningFormat = format
        isRunning = true

        let params = paramsLock.withLock { $0 }
        apply(params: params)
    }

    func stop() {
        guard isRunning else { return }
        stopNodes()
        isRunning = false
        runningFormat = nil
    }

    private func stopNodes() {
        engine.stop()
        for node in [sourceNode, eq, limiter].compactMap({ $0 }) {
            engine.detach(node)
        }
        sourceNode = nil
    }

    func updateParams(_ params: Params) {
        paramsLock.withLock { $0 = params }
        if isRunning { apply(params: params) }
    }

    private func apply(params: Params) {
        let limiterUnit = limiter.audioUnit
        let bands = eq.bands
        for (index, configured) in params.eqBands.enumerated() where index < bands.count {
            let band = bands[index]
            switch configured.type {
            case .parametric: band.filterType = .parametric
            case .lowShelf: band.filterType = .lowShelf
            case .highShelf: band.filterType = .highShelf
            }
            band.frequency = configured.frequency
            band.gain = configured.gainDB
            band.bandwidth = configured.bandwidthOctaves
            band.bypass = configured.bypass
        }
        for index in params.eqBands.count..<bands.count {
            bands[index].bypass = true
        }
        eq.globalGain = params.masterGainDB

        // Negative limiter pre-gain reserves headroom so boosts stay clean; the limiter
        // clamps inter-sample peaks at 0 dBFS either way.
        let limiterPreGain: Float = params.limiterEnabled ? -max(params.masterGainDB, 0) * 0.35 : 0
        AudioUnitSetParameter(limiterUnit, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, limiterPreGain, 0)
        AudioUnitSetParameter(limiterUnit, kLimiterParam_AttackTime, kAudioUnitScope_Global, 0, 0.003, 0)
        AudioUnitSetParameter(limiterUnit, kLimiterParam_DecayTime, kAudioUnitScope_Global, 0, 0.24, 0)
        limiter.bypass = !params.limiterEnabled && params.masterGainDB <= 0
    }
}
