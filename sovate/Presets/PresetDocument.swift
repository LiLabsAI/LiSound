import SwiftUI
import UniformTypeIdentifiers

/// FileDocument wrapper so presets can be exported/imported through the standard
/// macOS save/open panels as JSON files.
struct PresetDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var preset: Preset

    init(preset: Preset) {
        self.preset = preset
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let decoded = try? JSONDecoder().decode(Preset.self, from: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        preset = decoded
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = (try? JSONEncoder().encode(preset)) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}
