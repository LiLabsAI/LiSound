import Foundation
import CoreAudio

// Logic test harness for FxSound for Mac (plan9 §5 — unit gates).
// Compiled against the app's non-UI source files with swiftc; exits non-zero on failure.

var failures = 0
var checks = 0

func check(_ condition: Bool, _ label: String) {
    checks += 1
    if condition {
        print("  ✓ \(label)")
    } else {
        failures += 1
        print("  ✗ \(label)")
    }
}

// MARK: - RingBuffer

func testRingBuffer() {
    print("RingBuffer")
    let ring = RingBuffer(capacityFrames: 1000, channels: 2)

    let frames = 256
    let left = UnsafeMutablePointer<Float>.allocate(capacity: frames)
    let right = UnsafeMutablePointer<Float>.allocate(capacity: frames)
    defer { left.deallocate(); right.deallocate() }
    for i in 0..<frames {
        left[i] = Float(i)
        right[i] = Float(i) * 2
    }

    // Build a non-interleaved 2-channel AudioBufferList at the real mBuffers offset
    // (8 on arm64 — pointer alignment pads the list header).
    let ablPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
    defer { ablPointer.deallocate() }
    let rawList = UnsafeMutableRawPointer(ablPointer)
    rawList.storeBytes(of: UInt32(2), as: UInt32.self)
    let buffers = AudioBufferListAccess.mutableBuffers(ablPointer)
    buffers[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: left)
    buffers[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: right)
    let listPtr = UnsafePointer<AudioBufferList>(ablPointer)
    check(AudioBufferListAccess.bufferCount(listPtr) == 2, "bufferCount round-trips through raw offset")

    let dummy = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    defer { dummy.deallocate() }
    let written = ring.read(left: dummy, right: nil, frames: 0)
    check(written == 0, "read on empty ring returns 0")

    ring.write(from: listPtr, frames: frames)
    check(ring.availableFrames() == frames, "availableFrames after write")

    let outL = UnsafeMutablePointer<Float>.allocate(capacity: frames)
    let outR = UnsafeMutablePointer<Float>.allocate(capacity: frames)
    defer { outL.deallocate(); outR.deallocate() }
    let got = ring.read(left: outL, right: outR, frames: frames)
    check(got == frames, "read returns all written frames")
    check(outL[0] == 0 && outL[100] == 100, "left channel round-trip preserves samples")
    check(outR[50] == 100, "right channel round-trip preserves samples")
    check(ring.availableFrames() == 0, "ring drains to empty")

    // wrap-around across power-of-two boundary
    for round in 0..<9 {
        for i in 0..<frames {
            left[i] = Float(round * 1000 + i)
            right[i] = Float(round * 2000 + i)
        }
        ring.write(from: listPtr, frames: frames)
    }
    let got2 = ring.read(left: outL, right: outR, frames: frames * 8)
    check(got2 == 1024, "capacity clamp drops oldest (kept \(got2), capacity 1024)")
    check(ring.statistics.totalWritten == UInt64(frames * 10), "totalWritten tracks all input")

    let bigL = UnsafeMutablePointer<Float>.allocate(capacity: 5000)
    let bigR = UnsafeMutablePointer<Float>.allocate(capacity: 5000)
    defer { bigL.deallocate(); bigR.deallocate() }
    let remaining = ring.read(left: bigL, right: bigR, frames: 5000)
    check(remaining == 0, "ring fully drained by clamp read (got \(remaining))")
    let underrunsBefore = ring.statistics.underruns
    let drained = ring.read(left: bigL, right: bigR, frames: 5000)
    check(drained == 0 && ring.statistics.underruns == underrunsBefore + 5000, "underrun counted")
}

// MARK: - EQParameters

func testEQParameters() {
    print("EQParameters")
    let centers = EQParameters.defaultCenters(count: 10)
    check(centers.count == 10, "10-band layout size")
    check(centers[0] == 62.5 && centers[9] == 13885, "10-band ported FxSound centers")
    check(EQParameters.defaultCenters(count: 31).count == 31, "31-band layout size")
    let mono5 = EQParameters.defaultCenters(count: 5)
    check(mono5 == Array(mono5.sorted()), "5-band centers ascending")
    check(EQParameters.bandwidthOctaves(count: 10, q: 1.0) > EQParameters.bandwidthOctaves(count: 10, q: 3.0),
          "higher Q narrows bandwidth")
    let clamped = EQParameters.clampFrequency(99999, index: 9, count: 10)
    check(clamped <= EQParameters.maxCenterHz, "frequency clamp upper bound")
}

// MARK: - RenderDSP

