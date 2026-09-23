import Foundation
import CoreAudio
import AVFoundation
import Observation
import os

@Observable
@MainActor
final class AppController {
    static let shared = AppController()
    private static let engineLog = Logger(subsystem: "com.aliahad.fxsound", category: "engine")
    let state = AppState()
    let presetStore: PresetStore
    let settingsStore: SettingsStore

    private let tap = SystemTap()
    private let aggregate = AggregateEngine()
    private let processingEngine = ProcessingEngine()
    private let deviceManager = DeviceManager()
    private let renderDSP = RenderDSP()
    private var spectrumAnalyzer: SpectrumAnalyzer?
    private var ringBuffer: RingBuffer?

    private var hotkeys = HotkeyManager()
    private var spectrumTimer: Timer?
    private var statsTimer: Timer?
    private var selfTestWorkItem: DispatchWorkItem?

    var toggleMainWindow: (() -> Void)?

    init() {
        self.presetStore = PresetStore()
        self.settingsStore = SettingsStore()
        deviceManager.onDevicesChanged = { [weak self] in
            Task { @MainActor [weak self] in self?.handleDevicesChanged() }
        }
        deviceManager.onDefaultOutputChanged = { [weak self] in
            Task { @MainActor [weak self] in self?.handleDefaultOutputChanged() }
        }
        deviceManager.startListening()
        bootstrap()
    }

    // MARK: - Bootstrap

    func bootstrap() {
        refreshOutputs()
        state.followSystemDefault = settingsStore.settings.followSystemDefaultOutput
        state.selectedOutputUID = settingsStore.settings.lastOutputUID
        state.viewIsPro = settingsStore.settings.viewIsPro
        syncPresetsIntoState()

        if let lastID = settingsStore.settings.lastPresetID,
           presetStore.preset(id: lastID) != nil {
            state.selectedPresetID = lastID
        } else if let def = presetStore.builtIns.first(where: { $0.name == "Default" }) {
            state.selectedPresetID = def.id
        }
        if let preset = state.selectedPreset {
            applyPresetToEditingState(preset)
        }

        registerHotkeys()

        // FxSound (Windows) CLI parity: `fxsound --power=1` starts processing at launch,
        // `--view=2` opens in Pro view.
        if ProcessInfo.processInfo.arguments.contains("--power=1") {
            powerOn()
        } else if settingsStore.settings.powerOnAtLaunch {
            powerOn()
        }
        if ProcessInfo.processInfo.arguments.contains("--view=2") {
            setViewIsPro(true)
        }
    }

    func prepareForTermination() {
        autoSaveModifiedPreset()
        powerOff()
        deviceManager.stopListening()
        hotkeys.unregisterAll()
        settingsStore.update { s in
            s.lastPresetID = state.selectedPresetID
            s.viewIsPro = state.viewIsPro
            s.followSystemDefaultOutput = state.followSystemDefault
        }
    }

    // MARK: - Presets

    private func syncPresetsIntoState() {
        state.presets = presetStore.allPresets
    }

    func selectPreset(id: Preset.ID) {
        guard id != state.selectedPresetID else { return }
        autoSaveModifiedPreset()
        state.selectedPresetID = id
        if let preset = state.selectedPreset {
            applyPresetToEditingState(preset)
        }
        settingsStore.update { $0.lastPresetID = id }
    }

    private func applyPresetToEditingState(_ preset: Preset) {
        state.eqOn = preset.eqOn
        state.bands = preset.bands
        state.filterQ = preset.filterQ
        state.effects = preset.effects
        state.selectedModified = false
        pushParamsToEngine()
    }

    private func markEdited() {
        if let preset = state.selectedPreset {
            state.selectedModified = currentEditingPreset() != preset
        }
        pushParamsToEngine()
    }

    private func currentEditingPreset() -> Preset {
        Preset(
            id: state.selectedPresetID ?? UUID(),
            name: state.selectedPreset?.name ?? "",
            isBuiltIn: state.selectedPreset?.isBuiltIn ?? false,
            effects: state.effects,
            eqOn: state.eqOn,
            bands: state.bands,
            filterQ: state.filterQ)
    }

