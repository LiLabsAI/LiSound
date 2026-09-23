# Plan 8 — Phase 4: Device manager, UI shell, hotkeys, settings

**Milestone M4: "Usable daily."** The app looks like FxSound, follows device changes, sits in the
menu bar, answers hotkeys, launches at login, and remembers every preference.

---

## 1. `DeviceManager.swift` — "choose the sound system / device"

- Enumeration: `kAudioHardwarePropertyDevices` → devices with output streams; collect
  `id`, `name` (`kAudioObjectPropertyName`), `transportType`
  (`kAudioDevicePropertyTransportType` → icon: built-in `hifispeaker`, HDMI/DisplayPort
  `tv`, USB `cable.connector`, Bluetooth `airpods`/`person.wave.2`, AirPlay `airplayaudio`),
  `isDefault` (`kAudioHardwarePropertyDefaultOutputDevice`).
- Listeners (hop to main): device list changed, default output changed, device is-alive changed
  (`kAudioDevicePropertyDeviceIsAlive`), nominal sample rate.
- Selection semantics:
  - "Follow system default" (default ON): rebind engine output when macOS default changes.
  - Manual pick: rebind engine output to that device; remembered across launches by UID.
  - **"Prioritize newly connected devices"** toggle (FxSound parity, default OFF): when ON, a new
    output appearing (headphones plugged) becomes the output automatically.
  - Disappearing device: fall back to system default, keep chain alive (≤1 s), notify.
- "Next Output" support: ordered list cycling (hotkey + menu).

## 2. Main window UI (SwiftUI; polish pass on plan6's controls)

- `RootView`: toolbar with power (`PowerButton` — glowing ring when on, FxSound signature),
  Lite/Pro segmented toggle, window title shows active preset when power on.
- **LiteView**: preset combo (FxDropdown), output picker, master gain slider with dB readout,
  mini visualizer strip.
- **ProView**: EQ panel (sliders per band, band-count picker 5/10/15/20/31, Q stepper,
  per-band double-click reset, optional curve overlay Canvas), Effects panel (5 sliders 0–10),
  Master/Balance/Leveling rows, full `VisualizerView`.
- Empty/disabled states: permission cards (welcome / denied / silent-failure guidance), "no
  output device" card, power-off dims all controls but keeps them visible (FxSound does the same).
- Accessibility: labels on every slider, VoiceOver readouts, full keyboard control; tooltips
  (FxSound's help tips) behind the "hide tooltips" toggle.

## 3. `MenuBarExtra`

Menu: **Power** toggle, presets (top 5 + "More…"), output devices (radio + follow-default),
Open FxSound, Quit. Icon: slider glyph; power-on state adds a tint. Matches FxSound's tray view
role.

## 4. `Hotkeys.swift` (5, FxSound parity)

Carbon `RegisterEventHotKey`: Power On/Off, Show/Hide window, Next Preset, Previous Preset,
Next Output. Recorder UI in Settings (capture key-down, restrict to ⌃⌥ / ⌃⇧ + A–Z/0–9 like
FxSound), stored in `SettingsStore`, unregister/re-register on change, conflict check against
registered set.

## 5. `SettingsView` (3 panes, FxSound parity)

- **Audio**: output behavior (follow default, prioritize new), show sample rate/format info,
  "restore normal audio when quitting" (always on, explained).
- **General**: launch at login (`SMAppService`), show menu bar icon, hide tooltips, show
  notifications (device switches, power state), theme (System/Light/Dark), language (EN; hooks
  for l10n via String Catalogs).
- **Help**: diagnostics (copy system/audio report), link to project notes, licenses.

## 6. Window/app lifecycle

- Close button hides to menu bar (keep processing); ⌘Q = power off → save state → quit
  (guaranteed mute-release; also handle `applicationShouldTerminate` force path).
- Single-instance enforcement; second launch activates the window.
- State restoration: power-on-at-launch optional (default off — permission prompt UX), last
  preset/output/view restored.

### Acceptance checklist (M4 done when)
- [ ] Plug/unplug headphones (wired + BT): output follows per settings; no audio gaps > 1 s;
      notification shown.
- [ ] Every hotkey works system-wide and is rebindable; conflicts detected.
- [ ] Menu bar flow: power/preset/output all controllable without opening the window.
- [ ] Launch-at-login works and survives reboot; no permission re-prompt.
- [ ] Quit while running leaves system audio untouched (no mute, no aggregate leftovers in
      Audio MIDI Setup).
- [ ] Design QA vs FxSound screenshots: Lite and Pro parity walkthrough (plan3 §4).