func testRenderDSP() {
    print("RenderDSP")
    let dsp = RenderDSP()
    let frames = 64
    let l = UnsafeMutablePointer<Float>.allocate(capacity: frames)
    let r = UnsafeMutablePointer<Float>.allocate(capacity: frames)
    defer { l.deallocate(); r.deallocate() }
    for i in 0..<frames { l[i] = 0.5; r[i] = 0.25 }

    dsp.process(left: l, right: r, frames: frames)
    check(l[0] == 0.5 && r[0] == 0.25, "neutral params are transparent")

    dsp.setParams(RenderDSP.Params(balanceDB: -20, width: 0, levelingDB: 0))
    dsp.process(left: l, right: r, frames: frames)
    check(abs(r[0] - 0.025) < 0.001, "balance -20 dB attenuates right (10^-1)")

    // width symmetry: mono content stays symmetric under widening
    for i in 0..<frames { l[i] = 0.5; r[i] = 0.5 }
    dsp.setParams(RenderDSP.Params(balanceDB: 0, width: 0.5, levelingDB: 0))
    dsp.process(left: l, right: r, frames: frames)
    check(abs(l[0] - r[0]) < 0.001, "width keeps identical channels symmetric")
}

// MARK: - Preset JSON + PresetStore

func testPresets() {
    print("Presets")
    MainActor.assumeIsolated {
        guard let data = BuiltInPresets.json.data(using: .utf8),
              let file = try? JSONDecoder().decode(BuiltInPresetFile.self, from: data) else {
            check(false, "BuiltInPresets.json decodes")
            return
        }
        check(file.presets.count == 13, "13 built-in presets")
        let names = Set(file.presets.map { $0.name })
        for expected in ["Default", "General", "Music", "Voice", "Volume Boost", "Gaming",
                         "Classic Processing", "Light Processing", "Bass Boost",
                         "Streaming Video", "Movies", "TV", "Transcription"] {
            check(names.contains(expected), "preset exists: \(expected)")
        }
        let def = file.presets.first { $0.name == "Default" }!
        check(def.effects == EffectValues() && def.bands.allSatisfy { $0.gain == 0 }, "Default preset is neutral")
        let music = file.presets.first { $0.name == "Music" }!
        check(abs(music.effects.fidelity - 3.94) < 0.01 && music.effects.bass > 4, "Music preset effect values decoded")
        let transcription = file.presets.first { $0.name == "Transcription" }!
        check(transcription.bands.contains { $0.gain == -12 }, "Transcription has -12 dB low cut")
        check(file.presets.allSatisfy { $0.bands.count == 10 }, "all built-ins carry 10 bands")

        // store round-trip in temp dir
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("fxsound-tests-\(UUID().uuidString)", isDirectory: true)
        let store = PresetStore(directoryOverride: temp)
        check(store.builtIns.count == 13, "store loads built-ins")
        check(store.isNameValid("My Rock Preset"), "name validation accepts new name")
        check(!store.isNameValid("Music"), "name validation rejects duplicate of built-in")

        var user = Preset(name: "My Rock Preset", isBuiltIn: false, effects: EffectValues(bass: 6))
        user.bands = [PresetBand(frequency: 100, gain: 4)]
        store.addOrUpdateUserPreset(user)
        user.name = "My Rock Preset v2"
        store.addOrUpdateUserPreset(user)

        let reloaded = PresetStore(directoryOverride: temp)
        check(reloaded.userPresets.count == 1, "user preset persisted to disk")
        check(reloaded.userPresets.first?.name == "My Rock Preset v2", "user preset content survives reload")
        check(reloaded.userPresets.first?.effects.bass == 6, "user preset effects survive reload")
        reloaded.deleteUserPreset(id: reloaded.userPresets[0].id)
        check(reloaded.userPresets.isEmpty, "delete removes user preset")
        try? FileManager.default.removeItem(at: temp)
    }
}

// MARK: - Audit fixes (stable IDs, band resample, built-in overrides)

