# Plan 3 — Product spec: Mac feature set, MVP, presets & UI

Turns the research into a concrete product. App name: **FxSound** (bundle `com.aliahad.fxsound`).

---

## 1. Feature parity matrix (FxSound Windows → Mac)

| Feature | FxSound (Win) | Mac v1 | Phase |
|---|---|---|---|
| System-wide audio processing | Virtual soundcard driver | Core Audio process tap (no driver) | P1 |
| Power on/off button | ✓ | ✓ (destroys/creates tap) | P1 |
| Graphic EQ, 5/10/15/20/31 bands, ±12 dB, movable centers, Q 1–3 | ✓ | ✓ (AVAudioUnitEQ) | P2 |
| Preset EQ (13 built-ins) | ✓ `.fac` files | ✓ JSON built-ins (ported values) | P3 |
| User presets: save/rename/delete/undo/reset/autosave/import/export | ✓ | ✓ | P3 |
| Effects: Bass, Fidelity, Ambience, Surround, Dynamic Boost (0–10) | ✓ | ✓ (perceptual equivalents) | P2 |
| Master gain −20…+20 dB (volume boost) | ✓ | ✓ + safety limiter | P2 |
| Balance ±20 | ✓ | ✓ | P2 |
| Volume leveling 0–4 | ✓ | ✓ (slow AGC) | P2 |
| 10-band spectrum visualizer | ✓ | ✓ (vDSP FFT) | P2 |
| Output device chooser + auto-switch on default change | ✓ | ✓ | P4 |
| "Prioritize new devices" option | ✓ | ✓ | P4 |
| Global hotkeys ×5 (on/off, show/hide, next/prev preset, next output) | ✓ | ✓ (Carbon hotkeys) | P4 |
| Lite / Pro views | ✓ | ✓ (single window, toggle) | P4 |
| Menu bar quick menu | Tray popup | `MenuBarExtra` | P4 |
| Launch at startup, always-on-top, tooltips/notifications toggles, theme | ✓ | ✓ (minus always-on-top → standard) | P4 |
| Languages | 15+ | EN first; structure for l10n | P4+ |
| CLI/URL remote control + status | ✓ `--preset=…` | URL scheme `fxsound://preset/Music` (v2) | backlog |
| Multiple EQ curve visual overlay | ✓ (Pro) | ✓ | P4 polish |

Explicit **non-goals for v1**: driver fallback builds, App Store distribution, per-app EQ profiles,
REW import, upmixing.

## 2. MVP definition (what makes this "the simple app" the user asked for)

> **MVP = M1+M2+M3**: install → grant Audio Recording permission → press power → pick a preset
> (e.g. *Volume Boost* or *Bass Boost*) → music is louder and shaped; choose output device; quit
> cleanly restores normal audio.

Success criteria (measurable):
- End-to-end latency ≤ 50 ms; zero glitching playing 48 kHz stereo for 30 min on M4.
- CPU < 5 % average, memory < 120 MB steady state.
- Power-off within 200 ms restores untouched system audio.
- Preset switch ≤ 100 ms, click-free (gain ramp).

## 3. Preset catalog (ported from `Installer/Resources/Factsoft/*.fac`)

13 built-ins (names fixed): **Default, General, Music, Voice, Volume Boost, Gaming,
Classic Processing, Light Processing, Bass Boost, Streaming Video, Movies, TV, Transcription**.
Each carries: effect values, master gain, per-band centers + boost/cut (extracted values in
plan7 §3; port script generates `BuiltInPresets.json`). Optional bonus set (70's, 80's, Classical,
Jazz, Metal, Pop, Rock, R&B, Trap, …) gated behind a "Download/enable bonus presets" affordance or
simply shipped as extra built-ins — decision at P3 start.

## 4. UI design (SwiftUI, light/dark adaptive)

### Main window (single window, two modes, FxSound-style)

```
┌────────────────────────────────────────────────────────┐
│  ⏻  FxSound            [Lite | Pro]         — □ ✕      │
│ ┌─────────────── Lite mode ───────────────────────────┐│
│ │   Preset [ Music ▾ ]        Output [ MacBook Pro ▾ ]││
│ │   MASTER ───────────────●────────  +4.0 dB          ││
│ └─────────────────────────────────────────────────────┘│
│ ┌──────────────── Pro mode ───────────────────────────┐│
│ │ EQ ON   Bands [5|10|15|20|31]   Q [1.0]             ││
│ │  62 ─ 110 ─ 250 ─ 370 ─ 650 ─ 1.2k ─ 2.1k ─ 4.5k ─… ││
│ │  (±12 dB vertical sliders, double-click = reset)    ││
│ │ Effects   Bass ──●────  Fidelity ─●────             ││
│ │           Ambience ────  Surround ────  DynBoost ── ││
│ │ Leveling [0.0]  Balance ──●──  Visualizer ▂▄▆▄▂     ││
│ └─────────────────────────────────────────────────────┘│
└────────────────────────────────────────────────────────┘
```

- **Power button**: big, glowing when on (FxSound's signature), keyboard `⌘P`? (reserved: power).
- **Preset dropdown**: built-ins grouped first, then user presets with ✎/🗑 inline; "modified"
  dot + undo ↩ affordance; New Preset…; Import/Export….
- **Output picker**: devices with transport icons; "Follow system default" check item; disabled
  entries for disconnected-but-remembered devices.
- **Menu bar (`MenuBarExtra`)**: Power on/off, last 5 presets, output devices, Open FxSound, Quit.

### First-launch permission flow (critical UX)

1. Welcome screen explains what the app does + "Enable system audio" button.
2. Button creates the tap → TCC prompt appears ("FxSound would like to record this computer's
   audio…"). Approve → engine starts.
3. If user denies (or the silent-zero-buffer failure is detected by the self-test), show a
   guidance card: System Settings → Privacy & Security → **Audio Recording** → enable FxSound →
   Reopen. Re-test on window focus.

## 5. Settings sheet

Audio: follow default output (on), prioritize newly connected devices (off), buffer size
(safety), sample-rate display. General: launch at login, show menu bar icon, hotkeys ×5 with
recorder fields, check for updates, notifications on device change. About: version, licenses
(acknowledges FxSound inspiration + AGPL preset-data provenance note).

## 6. Iconography & branding

Original icon (speaker + sliders), not FxSound's artwork (their logo/assets are not ours to reuse).
SF Symbols throughout: `power`, `slider.horizontal.3`, `hifispeaker`, `waveform`, `airplayaudio`.
