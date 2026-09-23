import Foundation
import Carbon.HIToolbox

final class HotkeyManager {
    var handler: ((HotkeyCommand) -> Void)?

    private var hotKeyRefs: [HotkeyCommand: EventHotKeyRef?] = [:]
    private static var commandMap: [UInt32: HotkeyCommand] = [:]
    private static var nextCommandID: UInt32 = 1
    private static var sharedHandler: ((HotkeyCommand) -> Void)?
    private static var installed = false

    func register(combos: [HotkeyCommand: HotkeyCombo], handler: @escaping (HotkeyCommand) -> Void) {
        unregisterAll()
        Self.sharedHandler = handler
        Self.installEventHandlerIfNeeded()

        for (command, combo) in combos {
            var ref: EventHotKeyRef?
            let commandID = Self.nextCommandID
            Self.nextCommandID += 1
            Self.commandMap[commandID] = command
            let hotKeyID = EventHotKeyID(signature: OSType(0x46583031), id: commandID)
            let status = RegisterEventHotKey(
                combo.keyCode,
                combo.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref)
            if status == noErr {
                hotKeyRefs[command] = ref
            }
        }
    }

    func unregisterAll() {
        for (command, ref) in hotKeyRefs {
            if let ref { UnregisterEventHotKey(ref) }
            hotKeyRefs[command] = nil
        }
        Self.commandMap.removeAll()
    }

    private static func installEventHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                guard let event else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID)
                guard status == noErr, let command = HotkeyManager.commandMap[hotKeyID.id] else { return noErr }
                HotkeyManager.sharedHandler?(command)
                return noErr
            },
            1, &eventType, nil, nil)
    }
}
