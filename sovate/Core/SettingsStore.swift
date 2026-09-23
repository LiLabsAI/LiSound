import Foundation
import Carbon.HIToolbox

struct HotkeyCombo: Codable, Equatable {
    var carbonModifiers: UInt32
    var keyCode: UInt32

    var displayString: String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.keyName(keyCode))
        return parts.joined()
    }

    static func keyName(_ keyCode: UInt32) -> String {
        let letters: [UInt32: String] = [
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J",
            40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T",
            32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        ]
        return letters[keyCode] ?? "Key \(keyCode)"
    }
}

enum HotkeyCommand: String, CaseIterable, Codable, Identifiable {
    case power
    case showHide
    case nextPreset
    case previousPreset
    case nextOutput

    var id: String { rawValue }

    var title: String {
        switch self {
        case .power: "Turn Sovate On/Off"
        case .showHide: "Open/Close Sovate"
        case .nextPreset: "Next Preset"
        case .previousPreset: "Previous Preset"
        case .nextOutput: "Next Output"
        }
    }

    var defaultCombo: HotkeyCombo {
        switch self {
        case .power: HotkeyCombo(carbonModifiers: UInt32(controlKey | optionKey), keyCode: 35)
        case .showHide: HotkeyCombo(carbonModifiers: UInt32(controlKey | optionKey), keyCode: 3)
        case .nextPreset: HotkeyCombo(carbonModifiers: UInt32(controlKey | optionKey), keyCode: 45)
        case .previousPreset: HotkeyCombo(carbonModifiers: UInt32(controlKey | optionKey), keyCode: 11)
        case .nextOutput: HotkeyCombo(carbonModifiers: UInt32(controlKey | optionKey), keyCode: 31)
        }
    }
}

struct AppSettings: Codable, Equatable {
    var powerOnAtLaunch = false
    var followSystemDefaultOutput = true
    var prioritizeNewDevices = false
    var launchAtLogin = false
    var hotkeysEnabled = true
    var hotkeyCombos: [String: HotkeyCombo] = [:]
    var lastOutputUID: String?
    var lastPresetID: UUID?
    var viewIsPro = false

    func combo(for command: HotkeyCommand) -> HotkeyCombo {
        hotkeyCombos[command.rawValue] ?? command.defaultCombo
    }
}

@MainActor
final class SettingsStore {
    private(set) var settings: AppSettings {
        didSet { persist() }
    }

    private let defaults: UserDefaults
    private static let key = "AppSettings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        settings = copy
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