    func autoSaveModifiedPreset() {
        guard state.selectedModified, let preset = state.selectedPreset else { return }
        if preset.isBuiltIn {
            var edited = currentEditingPreset()
            edited.id = preset.id
            edited.name = preset.name
            presetStore.saveBuiltInOverride(edited)
            state.selectedModified = false
            syncPresetsIntoState()
        } else {
            var updated = currentEditingPreset()
            updated.isBuiltIn = false
            presetStore.addOrUpdateUserPreset(updated)
            state.selectedModified = false
            syncPresetsIntoState()
        }
    }

    func saveNewPreset(named rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard presetStore.isNameValid(name) else { return false }
        var preset = currentEditingPreset()
        preset.id = UUID()
        preset.name = name
        preset.isBuiltIn = false
        presetStore.addOrUpdateUserPreset(preset)
        state.selectedPresetID = preset.id
        state.selectedModified = false
        syncPresetsIntoState()
        settingsStore.update { $0.lastPresetID = preset.id }
        return true
    }

    func overwriteUserPreset() -> Bool {
        guard let preset = state.selectedPreset, !preset.isBuiltIn else { return false }
        var updated = currentEditingPreset()
        updated.id = preset.id
        updated.name = preset.name
        updated.isBuiltIn = false
        presetStore.addOrUpdateUserPreset(updated)
        state.selectedModified = false
        syncPresetsIntoState()
        return true
    }

    func renameSelectedPreset(to rawName: String) -> Bool {
        guard let preset = state.selectedPreset, !preset.isBuiltIn else { return false }
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard presetStore.isNameValid(name, excluding: preset.id) else { return false }
        var updated = preset
        updated.name = name
        presetStore.addOrUpdateUserPreset(updated)
        syncPresetsIntoState()
        return true
    }

    func deleteSelectedPreset() {
        guard let preset = state.selectedPreset, !preset.isBuiltIn else { return }
        presetStore.deleteUserPreset(id: preset.id)
        syncPresetsIntoState()
        if let fallback = state.presets.first(where: { $0.name == "Default" }) ?? state.presets.first {
            state.selectedPresetID = fallback.id
            applyPresetToEditingState(fallback)
        }
    }

    func undoPresetChanges() {
        guard let preset = state.selectedPreset else { return }
        applyPresetToEditingState(preset)
    }

    func resetAllPresets() {
        presetStore.deleteAllBuiltInOverrides()
        syncPresetsIntoState()
        if let current = state.selectedPreset {
            applyPresetToEditingState(current)
        }
    }

    // MARK: - Editing state mutations

    func setEQBandGain(_ gain: Float, index: Int) {
        guard state.bands.indices.contains(index) else { return }
        state.bands[index].gain = min(max(gain, PresetBand.gainRange.lowerBound), PresetBand.gainRange.upperBound)
        markEdited()
    }

    func setBandFrequency(_ frequency: Float, index: Int) {
        guard state.bands.indices.contains(index) else { return }
        let clamped = EQParameters.clampFrequency(frequency, index: index, count: state.bands.count)
        state.bands[index].frequency = clamped
        markEdited()
    }

    func setBandCount(_ count: EQBandCount) {
        // Keep the user's curve shape: interpolate existing gains onto the new centers.
        state.bands = EQParameters.resample(state.bands, to: count.rawValue)
        markEdited()
    }

    func setFilterQ(_ q: Float) {
        state.filterQ = min(max(q, EQParameters.qRange.lowerBound), EQParameters.qRange.upperBound)
        markEdited()
    }

    func setEQOn(_ on: Bool) {
        state.eqOn = on
        markEdited()
    }

    func setEffect(_ keyPath: WritableKeyPath<EffectValues, Float>, to value: Float) {
        state.effects[keyPath: keyPath] = min(max(value, 0), 10)
        markEdited()
    }

