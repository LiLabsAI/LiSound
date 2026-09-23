import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var powerOn = false
    var permissionState: PermissionState = .unknown
    var engineError: String?

    var presets: [Preset] = []
    var selectedPresetID: Preset.ID?
    var selectedModified = false

    var outputs: [AudioDeviceInfo] = []
    var selectedOutputUID: String?
    var followSystemDefault = true

    var eqOn = true
    var bands: [PresetBand] = EQParameters.defaultCenters(count: 10).map { PresetBand(frequency: $0, gain: 0) }
    var filterQ: Float = 1.0
    var effects = EffectValues()

    var masterGainDB: Float = 0
    var balanceDB: Float = 0
    var levelingDB: Float = 0

    var spectrum: [Float] = Array(repeating: 0, count: SpectrumAnalyzer.bandCount)

    var viewIsPro = false
    var showPermissionHelp = false

    var selectedPreset: Preset? {
        presets.first { $0.id == selectedPresetID }
    }

    var sortedOutputs: [AudioDeviceInfo] {
        outputs.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
