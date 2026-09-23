# FxSound for Mac — Master Plan

A system-wide audio equalizer & sound booster for Mac (Apple Silicon), modeled on the
open-source Windows app [FxSound](https://github.com/fxsound2/fxsound-app).

- **Target machine:** Mac Mini M4 (Apple Silicon, macOS 14.4+ required for the audio-capture API; repo currently targets a newer SDK).
- **Local project:** `/Volumes/essd/build/apps/fxSound/fxsound` — a fresh SwiftUI Xcode project
  (`fxsound.xcodeproj`, bundle id `com.aliahad.fxsound`, Swift 5, currently a "Hello, world" template).
- **Reference repo cloned for research:** `/tmp/fxsound-app` (fxsound2/fxsound-app, C++/JUCE, AGPL v3).
- **License note:** FxSound is AGPL v3. This Mac app is written from scratch in Swift — we port
  *concepts, parameter values and preset data* (data is not copyrightable), **not** C++ source.
  Keep the codebase clean-room: no copying of FxSound C/C++ source files.

---

## What FxSound is (one paragraph)

FxSound is a **virtual soundcard**: Windows plays all audio into the "FxSound Audio Enhancer"
virtual device, the app captures that stream, runs it through a real-time DSP engine
(graphic EQ + 5 enhancement effects + gain/leveling), and plays the processed result out of the
real output device. The UI is a compact window (Lite view: power, preset, output selector;
Pro view: EQ sliders, effect sliders, visualizer) plus a system-tray icon and global hotkeys.

## The macOS equivalent (our design in one paragraph)

macOS has no virtual-soundcard API for third-party apps, but since **macOS 14.2/14.4** it has
**Core Audio process taps** (`AudioHardwareCreateTap` + `CATapDescription`): an app can capture the
system's output audio passively — no kext, no virtual driver, no default-device hijack. The app
creates a **stereo global tap that mutes the original output and excludes its own process**,
wraps the tap + the real output device in a **private aggregate device**, pulls tapped frames in an
IOProc, pushes them through a lock-free ring buffer into an **AVAudioEngine**
(`AVAudioSourceNode → AVAudioUnitEQ → output node`), and the engine renders processed audio to the
user-selected output device. Power off = destroy the tap → system audio flows normally again.
Fallback for older macOS: the BlackHole loopback driver (documented in plan2.md, not required here).

---

## Plan files

| File | Contents |
|---|---|
| [plan1.md](plan1.md) | **Research:** FxSound (Windows) — architecture, DSP engine, EQ, effects, presets, UI, hotkeys, CLI |
| [plan2.md](plan2.md) | **Research:** macOS audio ecosystem — Core Audio taps, aggregate devices, AVAudioEngine/EQ, permissions, route decision & fallback |
| [plan3.md](plan3.md) | **Product spec:** feature-parity matrix, MVP definition, preset catalog, UI design |
| [plan4.md](plan4.md) | **Architecture:** Swift module layout, data flow, state model, threading, persistence |
| [plan5.md](plan5.md) | **Phase 1 — Audio engine core:** tap → aggregate → ring buffer → AVAudioEngine → device output, power on/off |
| [plan6.md](plan6.md) | **Phase 2 — EQ & effects DSP:** AVAudioUnitEQ configuration, effect mapping, balance, master gain, leveling, spectrum |
| [plan7.md](plan7.md) | **Phase 3 — Presets system:** 13 built-ins ported from FxSound, user presets, autosave/undo, import/export |
| [plan8.md](plan8.md) | **Phase 4 — Device manager & UI:** output selection/auto-switch, main window (Lite/Pro), menu bar, hotkeys, settings |
| [plan9.md](plan9.md) | **Phase 5 — Permissions, packaging & testing:** TCC flow, notarization, DMG, test plan, roadmap |

## Milestones

| # | Milestone | Plans | "Done" means |
|---|---|---|---|
| M0 | Research & design signed off | 1–4 | Feature matrix + architecture approved |
| M1 | **Sound flows through the app** | 5 | Music playing on the Mac is captured, EQ'd, and heard from the selected device; power toggle works |
| M2 | **The EQ works** | 6 | 10-band preset EQ audibly boosts bass/mids/treble; master gain boosts volume; visualizer moves |
| M3 | **Presets work** | 7 | 13 built-in FxSound presets selectable; user preset save/load/undo works |
| M4 | **The app is usable daily** | 8 | Device switching incl. auto-follow, menu bar quick controls, hotkeys, login launch |
| M5 | **Shippable build** | 9 | Notarized app runs with a clean first-launch permission flow |

## Key risks (summary — details in plan2/plan9)

1. **Silent-tap failure**: if `NSAudioCaptureUsageDescription` is missing from Info.plist, taps
   succeed but deliver **all-zero audio with no error**. Mitigation: set the key from day one and
   add a zero-signal self-test (plan5, plan9).
2. **Feedback loop**: a global tap also hears *our own* output. Mitigation: create the tap with our
   own process in the exclusion list (verified in plan5's first milestone).
3. **DRM content** (Apple Music/movies) may refuse capture or play muted through taps — degraded
   experience for protected streams; documented limitation, not fixable.
4. **Latency/CPU**: ring-buffer + engine adds ~20–40 ms round-trip; acceptable for EQ use-case,
   must stay glitch-free at 44.1/48 kHz stereo on M4 (real-time-safety rules in plan4).

## Status log

- 2026-09-24 — Research complete (FxSound source read from clone; macOS APIs verified against
  Apple docs/sample + AudioCap/iqualize references). Plan folder created.
- 2026-09-24 — **All implementation phases executed (plans 5–9).**
  - P1 (plan5) audio engine core: `SystemTap` (CATapDescription refined-init + bridged
    `AudioHardwareCreateProcessTap`/`Destroy`), private `AggregateEngine` (raw-key dictionary,
    zeroed IOProc output), `RingBuffer` (planar SPSC, os_unfair_lock), `ProcessingEngine`
    (AVAudioEngine graph, engine output bound to the aggregate device).
  - P2 (plan6) DSP: `AVAudioUnitEQ` (40 bands: EQ + bass/fidelity shelves + dynamic-boost
    contour), `RenderDSP` (balance, mid/side width, leveling AGC), Apple PeakLimiter via
    `AVAudioUnitEffect` (this SDK removed `AVAudioUnitDynamicsProcessor`), `SpectrumAnalyzer`
    (vDSP FFT, 10 log bands).
  - P3 (plan7) presets: `.fac` values decoded (Main indices 0/1/3/4/5 = fidelity/surround/
    ambience/dynamicBoost/bass, midi 0–127 → 0–10), all 13 built-ins embedded as generated
    Swift constant (packaging-proof, supersedes the planned JSON bundle resource), user preset
    CRUD/undo/autosave/JSON import-export.
  - P4 (plan8) device manager (enumerate/select/auto-follow/prioritize-new), Lite+Pro SwiftUI
    UI, menu bar quick menu, 5 Carbon hotkeys (rebindable), settings (login item via
    SMAppService, startup power, output behavior).
  - P5 (plan9) permissions (explicit `NSAudioCaptureUsageDescription` + sandbox audio-input
    entitlements file — the INFOPLIST_KEY/ENABLE_AUDIO_INPUT build settings did not take
    effect on this Xcode, so an explicit Info.plist/entitlements pair is used), zero-signal
    self-test after power-on, `Scripts/build_release.sh` (build + `--dmg`, sign/notarize
    hooks), `Tests/LogicTests` + `Tests/run_logic_tests.sh`.
- Verification: Debug & Release builds succeed warning-free; app launches and runs (smoke
  test on both configurations); 46/46 logic checks pass (ring-buffer round-trip/wrap/overflow,
  EQ band layouts + Q mapping, balance/width/leveling math, 13-preset decode + persistence
  round-trip, settings persistence).
- Notable bugs found by tests and fixed: AudioBufferList `mBuffers` struct-copy access returns
  garbage on this SDK (switched to raw-pointer arithmetic); `UInt32(command.hashValue)` trap on
  negative hash; missing `NSAudioCaptureUsageDescription` (the documented silent zero-tap
  failure) caught and closed before first user run.
- Audible/device-hardware QA (plan5/6/8 acceptance checklists: real-device switching, Bluetooth,
  30-min soak, Instruments profiling) and notarization remain manual/on-user-hardware steps —
  documented in plan9 §5.
- 2026-09-24 — **M1 runtime gate PASSED on the live machine (TCC granted in GUI).** The chain
  was exercised end-to-end with real audio: tap created (after fixing `!obj` — the tap
  exclusion list needs PID→`kAudioHardwarePropertyTranslatePIDToProcessObject` object IDs),
  aggregate IOProc delivers 512 frames/callback @48 kHz stereo, ring capture runs at exactly
  48025 fps with 0 overruns / 0 underruns, render callback runs 1:1 with IOProcs, and the
  spectrum analyzer reports peak 1.0 while a 440 Hz test tone plays (proof: capture → DSP →
  render path carries real signal). Also found & fixed: the AUHAL/server deadlock when binding
  the engine output to the tap-aggregate (engine now renders to the real device; the aggregate
  is capture-only), the `mBuffers` offset (8, not 4 — pointer alignment) behind a SIGSEGV in
  the render path, and a spectrum bug (`vDSP_vsmul` scalar misuse → `vDSP_vmul`).
  - Power cycle: SIGTERM → clean exit & teardown; relaunch `--power=1` re-arms with persisted
    TCC (self-test passed). `--power=1` CLI flag added (FxSound Windows parity).
  - Device switching: default-output changes (Speakers ↔ HDMI via SwitchAudioSource) are
    followed automatically; chain rebuilds in ~63–107 ms (gate: ≤1 s). Capture continues
    seamlessly across the switch.
  - Soak sample: CPU ~10.4%, memory 104 MB during processing (mem gate met; CPU above the 5%
    target — optimization path: throttle FFT cadence; scripted gate: `Scripts/soak_test.sh`).
  - Notarization: **not performable here** — the keychain holds only Apple Development
    identities, no Developer ID. `Scripts/build_release.sh --sign --notarize` is ready for a
    machine with credentials.
- 2026-09-24 — **Soak test executed (user halted at ~12 of 30 min)** via `Scripts/soak_test.sh 30`
  (Release build, `--power=1`, looping test tone).
  - Memory: **flat 39–40 MB across all 48 samples** — no leak trend (single 99 MB outlier was
    sampled during teardown, not steady state).
  - CPU: ~0% while idle/no audio flowing; 10.4% during active processing (reliable `top -l 2`
    sample). Above the aspirational 5% target — optimization path: reduce spectrum FFT cadence
    (currently every render callback) and skip DSP stages when bypassed.
  - Engine counters observed live during the run: **overruns=0**, underruns=512 (one-time
    startup transient only), capture steady at 48 025 fps, ioProcs ≈ renders 1:1.
    (Note: os_log info-level stats entries are memory-buffered only and are not reliably
    retrievable via `log show` after the process exits — read them live via
    `log stream --predicate 'subsystem == "com.aliahad.fxsound"'`.)
  - Full 30-minute duration: re-run with `Scripts/soak_test.sh 30` whenever desired; the
    ~12-minute slice showed stable memory and clean counters.
- 2026-09-24 — **UI/UX pass: pure-black + red theme, responsive layout, animated visualizer.**
  - Theme (`App/Theme.swift`): pure black background (#000), near-black cards with subtle red
    borders, red accent (`AccentColor` asset set to red, `.tint` cascaded), forced dark scheme.
  - Animated visualizer (`VisualizerView`): mirrored bar design at display refresh rate
    (`TimelineView(.animation)` + `VisualizerModel`), per-bar attack/decay smoothing, falling
    peak caps, red gradient fill with glow, center baseline; pauses when power is off.
  - Responsive: window resizes 380 pt up; EQ bands and effect sliders reflow via adaptive
    `LazyVGrid`s; pickers collapse via `ViewThatFits`; Lite view pins a tall visualizer to the
    bottom edge.
  - Custom-drawn `VerticalSlider` (red bipolar fill from center for EQ, bottom-fill for
    effects, double-click-to-reset preserved) replacing rotated NSSliders that rendered
    inconsistently on dark; segmented-control focus ring removed.
  - CLI parity addition: `--view=2` opens directly into Pro view.
  - Verified with window screenshots in both Lite and Pro views; 47/47 logic checks still
    green; Debug & Release builds clean; live chain confirmed processing while the UI was
    captured.
- 2026-09-24 — **Audit fixes applied** (audit found 2 medium + 5 low issues; all fixed):
  - Built-in preset IDs are now deterministic (MD5-derived from the name, `PresetStore.stableID`)
    — "restore last preset" works across launches.
  - Built-in preset edits now persist: auto-saved to `BuiltInOverrides/<id>.json` and merged
    onto factory values at load; `Reset Presets` deletes overrides. Dead shadow-copy code and
    the unused `showMenuBarIcon` setting removed.
  - SIGTERM now runs the graceful quit path (DispatchSourceSignal → `NSApp.terminate`) —
    verified: `chain stopped` is logged on `kill`, autosave/persistence run.
  - "Open FxSound" window fallback no longer raises the Settings window.
  - Menu-bar power item is a plain button (no toggle-state desync).
  - Switching EQ band count now interpolates the existing curve onto the new centers
    (`EQParameters.resample`) instead of resetting gains.
  - EQ/effect sliders expose VoiceOver labels and adjustable actions.
  - Tests: 57/57 pass (added: stable-ID determinism, resample curve preservation, built-in
    override persistence + reset). Runtime verified: SIGTERM teardown, graceful quit,
    chain start + self-test pass.
- 2026-09-24 — **Remaining manual gates require external resources:**
  - **Notarization** — requires Developer ID Application credentials (paid Apple Developer
    Program) and notarytool keychain profile; this machine has 0 Developer ID identities.
    Script hook ready: `Scripts/build_release.sh --sign --notarize`.
  - **Bluetooth output check** — requires a paired Bluetooth audio device; this Mac mini has
    only built-in speakers, an HDMI monitor, and USB devices connected. The device-switching
    gate was exercised over HDMI instead (passed, ~63–107 ms rebuilds).
