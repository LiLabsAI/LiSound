import Foundation
import CoreAudio
import os

/// Private aggregate device binding a process tap (input side) to a real output device
/// (clock master). The IOProc receives the tapped system audio frames.
final class AggregateEngine: @unchecked Sendable {
    private static let ioLog = Logger(subsystem: "com.aliahad.fxsound", category: "aggregate")
    private(set) var deviceID: AudioDeviceID = kAudioObjectUnknown
    private(set) var outputDeviceID: AudioDeviceID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private(set) var aggregateUID = ""
    private var ioLock = os_unfair_lock()
    private var ioInvocations: UInt64 = 0
    private var ioLastFrames: UInt32 = 0

    var ioProcStats: (invocations: UInt64, lastFrames: UInt32) {
        os_unfair_lock_lock(&ioLock)
        defer { os_unfair_lock_unlock(&ioLock) }
        return (ioInvocations, ioLastFrames)
    }

    // C-string dictionary keys (#defines are not imported into Swift).
    private enum Keys {
        static let name = "name"
        static let uid = "uid"
        static let privateFlag = "private"
        static let master = "master"
        static let subdevices = "subdevices"
        static let taps = "taps"
        static let drift = "drift"
        static let tapAutoStart = "tapautostart"
    }

    var isRunning: Bool { deviceID != kAudioObjectUnknown }

    func start(outputDevice: AudioDeviceID, tapUUID: String, channels: Int,
               ioHandler: @escaping @Sendable (UnsafePointer<AudioBufferList>, UInt32) -> Void) throws {
        guard !isRunning else { return }
        let outputUID = try Self.deviceUID(for: outputDevice)
        let channelCount = max(1, channels)

        let description: [String: Any] = [
            Keys.name: "FxSound Processing",
            Keys.uid: "com.aliahad.fxsound.agg." + UUID().uuidString,
            Keys.privateFlag: true,
            Keys.master: outputUID,
            Keys.subdevices: [[Keys.uid: outputUID]],
            Keys.taps: [[Keys.uid: tapUUID, Keys.drift: true]],
        ]

        var aggregateID = AudioDeviceID(0)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard status == noErr else { throw AudioChainError.osStatus(status, "AudioHardwareCreateAggregateDevice") }
        deviceID = aggregateID
        outputDeviceID = outputDevice
        aggregateUID = description[Keys.uid] as? String ?? ""

        let capturedDeviceID = aggregateID
        var procID: AudioDeviceIOProcID?
        let createStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, capturedDeviceID, nil) {
            inNow, inInputData, inInputTime, outOutputData, outOutputTime in
            // Raw helpers only — `pointee` access on this variable-length C struct
            // returns garbage on this SDK.
            let bufferCount = AudioBufferListAccess.bufferCount(inInputData)
            let inputBuffers = AudioBufferListAccess.buffers(inInputData)
            var frames: UInt32 = 0
            if bufferCount > 0 {
                // 1 buffer = interleaved (channelCount frames-worth per sample slot);
                // multiple buffers = non-interleaved planar channels.
                let bytesPerFrame = (bufferCount == 1 && channelCount > 1)
                    ? UInt32(MemoryLayout<Float>.size) * UInt32(channelCount)
                    : UInt32(MemoryLayout<Float>.size)
                frames = inputBuffers[0].mDataByteSize / max(bytesPerFrame, 1)
            }
            ioHandler(inInputData, frames)
            os_unfair_lock_lock(&self.ioLock)
            self.ioInvocations &+= 1
            self.ioLastFrames = frames
            let invocation = self.ioInvocations
            os_unfair_lock_unlock(&self.ioLock)
            if invocation <= 3 {
                Self.ioLog.info("IOProc #\(invocation, privacy: .public): buffers=\(bufferCount, privacy: .public) bytes0=\(inputBuffers[0].mDataByteSize, privacy: .public) frames=\(frames, privacy: .public)")
            }
            let outBuffers = AudioBufferListAccess.mutableBuffers(outOutputData)
            let outCount = AudioBufferListAccess.bufferCount(outOutputData)
            for b in 0..<outCount {
                if let data = outBuffers[b].mData {
                    memset(data, 0, Int(outBuffers[b].mDataByteSize))
                }
            }
        }
        guard createStatus == noErr, let procID else {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            deviceID = kAudioObjectUnknown
            throw AudioChainError.osStatus(createStatus, "AudioDeviceCreateIOProcIDWithBlock")
        }
        ioProcID = procID

        let startStatus = AudioDeviceStart(capturedDeviceID, procID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(capturedDeviceID, procID)
            ioProcID = nil
            AudioHardwareDestroyAggregateDevice(capturedDeviceID)
            deviceID = kAudioObjectUnknown
            throw AudioChainError.osStatus(startStatus, "AudioDeviceStart")
        }
    }

    func stop() {
        guard isRunning else { return }
        let id = deviceID
        deviceID = kAudioObjectUnknown
        if let procID = ioProcID {
            AudioDeviceStop(id, procID)
            AudioDeviceDestroyIOProcID(id, procID)
            ioProcID = nil
        }
        AudioHardwareDestroyAggregateDevice(id)
        aggregateUID = ""
    }

    static func deviceUID(for deviceID: AudioDeviceID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard status == noErr, size > 0 else { throw AudioChainError.osStatus(status, "DeviceUID size") }
        var value: CFString? = nil
        status = withUnsafeMutablePointer(to: &value) { valuePtr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, valuePtr)
        }
        guard status == noErr, let uid = value as String? else {
            throw AudioChainError.osStatus(status, "DeviceUID")
        }
        return uid
    }
}
