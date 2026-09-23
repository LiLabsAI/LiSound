# Sovate

A system-wide audio equalizer and volume booster for macOS (Apple Silicon), modeled on the
open-source [FxSound](https://github.com/fxsound2/fxsound-app) app for Windows. Written from
scratch in Swift/SwiftUI under the **Sovate** brand — preset *data* is ported from FxSound
(AGPL v3), no FxSound code.

Sovate lives in your menu bar, processes **all** system audio in real time, and renders it
to whatever output device you choose — with a pure black/golden UI.

## How it works

macOS Core Audio **process taps** capture the system's output audio (no virtual driver,
no kext). A private aggregate device binds the tap to your real output device; tapped audio
flows through a lock-free ring buffer into an `AVAudioEngine` chain:

```
system audio ──▶ process tap (mutes original, excludes this app)
                    └─▶ private aggregate device ── IOProc ──▶ ring buffer
                                                                 └─▶ AVAudioEngine:
     AVAudioSourceNode (balance · width · leveling) → AVAudioUnitEQ (EQ + bass/treble shelves
     + loudness contour) → PeakLimiter (headroom for boosts) → output device
```

Power off destroys the tap and normal system audio resumes instantly.

## Features

- **Power on/off** with mute-safe teardown; audio returns to normal the instant you power off
- **13 built-in presets** ported from FxSound (Default, Music, Voice, Volume Boost, Bass
  Boost, Gaming, Movies, TV, Transcription, …) with FxSound's exact band frequencies and
  decoded effect values
- **Custom presets**: the first edit detaches into a rolling "Custom" scratch — factory
  presets stay pristine. Save As New / Overwrite / Undo / Delete; presets export and import
  as shareable JSON files
- **Graphic EQ**: 5/10/15/20/31 bands, ±12 dB, per-band movable centers, Q 1–3 — switching
  band counts interpolates your existing curve
- **Effects**: Bass, Fidelity, Ambience, Surround, Dynamic Boost (0–10)
- **Master gain** −20…+20 dB with a peak limiter for clean boosting, balance ±20 dB,
  volume leveling 0–4 dB
- **Beat-sensitive waveform visualizer**: 128 fixed thin sticks driven by per-band FFT
  energy with fast attack / smooth release
- **Output management**: follow the system default, prioritize newly connected devices,
  cycle outputs by hotkey, aggregate/transient devices filtered from the list
- **Menu bar quick menu** with ✓ ticks on the active preset/output, plus Settings
- **5 global hotkeys** (rebindable, ⌃/⌥ + key), launch at login, single-instance enforcement
- **Lite / Pro views** in a pure black + golden theme
- **CLI control**: `--power=1`, `--preset=<name>`, `--set-band-gain=<index>:<dB>`, `--view=2`

## Requirements

- macOS 15.0+, Apple Silicon
- Audio Recording permission — Sovate prompts on first power-on, or enable it from
  **Settings → Permissions** with one click

## Build & run

```bash
open sovate.xcodeproj          # ⌘R in Xcode
# or:
Scripts/build_release.sh        # Release build
Scripts/build_release.sh --dmg  # + DMG at build/Sovate.dmg
```

Logic tests (no audio hardware needed):

```bash
Tests/run_logic_tests.sh        # 70 checks; exits non-zero on failure
```

## CLI flags

| Flag | Effect |
|---|---|
| `--power=1` / `--power=0` | Start with processing on / force off at launch |
| `--preset=<name>` | Select a preset by name (case-insensitive) |
| `--set-band-gain=<index>:<dB>` | Edit one EQ band at launch (detaches into Custom) |
| `--view=2` | Open directly in Pro view |

## Project layout

- `plan/` — research and implementation plans (plan1–plan9) with status log
- `sovate/Audio/` — tap, aggregate device, ring buffer, spectrum analyzer, DSP engine, device manager
- `sovate/Presets/` — preset model/store + built-in preset data (generated from FxSound `.fac`)
- `sovate/Core/` — app state, controller, settings
- `sovate/App/` — SwiftUI views (Lite/Pro, menu bar, settings, theme)
- `sovate/Platform/` — hotkeys, login item, permissions
- `Tests/LogicTests/` + `Tests/run_logic_tests.sh` — standalone logic test harness

## Troubleshooting

- **No effect / visualizer flat**: check Settings → Permissions → *System audio access*.
  Use **Enable / Re-check** to run a 6-second self-test; if it fails, open
  **System Settings → Privacy & Security → Audio Recording** and make sure Sovate is enabled.
- If the prompt never appeared (e.g. after removing `NSAudioCaptureUsageDescription`),
  taps return silent audio — the app detects this and shows the same guidance.

## Known limitations

- DRM-protected content (e.g. some Apple TV/streaming apps) may bypass or mute through taps.
- Not notarized — first launch needs right-click → Open, or
  `xattr -d com.apple.quarantine /Applications/sovate.app`.

## Developer

Developed by Ali — [ali@aliahad.com](mailto:ali@aliahad.com).
