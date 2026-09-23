import Foundation
import CryptoKit

@MainActor
final class PresetStore {
    static let userPresetsFolderName = "Presets"
    static let customScratchName = "Custom"
    private static let legacyOverridesFolderName = "BuiltInOverrides"

    private(set) var builtIns: [Preset] = []
    private(set) var userPresets: [Preset] = []

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let directoryOverride: URL?

    var userDirectory: URL {
        if let directoryOverride { return directoryOverride }
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Sovate", isDirectory: true)
        return base.appendingPathComponent(Self.userPresetsFolderName, isDirectory: true)
    }

    init(directoryOverride: URL? = nil) {
        self.directoryOverride = directoryOverride
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        loadBuiltIns()
        loadUserPresets()
    }

    /// Deterministic ID so a built-in preset keeps its identity across launches
    /// (random IDs would break "restore last preset" persistence).
    static func stableID(for name: String) -> UUID {
        let digest = Array(Insecure.MD5.hash(data: Data("com.aliahad.sovate.builtin.\(name)".utf8)))
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }

    var allPresets: [Preset] { builtIns + userPresets }

    func preset(id: UUID) -> Preset? {
        allPresets.first { $0.id == id }
    }

    private func loadBuiltIns() {
        guard let data = BuiltInPresets.json.data(using: .utf8),
              let file = try? decoder.decode(BuiltInPresetFile.self, from: data) else { return }
        builtIns = file.presets.map { preset in
            var p = preset
            p.isBuiltIn = true
            p.id = Self.stableID(for: p.name)
            return p
        }
    }

    private func loadUserPresets() {
        try? fileManager.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        guard let files = try? fileManager.contentsOfDirectory(
            at: userDirectory, includingPropertiesForKeys: nil) else { return }
        userPresets = files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  var preset = try? decoder.decode(Preset.self, from: data) else { return nil }
            preset.isBuiltIn = false
            return preset
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func fileURL(for preset: Preset) -> URL {
        userDirectory.appendingPathComponent("\(preset.id.uuidString).json")
    }

    private func persist(_ preset: Preset) {
        try? fileManager.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(preset) else { return }
        try? data.write(to: fileURL(for: preset), options: .atomic)
    }

    func addOrUpdateUserPreset(_ preset: Preset) {
        if let index = userPresets.firstIndex(where: { $0.id == preset.id }) {
            userPresets[index] = preset
        } else {
            userPresets.append(preset)
            userPresets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        persist(preset)
    }

    func deleteUserPreset(id: UUID) {
        guard let index = userPresets.firstIndex(where: { $0.id == id }) else { return }
        let preset = userPresets.remove(at: index)
        try? fileManager.removeItem(at: fileURL(for: preset))
    }

    func isNameValid(_ name: String, excluding id: UUID? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 64 else { return false }
        return !allPresets.contains { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    /// Imports a preset from an exported JSON file, assigning a fresh ID and a
    /// non-colliding name. Returns nil if the file isn't a valid preset.
    @discardableResult
    func importPreset(from url: URL) -> Preset? {
        guard let data = try? Data(contentsOf: url),
              var preset = try? decoder.decode(Preset.self, from: data) else { return nil }
        var name = preset.name.isEmpty ? "Imported Preset" : preset.name
        var suffix = 2
        while !isNameValid(name) {
            name = "\(preset.name.isEmpty ? "Imported Preset" : preset.name) \(suffix)"
            suffix += 1
        }
        preset.id = UUID()
        preset.name = name
        preset.isBuiltIn = false
        addOrUpdateUserPreset(preset)
        return preset
    }

    /// The rolling scratch preset edits detach into: reuses the same "Custom" slot so
    /// experimenting never multiplies presets. Returns the stored preset.
    @discardableResult
    func createOrResetCustom(values: Preset) -> Preset {
        var custom: Preset
        if let existing = userPresets.first(where: { $0.name == Self.customScratchName }) {
            custom = existing
        } else {
            custom = Preset(name: Self.customScratchName, isBuiltIn: false)
            userPresets.append(custom)
            userPresets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        custom.effects = values.effects
        custom.eqOn = values.eqOn
        custom.bands = values.bands
        custom.filterQ = values.filterQ
        persist(custom)
        return custom
    }


    func resetBuiltIns() {
        loadBuiltIns()
    }
}
