# Plan 4 — Architecture: Swift modules, data flow, state, threading, persistence

How the Mac app is organized. Everything here maps 1:1 onto phases plan5–plan8.

---

## 1. Module layout (inside the existing `fxsound` Xcode target; split SPM packages only if compile times demand it)

```
fxsound/
├── fxsoundApp.swift                 // SwiftUI @main, WindowGroup + MenuBarExtra + Settings
├── App/
│   ├── RootView.swift               // Lite/Pro container, welcome & permission cards
│   ├── LiteView.swift               // power, preset, output, master gain
│   ├── ProView.swift                // EQ sliders, effects, balance, leveling, visualizer
│   ├── Components/                  // PowerButton, VerticalSlider, VisualizerView, DevicePicker…
│   └── SettingsView.swift
├── Core/
│   ├── AppState.swift               // @Observable single source of truth (FxModel counterpart)
│   ├── AppController.swift          // orchestrates engine+devices+preset+settings (FxController counterpart)
│   └── SettingsStore.swift          // UserDefaults-backed, Codable Settings struct
├── Audio/
│   ├── SystemTap.swift              // CATapDescription + AudioHardwareCreateTap + exclusions
│   ├── AggregateEngine.swift        // private aggregate device + IOProc + ring buffer
│   ├── RingBuffer.swift             // lock-free SPSC PCM ring (real-time safe)
│   ├── ProcessingEngine.swift       // AVAudioEngine graph owner: source → EQ → limiter → out
│   ├── EQParameters.swift           // band model, Q↔bandwidth, 5..31 band layouts
│   ├── EffectChain.swift            // effect sliders → concrete filter/stage values
│   ├── RenderDSP.swift              // balance + leveling AGC + stereo widening (AVAudioSourceNode stage)
│   ├── SpectrumAnalyzer.swift       // vDSP FFT, 10 bands, published levels
│   └── DeviceManager.swift          // enumerate/select outputs, default-change listeners
├── Presets/
│   ├── Preset.swift                 // Codable model (effects, gains, bands[], q, leveling…)
│   ├── PresetStore.swift            // built-ins + user presets CRUD, autosave, undo stack
│   ├── BuiltInPresets.json          // generated from FxSound .fac data (plan7)
│   └── FacImporter.swift            // (optional v2) read .fac files
└── Platform/
    ├── Hotkeys.swift                // Carbon RegisterEventHotKey wrapper
    ├── LoginItem.swift              // SMAppService
    └── Permissions.swift            // audio-capture status probing + zero-signal self-test
```

## 2. Data flow

```
UI (SwiftUI) ──commands──▶ AppController ──▶ ProcessingEngine (EQ/gain params, ramped)
     ▲                          │                  ▲
     │ published state          │ power on/off     │ PCM
     │                          ▼                  │
   AppState ◀── DeviceManager ─▶ AggregateEngine ──┘ (IOProc → RingBuffer)
            (device add/remove/   ▲                ▶ SpectrumAnalyzer (read-only tap copy)
             default change)      └── SystemTap (create/destroy)
                                PresetStore ──apply(preset)──▶ AppController
```

Rules:
- **AppState** is the only thing views read; mutations go through AppController (testable, and
  keeps SwiftUI free of Core Audio imports).
- Every DSP parameter change is applied with **10–20 ms gain smoothing** to avoid zipper noise.
- Spectrum + meters update on a 30 Hz `CADisplayLink`-like timer reading a copy — never bind UI to
  the audio callback.

## 3. State model (`AppState`)

```swift
struct AppState {
    var powerOn = false
    var selectedPresetID: Preset.ID?
    var presets: [Preset]                 // built-ins + user, ordered
    var outputs: [AudioDevice]            // id, name, transport, isDefault
    var selectedOutputID: AudioDevice.ID? // nil = follow system default
    var followSystemDefault = true
    var eq = EQState(on: true, bandCount: 10, q: 1.0, bands: […])   // movable centers
    var effects = EffectsState(bass: 0, fidelity: 0, ambience: 0, surround: 0, dynamicBoost: 0) // 0…10
    var masterGainDB = 0.0                // −20…+20
    var balanceDB = 0.0                   // −20…+20
    var levelingDB = 0.0                  // 0…4
    var permissionState: .unknown/.granted/.denied/.silentFailure
    var engineError: String?
    var spectrum: [Float]                 // 10 × 0…1, 30 Hz
}
```

Persistence split: **settings** (power-on-at-launch, follow default, hotkeys, selected output,
UI mode) → `UserDefaults` via `SettingsStore`; **presets** → JSON files in
`~/Library/Application Support/FxSound/Presets/*.json`; **current edits** → auto-saved shadow
preset per session (FxSound "modified" semantics, plan7).

## 4. Threading model

| Thread | Owns | Rules |
|---|---|---|
| Main | SwiftUI, AppController, DeviceManager listeners | All user-facing mutations; Core Audio object listeners hop here |
| Core Audio IOProc (aggregate, real-time) | RingBuffer write, format check | Real-time safe: no malloc/lock/IO; bounded work per callback |
| Engine render thread (real-time) | RenderDSP (balance/AGC/widening), EQ unit (Apple's) | Same real-time rules; parameter reads are atomic |
| Worker queue | Tap/aggregate creation & teardown, device enumeration, preset file IO, spectrum FFT | All blocking work lives here |

Synchronization: SPSC ring buffer (atomic head/tail), `os_unfair_lock`-free param handoff via
`Atomic<T>`/`ManagedAtomic`, controller→engine param updates through the engine's atomic param
block. Teardown order on power-off: engine stop → IOProc destroy → aggregate destroy → tap destroy
(reversed creation order; every step error-checked, see plan5 §5).

## 5. Error handling & recovery

- Tap/aggregate/engine creation failures surface as `engineError` cards with a Retry button.
- Device vanished mid-playback: DeviceManager listener → rebuild aggregate with new output (≤ 1 s);
  if none, power off + notify (FxSound's OutputError parity).
- Sample-rate/format change of output: recreate engine graph keeping params.
- Watchdog: after permission grant + engine start, spectrum RMS ≈ 0 for 5 s while system plays →
  show the silent-failure guidance (Permissions.selfTest).

## 6. Testing strategy

- **Unit**: EQParameters math (Q↔bandwidth, band layout for 5/10/15/20/31), PresetStore CRUD +
  JSON round-trip, RingBuffer overflow/drain invariants, RenderDSP balance/AGC curves.
- **Hardware-in-loop** (manual checklist, plan9): audible EQ effect, power toggle, device switch
  under playback, Bluetooth/AirPlay outputs, permission-denied path, sleep/wake, sample-rate
  switch (44.1↔48).
- **Perf gates**: 30-min soak (CPU/mem via Instruments), glitch counter via
  `AVAudioEngine` render error + IOProc overrun counters (debug builds only).
