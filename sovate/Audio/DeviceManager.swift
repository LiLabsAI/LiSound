import Foundation
import CoreAudio

struct AudioDeviceInfo: Identifiable, Equatable, Sendable {
    var id: AudioDeviceID
    var uid: String
    var name: String
    var transportType: UInt32
    var isDefault: Bool


    var transportSymbol: String {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn: "hifispeaker"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: "tv"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: "airpods"
        case kAudioDeviceTransportTypeAirPlay: "airplayaudio"
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt: "cable.connector"
        default: "speaker.wave.2"
        }
    }
}

final class DeviceManager: @unchecked Sendable {
    var onDevicesChanged: (@Sendable () -> Void)?
    var onDefaultOutputChanged: (@Sendable () -> Void)?

    private let listenerQueue = DispatchQueue(label: "com.aliahad.sovate.devicelistener")
    private var listening = false

    func devices() -> [AudioDeviceInfo] {
        let defaultID = defaultOutputDeviceID()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.stride
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        var result: [AudioDeviceInfo] = []
        for id in ids where hasOutputStreams(id) {
            guard let info = deviceInfo(id, defaultID: defaultID) else { continue }
            // Hide our own private aggregate and transient system aggregates — they
            // are capture plumbing, not real outputs the user can pick.
            if info.uid.hasPrefix("com.aliahad.sovate") { continue }
            if info.transportType == kAudioDeviceTransportTypeAggregate { continue }
            if info.name.hasPrefix("CADefaultDeviceAggregate") { continue }
            result.append(info)
        }
        return result
    }

    func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != 0 else { return nil }
        return device
    }

    private func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    private func deviceInfo(_ id: AudioDeviceID, defaultID: AudioDeviceID?) -> AudioDeviceInfo? {
        guard let name = Self.readString(id, kAudioObjectPropertyName),
              let uid = try? AggregateEngine.deviceUID(for: id) else { return nil }
        var transport: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)
        return AudioDeviceInfo(id: id, uid: uid, name: name, transportType: transport,
                               isDefault: id == defaultID)
    }

    static func readString(_ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size) == noErr, size > 0 else { return nil }
        var value: CFString? = nil
        let status = withUnsafeMutablePointer(to: &value) { valuePtr in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, valuePtr)
        }
        guard status == noErr else { return nil }
        return value as String?
    }

    func startListening() {
        guard !listening else { return }
        listening = true
        addListener(kAudioHardwarePropertyDevices) { [weak self] in
            self?.onDevicesChanged?()
        }
        addListener(kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
            self?.onDefaultOutputChanged?()
        }
    }

    func stopListening() {
        guard listening else { return }
        listening = false
        removeListener(kAudioHardwarePropertyDevices)
        removeListener(kAudioHardwarePropertyDefaultOutputDevice)
    }

    private var storedBlocks: [AudioObjectPropertySelector: AudioObjectPropertyListenerBlock] = [:]

    private func addListener(_ selector: AudioObjectPropertySelector, handler: @escaping @Sendable () -> Void) {
        guard storedBlocks[selector] == nil else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async {
                handler()
            }
        }
        storedBlocks[selector] = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, listenerQueue, block)
    }

    private func removeListener(_ selector: AudioObjectPropertySelector) {
        guard let block = storedBlocks.removeValue(forKey: selector) else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, listenerQueue, block)
    }
}
