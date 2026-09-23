import Foundation

struct EffectValues: Codable, Equatable {
    var bass: Float = 0
    var fidelity: Float = 0
    var ambience: Float = 0
    var surround: Float = 0
    var dynamicBoost: Float = 0

    static let range: ClosedRange<Float> = 0...10

    static let neutral = EffectValues()
}

struct PresetBand: Codable, Equatable, Hashable {
    var frequency: Float
    var gain: Float

    static let gainRange: ClosedRange<Float> = -12...12
}

struct Preset: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var isBuiltIn: Bool
    var effects: EffectValues
    var eqOn: Bool
    var bands: [PresetBand]
    var filterQ: Float

    init(id: UUID = UUID(), name: String, isBuiltIn: Bool,
         effects: EffectValues = EffectValues(), eqOn: Bool = true,
         bands: [PresetBand] = [], filterQ: Float = 1.0) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.effects = effects
        self.eqOn = eqOn
        self.bands = bands
        self.filterQ = filterQ
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, isBuiltIn, effects, eqOn, bands, filterQ
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        effects = try c.decodeIfPresent(EffectValues.self, forKey: .effects) ?? .neutral
        eqOn = try c.decodeIfPresent(Bool.self, forKey: .eqOn) ?? true
        bands = try c.decodeIfPresent([PresetBand].self, forKey: .bands) ?? []
        filterQ = try c.decodeIfPresent(Float.self, forKey: .filterQ) ?? 1.0
    }
}

struct BuiltInPresetFile: Codable {
    var version: Int
    var presets: [Preset]
}