func testAuditFixes() {
    print("Audit fixes")
    MainActor.assumeIsolated {
        // deterministic built-in IDs
        let a = PresetStore.stableID(for: "Music")
        let b = PresetStore.stableID(for: "Music")
        let c = PresetStore.stableID(for: "Voice")
        check(a == b, "stableID is deterministic for the same name")
        check(a != c, "stableID differs between preset names")

        // band-count resample keeps curve shape
        let old: [PresetBand] = [
            PresetBand(frequency: 62.5, gain: -12),
            PresetBand(frequency: 16000, gain: 12),
        ]
        let resampled = EQParameters.resample(old, to: 10)
        check(resampled.count == 10, "resample produces 10 bands")
        check(resampled[0].gain == -12, "resample keeps gain at low edge (center matches)")
        check(resampled[9].gain == 11, "resample interpolates toward high edge (got \(resampled[9].gain))")
        let mid = resampled[4].gain
        check(abs(mid - 0) < 2, "resample interpolates the middle of a -12→12 ramp (got \(mid))")

        // Custom scratch lifecycle: edits detach into one rolling "Custom" slot
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("fxsound-custom-\(UUID().uuidString)", isDirectory: true)
        let store = PresetStore(directoryOverride: temp)
        let music = store.builtIns.first { $0.name == "Music" }!
        let custom1 = store.createOrResetCustom(values: music)
        check(custom1.name == PresetStore.customScratchName, "scratch named Custom")
        check(abs(custom1.effects.bass - 4.72) < 0.01, "scratch starts from source preset values")
        let custom2 = store.createOrResetCustom(values: Preset(name: "x", isBuiltIn: false))
        check(custom2.id == custom1.id, "scratch reuses the same Custom slot (no preset spam)")

        let reloaded = PresetStore(directoryOverride: temp)
        check(reloaded.userPresets.contains { $0.id == custom1.id }, "Custom scratch persists")

        // built-ins stay factory-immutable under the Custom model
        let factoryMusic = reloaded.builtIns.first { $0.name == "Music" }!
        check(abs(factoryMusic.effects.bass - 4.72) < 0.01, "built-ins stay factory after Custom created")

        // import from an exported JSON file with name-collision handling
        let exportURL = temp.appendingPathComponent("export.json")
        var exportPreset = Preset(name: "Music", isBuiltIn: false, effects: EffectValues(bass: 8))
        exportPreset.bands = [PresetBand(frequency: 100, gain: 5)]
        if let data = try? JSONEncoder().encode(exportPreset) {
            try? data.write(to: exportURL)
        }
        let imported = reloaded.importPreset(from: exportURL)
        check(imported != nil, "import succeeds from valid JSON file")
        check(imported?.name == "Music 2", "imported name uniqued against existing (got \(imported?.name ?? "nil"))")
        check(imported?.effects.bass == 8, "imported preset keeps its values")
        let afterImport = PresetStore(directoryOverride: temp)
        check(afterImport.userPresets.contains { $0.name == "Music 2" && $0.effects.bass == 8 },
              "imported preset persists to disk")
        try? FileManager.default.removeItem(at: temp)
    }
}

// MARK: - SpectrumBars (fixed-stick visualizer feed)

func testSpectrumBars() {
    print("SpectrumBars")
    let sr: Float = 48000
    let bars = SpectrumBars(sampleRate: sr)
    check(bars.snapshot().count == 128, "128 bands")
    check(bars.snapshot().allSatisfy { $0 == 0 }, "starts silent")

    // feed a loud 1 kHz sine (~40 ms across callbacks, fills the 2048 window)
    let frames = 512
    let l = UnsafeMutablePointer<Float>.allocate(capacity: frames)
    let r = UnsafeMutablePointer<Float>.allocate(capacity: frames)
    defer { l.deallocate(); r.deallocate() }
    var phase: Float = 0
    let phaseInc = Float(2 * Double.pi * 1000 / 48000)
    for _ in 0..<8 {
        for i in 0..<frames {
            l[i] = 0.5 * sin(phase)
            r[i] = l[i]
            phase += phaseInc
            if phase > 2 * Float.pi { phase -= 2 * Float.pi }
        }
        bars.analyze(left: l, right: r, frames: frames, sampleRate: sr)
    }
    let snap = bars.snapshot()
    check(snap.count == 128, "snapshot has 128 bands")
    check(bars.peakLevel > 0.8, "1 kHz tone drives its band high (peak \(bars.peakLevel))")
    check(snap[0] < 0.05, "sub-80 Hz bands stay dark for a 1 kHz tone (got \(snap[0]))")
    let highs = Array(snap.suffix(24)) // top ~2.9k-16k bands
    check((highs.max() ?? 1) < 0.6, "high bands stay low for a 1 kHz tone (max \((highs.max() ?? 0)))")
    check(bars.peakLevel == snap.max()!, "peakLevel matches snapshot max")

    let fresh = SpectrumBars(sampleRate: sr)
    check(fresh.snapshot().allSatisfy { $0 == 0 }, "fresh analyzer starts silent")
}

// MARK: - SettingsStore

func testSettings() {
    print("SettingsStore")
    MainActor.assumeIsolated {
        let suite = "fxsound-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = SettingsStore(defaults: defaults)
        check(store.settings.combo(for: .power).keyCode == 35, "default power hotkey keyCode")
        store.update { $0.followSystemDefaultOutput = false }
        let reloaded = SettingsStore(defaults: defaults)
        check(reloaded.settings.followSystemDefaultOutput == false, "settings persist to defaults")
        defaults.removePersistentDomain(forName: suite)
    }
}

testRingBuffer()
testEQParameters()
testRenderDSP()
testPresets()
testSettings()
testSpectrumBars()
testAuditFixes()

print("\n\(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