    func setMasterGain(_ db: Float) {
        state.masterGainDB = min(max(db, -20), 20)
        markEdited()
    }

    func setBalance(_ db: Float) {
        state.balanceDB = min(max(db, -20), 20)
        pushParamsToEngine()
    }

    func setLeveling(_ db: Float) {
        state.levelingDB = min(max(db, 0), 4)
        pushParamsToEngine()
    }

    // MARK: - Engine parameters

    private func pushParamsToEngine() {
        var nodeBands: [ProcessingEngine.EQNodeBand] = []
        if state.eqOn {
            let bandwidth = EQParameters.bandwidthOctaves(count: max(state.bands.count, 2), q: state.filterQ)
            for band in state.bands {
                nodeBands.append(ProcessingEngine.EQNodeBand(
                    type: .parametric, frequency: band.frequency,
                    gainDB: band.gain, bandwidthOctaves: bandwidth, bypass: false))
            }
        }
        if state.effects.bass > 0.01 {
            nodeBands.append(ProcessingEngine.EQNodeBand(
                type: .lowShelf, frequency: 100, gainDB: state.effects.bass * 1.2,
                bandwidthOctaves: 1, bypass: false))
        }
        if state.effects.fidelity > 0.01 {
            nodeBands.append(ProcessingEngine.EQNodeBand(
                type: .highShelf, frequency: 7000, gainDB: state.effects.fidelity * 0.9,
                bandwidthOctaves: 1, bypass: false))
        }
        if state.effects.dynamicBoost > 0.01 {
            let amount = state.effects.dynamicBoost
            nodeBands.append(ProcessingEngine.EQNodeBand(
                type: .lowShelf, frequency: 80, gainDB: amount * 0.8,
                bandwidthOctaves: 1, bypass: false))
            nodeBands.append(ProcessingEngine.EQNodeBand(
                type: .highShelf, frequency: 10000, gainDB: amount * 0.5,
                bandwidthOctaves: 1, bypass: false))
        }

        processingEngine.updateParams(ProcessingEngine.Params(
            eqBands: nodeBands,
            masterGainDB: state.masterGainDB,
            limiterEnabled: state.masterGainDB > 0.01))

        let width = min((state.effects.ambience * 0.35 + state.effects.surround * 0.55) / 10, 0.9)
        renderDSP.setParams(RenderDSP.Params(
            balanceDB: state.balanceDB,
            width: width,
            levelingDB: state.levelingDB))
    }

    // MARK: - Power

    func togglePower() {
        state.powerOn ? powerOff() : powerOn()
    }

