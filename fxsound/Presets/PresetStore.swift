import Foundation
import CryptoKit

@MainActor
final class PresetStore {
    static let userPresetsFolderName = "Presets"
    static let overrideFolderName = "BuiltInOverrides"

    private(set) var builtIns: [Preset] = []
    private(set) var userPresets: [Preset] = []

    private var overrideIDs: Set<UUID> = []
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let directoryOverride: URL?

    var userDirectory: URL {
        if let directoryOverride { return directoryOverride }
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FxSound", isDirectory: true)
        return base.appendingPathComponent(Self.userPresetsFolderName, isDirectory: true)
    }

    var overrideDirectory: URL {
        if let directoryOverride { return directoryOverride.appendingPathComponent("Overrides", isDirectory: true) }
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FxSound", isDirectory: true)
        return base.appendingPathComponent(Self.overrideFolderName, isDirectory: true)
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
        let digest = Array(Insecure.MD5.hash(data: Data("com.aliahad.fxsound.builtin.\(name)".utf8)))
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
        loadBuiltInOverrides()
    }

    /// Built-in edits (auto-saved) live in a separate folder and are merged onto the
    /// factory values, so factory data stays pristine and reset is a delete.
    private func loadBuiltInOverrides() {
        try? fileManager.createDirectory(at: overrideDirectory, withIntermediateDirectories: true)
        guard let files = try? fileManager.contentsOfDirectory(
            at: overrideDirectory, includingPropertiesForKeys: nil) else { return }
        overrideIDs = []
        for url in files where url.pathExtension == "json" {
            guard let fileName = url.deletingPathExtension().path.split(separator: "/").last,
                  let id = UUID(uuidString: String(fileName)),
                  let index = builtIns.firstIndex(where: { $0.id == id }),
                  let data = try? Data(contentsOf: url),
                  var edited = try? decoder.decode(Preset.self, from: data) else { continue }
            edited.isBuiltIn = true
            edited.id = id
            edited.name = builtIns[index].name
            builtIns[index] = edited
            overrideIDs.insert(id)
        }
    }

    func hasOverride(id: UUID) -> Bool {
        overrideIDs.contains(id)
    }

    func saveBuiltInOverride(_ preset: Preset) {
        var updated = preset
        updated.isBuiltIn = true
        updated.id = preset.id
        try? fileManager.createDirectory(at: overrideDirectory, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(updated) else { return }
        try? data.write(
            to: overrideDirectory.appendingPathComponent("\(preset.id.uuidString).json"),
            options: .atomic)
        overrideIDs.insert(preset.id)
        if let index = builtIns.firstIndex(where: { $0.id == preset.id }) {
            builtIns[index] = updated
        }
    }

    func deleteAllBuiltInOverrides() {
        for id in overrideIDs {
            try? fileManager.removeItem(
                at: overrideDirectory.appendingPathComponent("\(id.uuidString).json"))
        }
        overrideIDs = []
        loadBuiltIns()
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

    func resetBuiltIns() {
        loadBuiltIns()
    }
}
