# Plan 2 — Research: macOS audio ecosystem & route decision

Goal: answer "how does a Mac app do what FxSound does on Windows" — capture **all** system audio,
process it (EQ/boost), and play it out of a **chosen** device — without kernel extensions.

---

## 1. The three possible routes on macOS

| Route | How | Pros | Cons | Verdict |
|---|---|---|---|---|
| **A. Core Audio process tap** (macOS 14.2+/14.4+) | `CATapDescription` + `AudioHardwareCreateTap`; wrap tap + real output device in a private **aggregate device**; read tapped PCM in an IOProc | No driver install; sanctioned by Apple (official sample "Capturing system audio with Core Audio taps"); per-process or global; mute behavior built in | Requires macOS 14.4+; TCC audio-recording consent; DRM streams may be protected; poorly documented API | **PRIMARY** — Mac Mini M4 qualifies |
| **B. Virtual loopback driver** (eqMac model) | Bundled/installed virtual device (BlackHole, or own DriverKit `AudioDriverKit` extension) set as system default; app captures from it | Works on older macOS; no TCC audio permission (device install consent instead) | Requires every user to install a driver/extension & change default device; DriverKit entitlement needs Apple approval; heavy | **Fallback only** (documented; BlackHole 2ch works today) |
| **C. Default-device hijack without driver** | Not possible for capture on macOS — no HAL-plugin tap for third-party apps since AudioServerPlugIn deprecation | — | — | Rejected |

Proof route A works for exactly our use-case: **iqualize** (open-source macOS system-wide
parametric EQ, no virtual driver, real-time spectrum) and **insidegui/AudioCap** (system audio
capture reference implementation).

## 2. Route A mechanics (what plan5 implements)

```
┌─────────────── private aggregate device ───────────────┐
│  sub-device 1: process tap (uuid)  → delivers frames   │
│  sub-device 2: real output device  ← receives frames   │
│  clock: output device, drift compensation on           │
└────────────────────────────────────────────────────────┘
        │ AudioDeviceCreateIOProcIDWithBlock (IOProc)
        ▼
   lock-free ring buffer (TPCircularBuffer or equivalent)
        ▼
   AVAudioEngine: AVAudioSourceNode → AVAudioUnitEQ(…) → mainMixer → outputNode
        ▼
   selected real output device (via kAudioOutputUnitProperty_CurrentDevice)
```

