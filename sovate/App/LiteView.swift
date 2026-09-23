import SwiftUI
import UniformTypeIdentifiers

struct LiteView: View {
    @Environment(AppController.self) private var controller
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    PresetPicker()
                    OutputPicker()
                }
                VStack(alignment: .leading, spacing: 8) {
                    PresetPicker()
                    OutputPicker()
                }
            }
            masterGainRow
            Spacer(minLength: 12)
            VisualizerView(levels: state.amplitudes, isOn: state.powerOn)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(!state.powerOn)
        .opacity(state.powerOn ? 1 : 0.55)
    }

    private var masterGainRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.1")
                .foregroundStyle(FxTheme.textSecondary)
            Slider(value: Binding(
                get: { Double(state.masterGainDB) },
                set: { controller.setMasterGain(Float($0)) }),
                in: -20...20)
            Text("\(state.masterGainDB >= 0 ? "+" : "")\(state.masterGainDB, specifier: "%.1f") dB")
                .monospacedDigit()
                .frame(width: 74, alignment: .trailing)
                .foregroundStyle(FxTheme.textSecondary)
            Image(systemName: "speaker.wave.3")
                .foregroundStyle(FxTheme.textSecondary)
        }
        .help("Master gain boost (−20…+20 dB)")
    }
}

struct PresetPicker: View {
    @Environment(AppController.self) private var controller
    @Environment(AppState.self) private var state
    @State private var showSaveDialog = false
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportDocument: PresetDocument?
    @State private var newPresetName = ""
    @State private var importFailed = false

    var body: some View {
        HStack(spacing: 6) {
            menu
            saveButton
        }
        .sheet(isPresented: $showSaveDialog) {
            SavePresetSheet(newName: $newPresetName) {
                if controller.saveNewPreset(named: newPresetName) {
                    showSaveDialog = false
                }
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.json],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            if !controller.importPreset(from: url) {
                importFailed = true
            }
        }
        .fileExporter(isPresented: $showExporter,
                      document: exportDocument,
                      contentType: .json,
                      defaultFilename: "\(state.selectedPreset?.name ?? "Preset").json") { _ in }
        .alert("Import failed", isPresented: $importFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The selected file is not a valid Sovate preset.")
        }
    }

    private var menu: some View {
        Menu {
            Section("Presets") {
                ForEach(state.presets.filter { $0.isBuiltIn }) { preset in
                    presetButton(preset)
                }
            }
            if !state.presets.filter({ !$0.isBuiltIn }).isEmpty {
                Section("My Presets") {
                    ForEach(state.presets.filter { !$0.isBuiltIn }) { preset in
                        presetButton(preset)
                    }
                }
            }
            Section {
                Button("Save As New Preset…") { showSaveDialog = true }
                Button("Overwrite Preset") { controller.overwriteUserPreset() }
                    .disabled(!canOverwrite)
                Button("Undo Preset Changes") { controller.undoPresetChanges() }
                    .disabled(!state.selectedModified)
                if let selected = state.selectedPreset, !selected.isBuiltIn {
                    Button("Delete Preset") { controller.deleteSelectedPreset() }
                }
                Divider()
                Button("Export Preset…") {
                    exportDocument = PresetDocument(preset: controller.currentEditingPreset())
                    showExporter = true
                }
                Button("Import Preset…") { showImporter = true }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle")
                Text(state.selectedPreset?.name ?? "Choose Preset")
                if state.selectedModified {
                    Circle().fill(.orange).frame(width: 7, height: 7)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .focusable(false)
    }

    /// Explicit save: overwrite in place for user presets, "Save As New" for built-ins.
    private var saveButton: some View {
        Button {
            if state.selectedPreset?.isBuiltIn == false {
                controller.overwriteUserPreset()
            } else {
                newPresetName = ""
                showSaveDialog = true
            }
        } label: {
            Label("Save", systemImage: "square.and.arrow.down")
        }
        .disabled(!state.selectedModified)
        .help(state.selectedPreset?.isBuiltIn == false
              ? "Overwrite this preset with the current settings"
              : "Save the current settings as a new preset")
    }

    private var canOverwrite: Bool {
        state.selectedModified && state.selectedPreset?.isBuiltIn == false
    }

    private func presetButton(_ preset: Preset) -> some View {
        Button {
            controller.selectPreset(id: preset.id)
        } label: {
            HStack {
                Text(preset.name)
                if preset.id == state.selectedPresetID { Image(systemName: "checkmark") }
            }
        }
    }
}

struct OutputPicker: View {
    @Environment(AppController.self) private var controller
    @Environment(AppState.self) private var state

    var body: some View {
        Menu {
            Button {
                controller.setFollowSystemDefault(true)
            } label: {
                HStack {
                    Text("Follow System Default")
                    if state.followSystemDefault { Image(systemName: "checkmark") }
                }
            }
            Divider()
            ForEach(state.sortedOutputs) { device in
                Button {
                    controller.selectOutput(uid: device.uid)
                } label: {
                    HStack {
                        Image(systemName: device.transportSymbol)
                        Text(device.name)
                        if !state.followSystemDefault && device.uid == state.selectedOutputUID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: currentSymbol)
                Text(currentName).lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .focusable(false)
    }

    private var currentSymbol: String {
        if state.followSystemDefault { return "arrow.triangle.2.circlepath" }
        return state.outputs.first { $0.uid == state.selectedOutputUID }?.transportSymbol ?? "speaker.wave.2"
    }

    private var currentName: String {
        if state.followSystemDefault {
            let defaultName = state.outputs.first { $0.isDefault }?.name
            return defaultName.map { "Default (\($0))" } ?? "Follow System Default"
        }
        return state.outputs.first { $0.uid == state.selectedOutputUID }?.name ?? "Choose Output"
    }
}

struct SavePresetSheet: View {
    @Binding var newName: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Text("Save New Preset").font(.headline)
            TextField("Preset name", text: $newName)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 260)
            HStack {
                Button("Cancel") { dismiss() }
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }
}
