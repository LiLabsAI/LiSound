import Foundation
import CoreAudio
import AVFoundation

final class SystemTap: @unchecked Sendable {
    private(set) var objectID: AudioObjectID = kAudioObjectUnknown
    private(set) var uuid = ""
    private(set) var format: AVAudioFormat?
    /// Authoritative bytes-per-frame from the tap ASBD — the IOProc divides buffer
    /// sizes by this, never by a guess derived from the buffer count.
    private(set) var bytesPerFrame: UInt32 = 0

    var isCreated: Bool { objectID != kAudioObjectUnknown }

    /// Creates a stereo global process tap capturing all system output audio except this
    /// app's own process. `mutedWhenTapped` silences the original output while we are
    /// reading it, so only our processed render is audible.
    func create(excludingPIDs pids: [Int32]) throws {
        guard !isCreated else { return }
        // The exclusion list takes process *object* IDs — PIDs must be translated first
        // (passing raw PIDs fails with kAudioHardwareBadObjectError '!obj').
        let excludeObjectIDs = pids.map { Self.audioObjectID(forPID: $0) }
        let description = CATapDescription(__stereoGlobalTapButExcludeProcesses: excludeObjectIDs.map { NSNumber(value: $0) })
        description.muteBehavior = .mutedWhenTapped

        var tapID = AudioObjectID(0)
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw AudioChainError.osStatus(status, "AudioHardwareCreateProcessTap") }
        objectID = tapID

        do {
            uuid = description.uuid.uuidString
            guard !uuid.isEmpty else {
                throw AudioChainError.invalidState("Tap description without UUID")
            }
            format = try readFormat()
            bytesPerFrame = format.map { $0.streamDescription.pointee.mBytesPerFrame } ?? 0
            guard bytesPerFrame > 0 else {
                throw AudioChainError.invalidState("Tap format without frame size")
            }
        } catch {
            destroy()
            throw error
        }
    }

    static func audioObjectID(forPID pid: Int32) -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var pidValue = pid
        var objectID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address,
            UInt32(MemoryLayout<Int32>.size), &pidValue,
            &size, &objectID)
        return status == noErr ? objectID : 0
    }

    func destroy() {
        guard isCreated else { return }
        let id = objectID
        objectID = kAudioObjectUnknown
        uuid = ""
        format = nil
        AudioHardwareDestroyProcessTap(id)
    }

    private func readFormat() throws -> AVAudioFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size)
        guard status == noErr, size > 0 else {
            throw AudioChainError.osStatus(status, "kAudioTapPropertyFormat size")
        }
        var asbd = AudioStreamBasicDescription()
        if Int(size) >= MemoryLayout<AudioFormatListItem>.stride {
            let itemCount = Int(size) / MemoryLayout<AudioFormatListItem>.stride
            var items = [AudioFormatListItem](repeating: AudioFormatListItem(), count: itemCount)
            status = items.withUnsafeMutableBytes { raw in
                guard let baseAddress = raw.baseAddress else { return -50 }
                return AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, baseAddress)
            }
            guard status == noErr else { throw AudioChainError.osStatus(status, "kAudioTapPropertyFormat") }
            asbd = items[0].mASBD
        } else {
            // Some builds return a bare ASBD rather than a format-list item.
            status = withUnsafeMutablePointer(to: &asbd) { ptr in
                AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, ptr)
            }
            guard status == noErr else { throw AudioChainError.osStatus(status, "kAudioTapPropertyFormat asbd") }
        }
        guard let fmt = AVAudioFormat(streamDescription: &asbd) else {
            throw AudioChainError.invalidState("Unsupported tap stream format")
        }
        return fmt
    }
}