    func powerOn() {
        guard !state.powerOn else { return }
        state.engineError = nil
        do {
            let outputID = try resolveOutputDeviceID()
            try tap.create(excludingPIDs: [ProcessInfo.processInfo.processIdentifier])
            guard let format = tap.format, !tap.uuid.isEmpty else {
                throw AudioChainError.invalidState("Tap created without a stream format")
            }
            let channels = max(1, Int(format.channelCount))
            let ring = RingBuffer(capacityFrames: 8192, channels: channels)
            ringBuffer = ring
            let analyzer = SpectrumAnalyzer(sampleRate: Float(format.sampleRate))
            spectrumAnalyzer = analyzer

            try aggregate.start(outputDevice: outputID, tapUUID: tap.uuid, channels: channels) { [weak ring] abl, frames in
                ring?.write(from: abl, frames: Int(frames))
            }
            // The engine renders to the real device; binding it to the tap-aggregate
            // deadlocks in AUHAL's server round-trip (verified via process sample).
            try processingEngine.start(
                ring: ring, dsp: renderDSP, spectrum: analyzer,
                tapFormat: format, outputDevice: outputID)

            state.powerOn = true
            Self.engineLog.info("chain started: output=\(outputID, privacy: .public) tapUUID=\(self.tap.uuid, privacy: .public) format=\(Int(format.sampleRate), privacy: .public)Hz x\(Int(format.channelCount), privacy: .public)ch")
            startSpectrumTimer()
            startStatsTimer()
            schedulePermissionSelfTest()
        } catch {
            teardownChain()
            state.engineError = error.localizedDescription
            state.powerOn = false
            Self.engineLog.error("powerOn failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func powerOff() {
        guard state.powerOn else { return }
        teardownChain()
        state.powerOn = false
        state.spectrum = Array(repeating: 0, count: SpectrumAnalyzer.bandCount)
        state.showPermissionHelp = false
    }

    private func teardownChain() {
        selfTestWorkItem?.cancel()
        selfTestWorkItem = nil
        statsTimer?.invalidate()
        statsTimer = nil
        spectrumTimer?.invalidate()
        spectrumTimer = nil
        processingEngine.stop()
        aggregate.stop()
        tap.destroy()
        ringBuffer = nil
        spectrumAnalyzer = nil
        renderDSP.reset()
        Self.engineLog.info("chain stopped")
    }

    private func resolveOutputDeviceID() throws -> AudioDeviceID {
        let outputs = deviceManager.devices()
        if !state.followSystemDefault, let uid = state.selectedOutputUID,
           let match = outputs.first(where: { $0.uid == uid }) {
            return match.id
        }
        if let defaultID = deviceManager.defaultOutputDeviceID() {
            return defaultID
        }
        throw AudioChainError.invalidState("No output audio device found")
    }

    private func schedulePermissionSelfTest() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state.powerOn else { return }
            if let ring = self.ringBuffer, ring.statistics.totalWritten == 0 {
                self.state.permissionState = .silentFailure
                self.state.showPermissionHelp = true
                Self.engineLog.error("self-test FAILED: tap delivered 0 frames — Audio Recording permission missing or denied")
            } else if let ring = self.ringBuffer {
                self.state.permissionState = .granted
                Self.engineLog.info("self-test passed: tap delivered \(ring.statistics.totalWritten, privacy: .public) frames")
            }
        }
        selfTestWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    private func startStatsTimer() {
        statsTimer?.invalidate()
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.state.powerOn, let ring = self.ringBuffer else { return }
                let stats = ring.statistics
                let levels = self.spectrumAnalyzer?.currentLevels() ?? []
                let peak = levels.max() ?? 0
                Self.engineLog.info("stats: captured=\(stats.totalWritten, privacy: .public) overruns=\(stats.overruns, privacy: .public) underruns=\(stats.underruns, privacy: .public) spectrumPeak=\(peak, privacy: .public) ioProcs=\(self.aggregate.ioProcStats.invocations, privacy: .public) renders=\(self.processingEngine.renderCount, privacy: .public)")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        statsTimer = timer
    }

    // MARK: - Outputs

    func refreshOutputs() {
        state.outputs = deviceManager.devices()
    }

    func selectOutput(uid: String?) {
        state.selectedOutputUID = uid
        state.followSystemDefault = (uid == nil)
        settingsStore.update {
            $0.lastOutputUID = uid
            $0.followSystemDefaultOutput = uid == nil
        }
        restartChainIfRunning()
    }

    func setFollowSystemDefault(_ follow: Bool) {
        state.followSystemDefault = follow
        if follow { state.selectedOutputUID = nil }
        settingsStore.update {
            $0.followSystemDefaultOutput = follow
            $0.lastOutputUID = follow ? nil : $0.lastOutputUID
        }
        restartChainIfRunning()
    }

    func setPrioritizeNewDevices(_ prioritize: Bool) {
        settingsStore.update { $0.prioritizeNewDevices = prioritize }
    }

    var prioritizeNewDevices: Bool {
        settingsStore.settings.prioritizeNewDevices
    }

    func cycleToNextOutput() {
        let list = state.sortedOutputs
        guard list.count > 1 else { return }
        let currentUID = state.selectedOutputUID
            ?? deviceManager.defaultOutputDeviceID().flatMap { id in list.first { $0.id == id }?.uid }
        guard let index = list.firstIndex(where: { $0.uid == currentUID }) else {
            selectOutput(uid: list.first?.uid)
            return
        }
        let next = list[(index + 1) % list.count]
        selectOutput(uid: next.uid)
    }

    private func restartChainIfRunning() {
        guard state.powerOn else { return }
        powerOff()
        powerOn()
    }

    private func handleDevicesChanged() {
        let previousUIDs = Set(state.outputs.map { $0.uid })
        refreshOutputs()
        let newUIDs = Set(state.outputs.map { $0.uid })
        let added = newUIDs.subtracting(previousUIDs)

        if state.powerOn, prioritizeNewDevices, added.count == 1,
           let newUID = added.first {
            selectOutput(uid: newUID)
            return
        }

        guard state.powerOn else { return }
        let boundUID = state.selectedOutputUID
        let outputStillExists = boundUID.flatMap { uid in state.outputs.first { $0.uid == uid } } != nil
        if boundUID != nil && !outputStillExists {
            state.selectedOutputUID = nil
            state.followSystemDefault = true
            restartChainIfRunning()
        }
    }

    private func handleDefaultOutputChanged() {
        refreshOutputs()
        guard state.powerOn, state.followSystemDefault else { return }
        restartChainIfRunning()
    }

    // MARK: - Spectrum & self test

    private func startSpectrumTimer() {
        spectrumTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.state.powerOn else { return }
                self.state.spectrum = self.spectrumAnalyzer?.currentLevels()
                    ?? Array(repeating: 0, count: SpectrumAnalyzer.bandCount)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        spectrumTimer = timer
    }

    // MARK: - Hotkeys

    func registerHotkeys() {
        let enabled = settingsStore.settings.hotkeysEnabled
        guard enabled else {
            hotkeys.unregisterAll()
            return
        }
        var combos: [HotkeyCommand: HotkeyCombo] = [:]
        for command in HotkeyCommand.allCases {
            combos[command] = settingsStore.settings.combo(for: command)
        }
        hotkeys.register(combos: combos) { [weak self] command in
            Task { @MainActor in
                self?.handleHotkey(command)
            }
        }
    }

    private func handleHotkey(_ command: HotkeyCommand) {
        switch command {
        case .power: togglePower()
        case .showHide: toggleMainWindow?()
        case .nextPreset: cyclePreset(+1)
        case .previousPreset: cyclePreset(-1)
        case .nextOutput: cycleToNextOutput()
        }
    }

    private func cyclePreset(_ direction: Int) {
        let list = state.presets
        guard list.count > 1 else { return }
        let index = list.firstIndex { $0.id == state.selectedPresetID } ?? 0
        let next = list[((index + direction) % list.count + list.count) % list.count]
        selectPreset(id: next.id)
    }

    // MARK: - Settings passthrough

    func setPowerOnAtLaunch(_ enabled: Bool) {
        settingsStore.update { $0.powerOnAtLaunch = enabled }
    }

    var powerOnAtLaunch: Bool {
        settingsStore.settings.powerOnAtLaunch
    }

    func setHotkeysEnabled(_ enabled: Bool) {
        settingsStore.update { $0.hotkeysEnabled = enabled }
        registerHotkeys()
    }

    var hotkeysEnabled: Bool {
        settingsStore.settings.hotkeysEnabled
    }

    func currentCombo(for command: HotkeyCommand) -> HotkeyCombo? {
        guard hotkeysEnabled else { return nil }
        return settingsStore.settings.combo(for: command)
    }

    func setHotkeyCombo(_ combo: HotkeyCombo, for command: HotkeyCommand) {
        settingsStore.update { $0.hotkeyCombos[command.rawValue] = combo }
        registerHotkeys()
    }

    func setLaunchAtLogin(_ enabled: Bool) -> Error? {
        settingsStore.update { $0.launchAtLogin = enabled }
        return LoginItem.setEnabled(enabled)
    }

    var launchAtLogin: Bool {
        settingsStore.settings.launchAtLogin
    }

    func setViewIsPro(_ isPro: Bool) {
        state.viewIsPro = isPro
        settingsStore.update { $0.viewIsPro = isPro }
    }
}
