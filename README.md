# FxSound for Mac

A system-wide audio equalizer and volume booster for macOS (Apple Silicon), modeled on the
open-source [FxSound](https://github.com/fxsound2/fxsound-app) app for Windows. Written from
scratch in Swift/SwiftUI — preset *data* is ported from FxSound (AGPL v3), no FxSound code.

## How it works

macOS 14.4+ Core Audio **process taps** capture the system's output audio (no virtual driver,
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

- Power on/off with mute-safe teardown
- 13 built-in presets ported from FxSound (Default, Music, Voice, Volume Boost, Bass Boost,
  Gaming, Movies, TV, Transcription, …) with FxSound's exact band frequencies and decoded
  effect values
- Graphic EQ: 5/10/15/20/31 bands, ±12 dB, per-band movable centers, Q 1–3
- Effects: Bass, Fidelity, Ambience, Surround, Dynamic Boost (0–10)
- Master gain −20…+20 dB with limiter headroom management, balance ±20 dB, volume leveling 0–4 dB
- 10-band spectrum visualizer (vDSP FFT)
- User presets: save/rename/delete/undo/autosave, import/export as JSON
- Output device picker with follow-system-default and prioritize-new-devices modes
- Menu bar quick controls, 5 global hotkeys (rebindable), launch-at-login

## Requirements

- macOS 15.0+
- Audio Recording permission (System Settings → Privacy & Security → Audio Recording) is
  requested on first power-on.

## Build & run

```bash
open fxsound.xcodeproj          # ⌘R in Xcode
# or:
Scripts/build_release.sh        # Release build
Scripts/build_release.sh --dmg  # + DMG at build/FxSound.dmg
```

Logic tests (no audio hardware needed):

```bash
Tests/run_logic_tests.sh        # 46 checks; exits non-zero on failure
```

## Project layout

- `plan/` — research and implementation plans (plan1–plan9) with status log
- `fxsound/Audio/` — tap, aggregate device, ring buffer, DSP engine, device manager
- `fxsound/Presets/` — preset model/store + built-in preset data (generated from FxSound `.fac`)
- `fxsound/Core/` — app state, controller, settings
- `fxsound/App/` — SwiftUI views (Lite/Pro, menu bar, settings)
- `fxsound/Platform/` — hotkeys, login item, permissions
- `Tests/LogicTests/` — standalone logic test harness

## Known limitations

- DRM-protected content (e.g. some Apple TV/streaming apps) may bypass or mute through taps.
- Adding/removing `NSAudioCaptureUsageDescription` from Info.plist silently disables capture
  (taps return zeros) — the app detects this and shows guidance.