Key API sequence (all verified against Apple's sample + AudioCap README):

1. `CATapDescription.initStereoGlobalTapButExcludingProcesses([ownPID])` — global stereo tap;
   **must exclude our own process** or our processed output is re-tapped → feedback loop.
   Mute behavior: **mute when running** (`.whenRunning`) so the original stream is silenced while
   we process it (prevents double audio).
2. `AudioHardwareCreateTap(desc, &tapID)` → read tap `uuid`
   (`kAudioTapPropertyUUID`) and stream format (`kAudioTapPropertyFormat`).
3. `AudioHardwareCreateAggregateDevice` with:
   `kAudioAggregateDeviceTapListKey = [ {kAudioSubTapUIDKey: uuid} ]`,
   `kAudioAggregateDeviceIsPrivateKey = true` (hidden from other apps' device pickers),
   master clock = the real output device, per-sub-device drift compensation.
4. `AudioDeviceCreateIOProcIDWithBlock` on the aggregate; inside the callback wrap the input
   `AudioBufferList` as `AVAudioPCMBuffer` (`bufferListNoCopy`) and push into the ring buffer.
5. `AudioDeviceStart(aggregate)`, then run the AVAudioEngine.
6. **Power off**: `AudioDeviceStop`, destroy IOProc/aggregate/tap → system audio returns to
   normal instantly. This is FxSound's "power button" semantics.

## 3. Permissions & the silent-failure gotchas

- **Info.plist**: `NSAudioCaptureUsageDescription` is **mandatory**. If missing, **every Core Audio
  call still succeeds but the tap delivers all-zero buffers forever** — no error, no prompt.
  (Documented in AudioCap issues; make this a first-day item + runtime zero-signal self-test.)
- **TCC**: first tap creation triggers the audio-recording consent prompt; user can revoke in
  System Settings → Privacy & Security → Audio Recording. There is **no public API** to query the
  state — detect by checking for prolonged zero signal after enabling, and show guidance UI.
- **Sandboxing**: works in the App Sandbox (AudioCap ships sandboxed). For App Store builds add
  the audio-input-relevant entitlements; for direct distribution use Developer ID + notarization.
- **DRM content**: protected streams (e.g. Apple TV app movies) may be excluded/muted through
  taps. Accepted limitation; document in-app.

## 4. DSP toolbox on macOS

| FxSound feature | macOS building block |
|---|---|
| Graphic EQ, n bands, ±12 dB, movable centers, Q 1–3 | `AVAudioUnitEQ` — array of `AVAudioUnitEQFilterParameters` (`.parametric`: `frequency`, `gain`, `bandwidth` (octaves ≈ Q mapping), `bypass`) |
| Bass Boost effect | extra low-shelf band (@≈100 Hz) driven by the effect slider 0–10 |
| Fidelity/Clarity | high-shelf band (@≈7 kHz) + optional light high-pass cleanup |
| Ambience / 3D Surround | mid/side stereo widening stage (custom small render DSP with vDSP: S-gain, slight cross-feed) — perceptual equivalent, DFX's exact algorithm is proprietary |
| Dynamic Boost | loudness contour: level-dependent low+high shelf (simple AGC-free approximation; optional gentle RMS compressor later) |
| Master gain ±20 dB | `AVAudioUnitEQ.globalGain` (+ limiter guard: soft-clip via `AVAudioUnitDynamicsProcessor` peak limiter when boosting) |
| Balance ±20 dB | channel-gain stage in our render DSP (L/R scaling + optional negative-phase mono blend) |
| Volume leveling 0–4 dB | slow RMS AGC in render DSP (vDSP, ~1 s time constants), max +4 dB make-up |
| 10-band spectrum visualizer | vDSP FFT on tapped frames pre-EQ (10 log-spaced bands, 30 fps) |
| Boost without EQ distortion | headroom management: negative digital pre-gain + limiter ceiling (plan6) |

Real-time-safety rules for all render-path code (from FxSound's own CLAUDE.md review doctrine):
no allocations, no locks (use lock-free buffer), no logging, no Obj-C messaging beyond constant
selectors in the audio thread.

## 5. Device ecosystem ("choose the sound system / device")

- Enumerate outputs: `AudioObjectGetPropertyData(kAudioHardwarePropertyDevices)` →
  filter devices with output streams (`kAudioDevicePropertyStreams`, output scope); names via
  `kAudioObjectPropertyName`, transport type via `kAudioDevicePropertyTransportType`
  (Built-in/USB/HDMI/AirPlay/Bluetooth → show icons like FxSound does).
- Select output: set `kAudioOutputUnitProperty_CurrentDevice` on `engine.outputNode`; if the
  aggregate is already bound to that device, recreate the aggregate (cheap, rare event).
- "Next output" hotkey cycles the list (FxSound parity).
- Auto-follow: listen to `kAudioHardwarePropertyDefaultOutputDevice` +
  `kAudioHardwarePropertyDevices` changes; when the user plugs in headphones either (a) follow the
  new system default (default setting) or (b) keep current (FxSound's "prioritize new devices"
  toggle inverted — port both).
- Bluetooth caveats: AirPlay/BT devices have higher latency & buffer-size constraints; recreate
  engine format on sample-rate change (`kAudioDevicePropertyNominalSampleRate` listener).

## 6. Supporting platform APIs

| Need | API |
|---|---|
| Menu bar quick controls | SwiftUI `MenuBarExtra` (power, preset, output submenus) |
| Launch at login | `SMAppService.mainApp.register()` (macOS 13+) |
| Global hotkeys | Carbon `RegisterEventHotKey` (no Accessibility permission needed) |
| Persistence | `UserDefaults` (settings) + JSON in `~/Library/Application Support/FxSound/Presets/` |
| Updates (later) | Sparkle or App Store |
| Diagnostics | `os.Logger` with audio subsystem categories |

## 7. Decision record

- **D1**: Route A (process tap) primary; BlackHole documented as manual fallback only. → plan5
- **D2**: AVAudioEngine + AVAudioUnitEQ for DSP rather than hand-rolled biquads; custom DSP kept
  to one small render stage (balance/leveling/widening). → plan6
- **D3**: Target macOS 14.4+ (raise the Xcode project's current `MACOSX_DEPLOYMENT_TARGET` of
  27.0 down to 14.4 for reach, or keep 15.0 to simplify — final call in plan5 phase kickoff).
- **D4**: Preset data ported as JSON generated from the extracted `.fac` values (data, not code).
- **D5**: MVP = power + 10-band preset EQ + master boost + preset list + output picker (plan3).
