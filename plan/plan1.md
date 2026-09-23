# Plan 1 — Research: FxSound (Windows) deep dive

Source of truth: clone of https://github.com/fxsound2/fxsound-app at `/tmp/fxsound-app`
(shallow clone, 2026-09-24). C++ / JUCE 6.1.6, AGPL v3. We read the code to extract
**behavior, parameters and data** — not to copy code.

---

## 1. Three-component architecture (from CLAUDE.md + source layout)

| Component | Folder | Role | Mac counterpart |
|---|---|---|---|
| **FxSound GUI** | `fxsound/Source` | JUCE app: window, views, controller/model, hotkeys, settings, tray | SwiftUI app (plan4) |
| **AudioPassthru** | `audiopassthru/` | Enumerates devices, captures from the "FxSound Audio Enhancer" **virtual audio driver** (installed as the system default playback device), feeds DSP, plays to the real device, detects device changes | Core Audio process tap + aggregate device (plan5) |
| **DfxDsp** | `dsp/` | Real-time DSP engine: EQ + effects + gain + leveling + spectrum | AVAudioUnitEQ + small custom DSP (plan6) |

Key point: **on Windows FxSound must own a virtual soundcard** because pre-14.x Windows has no
system-tap API. On macOS 14.4+ we get the tap for free — this is the single biggest platform
difference and the reason our Mac version needs no driver install.

## 2. The DSP surface (`dsp/include/DfxDsp.h` — public API)

```cpp
enum Effect { Fidelity=0, Ambience=1, Surround=2, DynamicBoost=3, Bass=4, NumEffects=5 };
loadPreset(path) / savePreset(name, path) / exportPreset(...)
eqOn(on) / getNumEqBands() / setNumBands(n)          // n ∈ {5,10,15,20,31}, default 10
get/setEqBandFrequency(band, hz)                      // per-band movable center frequency
get/setEqBandBoostCut(band, dB)                       // ±12 dB per band
get/setFilterQ(q)                                     // 1.0–3.0, default 1.0 (band width)
get/setBalance(dB)                                    // ±20 dB L/R balance
get/setNormalization(dB)                              // normalization amount
get/setVolumeLeveling(dB)                             // 0–4 dB loudness leveling
get/setMasterGain(dB)                                 // ±20 dB master/volume boost
get/setEffectValue(effect, 0..10)                     // 5 effect sliders, 0.0–10.0
powerOn(bool), isPowerOn()
getSpectrumBandValues(...)                            // 10-band spectrum for the visualizer
```

Internal graphic EQ supports up to 31 bands (`DFXP_GRAPHIC_EQ_NUM_BANDS = 31` in
`dsp/DfxDspEq.cpp`); the UI default is **10 bands**.

## 3. UI structure (`fxsound/Source/GUI`)

- **FxModel** — observable state: `power_state`, presets list (`AppPreset`/`UserPreset`, each with
  `name`, `path`, `modified` flag), `output_names` + selected output + `output_disconnected`,
  hotkey support, language, debug logging. Events: PresetSelected, PresetListUpdated,
  OutputSelected, OutputListUpdated, OutputError, Notification.
- **FxController** — the app brain. Notable members:
  `NUM_SPECTRUM_BANDS = 10`, `DEFAULT_NUM_EQ_BANDS = 10`;
  preset ops: `setPreset, autoSaveModifiedPreset, savePreset, renamePreset, deletePreset,
  undoPreset, resetPresets, exportPresets, importPresets`;
  device ops: `setOutput, refreshOutputList, checkDeviceChanges, isOutputDeviceConnected,
  compareOutputDevicePriority, isNewOutputPrioritized (prioritize newly connected devices)`;
  hotkey ops: `enableHotkeys, setHotkey (Ctrl+Alt or Ctrl+Shift + A–Z/0–9)`.
- **Views**: `FxLiteView` (compact: preset combo + power button), `FxProView` (EQ sliders +
  effect sliders + balance + visualizer), `FxSystemTrayView` (tray popup), `FxMainWindow`,
  `FxSettingsDialog` (3 panes: **Audio**, **General**, **Help**).
- **Controls**: `FxPowerButton`, `FxAudioSlider` (vertical), `FxBalanceSlider`,
  `FxEqualizer` (sliders + on/off), `FxVisualizer` (10-band spectrum), `FxOutputPreference`
  (device chooser), `FxPresetNameEditor`, `FxPresetImportDialog`, `FxPresetExportDialog`,
  `FxHotkeyLabel` (hotkey editor), `FxTheme` (light/dark).

## 4. Settings dialog contents

- **Audio pane**: output device preference/priority, "prioritize new devices" toggle.
- **General pane**: launch on Windows startup, always on top, hide help tooltips,
  hide notifications, **hotkeys** (5 commands below), language.
- **View**: `--view` switches Lite (1) ↔ Pro/Full (2). Theme mode light/dark.

## 5. Global hotkeys (5 commands, from `FxSettingsDialog.cpp:342`)

1. Turn FxSound On/Off  2. Open/Close FxSound  3. Next Preset  4. Previous Preset  5. Next Output.
Constraint in code: Ctrl+Alt or Ctrl+Shift modified, key must be A–Z or 0–9.

## 6. Preset system

- **File format `.fac`** — plain-text key/value dump (version 9):
  header (`CLASS1 : Effect Type`, `9: Version`, name, double-params flag),
  6 "Main" values (scaled effect/gain state, 0–~115 range),
  then `N: Number of EQ Bands`, `1: On/Off Flag`, and per band: `CF` (center frequency, Hz)
  + `Boost/Cut` (dB). Band centers are **arbitrary per preset** (e.g. Music: 62.5, 110, 250,
  370, 650, 1200, 2130, 4550, 6850, 16000 Hz).
- **13 built-in app presets** (`Installer/Resources/Factsoft/*.fac`), names extracted:

  | # | Name | # | Name |
  |---|---|---|---|
  | Default | Default | 7 | Light Processing |
  | 1 | General | 8 | Bass Boost |
  | 2 | Music | 9 | Streaming Video |
  | 3 | Voice | 10 | Movies |
  | 4 | Volume Boost | 11 | TV |
  | 5 | Gaming | 12 | Transcription |
  | 6 | Classic Processing | | |

  Plus community **BonusPresets** (`bin/BonusPresets/*.fac`): 70's, 80's, Alternative Rock,
  Classical, Classic Rock, Jazz, Metal, Modern Country, Modern Rock, Pop, R&B, Trap (+6
  community-curated ones). Optional to port; listed in plan3.
- **Storage**: built-ins ship in the app folder (`Factsoft/`); user presets live in
  `%APPDATA%\FxSound\Presets\*.fac`; an auto-saved copy marks a preset "modified" in the UI;
  import/export dialogs move `.fac` files in/out.
- All 13 presets' Main values + band centers were extracted for porting — see plan7.

## 7. Command-line control (`docs/COMMAND_LINE_OPTIONS.md` — the exact parameter spec)

`--power`, `--preset`, `--save_preset`, `--overwrite_preset`, `--undo_preset`, `--rename_preset`,
`--delete_preset`, `--output=<device>`, `--view=<1|2>`, `--language`, `--num_bands=<5|10|15|20|31>`,
`--balance=-20..20`, `--filter_q=1.0–3.0`, `--master_gain=-20..20`, `--volume_leveling=0–4`,
`--set_band_freq`, `--set_band_gain`, `--set_effect=<fidelity|ambience|surround|dynamicboost|bass>:0–10`,
`--status` (writes state JSON), `--run_minimized`.
→ On macOS this maps naturally to URL-scheme / CLI + `--status`-style introspection (v2, plan9).

## 8. What we deliberately do NOT port

- The `.fac` binary-legacy format (we use JSON; optional `.fac` import later).
- The XP-era winmm/dsound DLL hooks, ASIO paths, MP3 encoder remnants (`audiopassthru`).
- The virtual audio driver itself (obsolete on macOS 14.4+ thanks to taps).
- DFX's proprietary filter-network code (`dsp/ptechDsp`, `dsp/ptutil`) — we re-implement
  **perceptual equivalents** with AVAudioUnitEQ/vDSP (plan6 documents every mapping).
