# Plan 5 — Phase 1: Audio engine core (tap → aggregate → ring → engine → output)

**Milestone M1: "Sound flows through the app."** Music playing anywhere on the Mac is captured,
passed through the engine, and heard from the selected output; the power button creates/destroys
the whole chain. EQ is pass-through at this stage (bypassed EQ node).

---

## 1. Project prep (in the existing `fxsound.xcodeproj`)

1. Set `MACOSX_DEPLOYMENT_TARGET` = **14.4** (or 15.0 — decision D3; both support taps).
2. Info.plist additions: `NSAudioCaptureUsageDescription = "FxSound processes your Mac's audio to
   apply the equalizer and volume boost. Audio stays on this device."`
   *(Xcode's Info.plist key dropdown may not list it — type it manually.)*
3. App Sandbox: keep **on**; enable *Audio Input* entitlement. (Direct-distribution variant:
   sandbox off + Developer ID — noted for plan9.)
4. Add `import CoreAudio`, `import AudioToolbox`, `import AVFoundation` targets/files per plan4.

## 2. `SystemTap.swift`

- `func create() throws -> Tap`
  - `CATapDescription.initStereoGlobalTapButExcludingProcesses([pid(Foundation.ProcessInfo.processInfo.processIdentifier)])`
  - mute behavior: `.whenRunning` (mute the tapped/original output while the tap lives)
  - `AudioHardwareCreateTap(description, &audioObjectID)`; read `uuid` via
    `kAudioTapPropertyUUID`, format via `kAudioTapPropertyFormat` (expect 44.1/48 kHz Float32
    deinterleaved or interleaved stereo — handle both by carrying the actual `AVAudioFormat`).
- `func destroy()` — `AudioObjectRemovePropertyListener` (if any) + `AudioHardwareDestroyTap`.
- Log every call with `os.Logger(.audio)`; wrap OSStatus into typed errors.

## 3. `AggregateEngine.swift`

- `start(output: AudioDevice, tap: Tap) throws`:
  1. Build aggregate dict:
     `kAudioAggregateDeviceNameUIDKey` = `"com.aliahad.fxsound.aggregate"`,
     `kAudioAggregateDeviceIsPrivateKey = true`,
     `kAudioAggregateDeviceMainSubDeviceKey` = output UID (clock master),
     `kAudioAggregateDeviceTapListKey` = `[{kAudioSubTapUIDKey: tap.uuid,
        kAudioSubTapDriftCompensationKey: true}]`,
     plus the output device in `kAudioAggregateDeviceUIDListKey` (tap gets its own private UID).
  2. `AudioHardwareCreateAggregateDevice` → `AudioDeviceCreateIOProcIDWithBlock`:
     - pull input `AudioBufferList` → `AVAudioPCMBuffer` (`bufferListNoCopy`, nil deallocator)
     - `ringBuffer.write(buffer)` (drop-oldest on overflow, count overruns in an atomic)
     - hop a zero-copy reference to `SpectrumAnalyzer` (later phase).
  3. `AudioDeviceStart`.
- `stop()` — `AudioDeviceStop` → `AudioDeviceDestroyIOProcID` → `AudioHardwareDestroyAggregateDevice`.
- Ring buffer: 200–500 ms capacity SPSC (contiguous Float32, channels preserved), caches format.

## 4. `ProcessingEngine.swift` (AVAudioEngine graph)

```
AVAudioSourceNode(render: pull RingBuffer → frame)   // our render-DSP home in phase 2
   → AVAudioUnitEQ(numberOfBands: 12)                // 10 EQ + bass-shelf + treble-shelf (phase 2)
   → AVAudioUnitDynamicsProcessor (.peakLimiter)     // ceiling −0.5 dBFS, armed when boosting
   → engine.mainMixerNode → engine.outputNode
```

- Output device: `kAudioOutputUnitProperty_CurrentDevice` on `outputNode.audioUnit`
  = selected device (or system default).
- `start()/stop()` with `AVAudioEngine` manual rendering defaults; all node params behind an
  atomic snapshot updated by AppController.
- Power off = `engine.stop()` + `AggregateEngine.stop()` + `SystemTap.destroy()` (reversed order),
  ~instant, system audio resumes unmuted because the tap's mute dies with it.

## 5. Lifecycle, edge cases & acceptance tests

- **Own-process exclusion** verified: no runaway loop/echo when engine output = tapped content.
- **Ordering bug-guards**: never destroy the tap before the aggregate (mute release ordering);
  guard double-start/double-stop idempotency.
- **Device change mid-stream** (basic): default output changes → stop chain, rebuild aggregate
  with new device, start (≤1 s gap). Full UX in plan8.
- **Sleep/wake & sample-rate change**: listener on `kAudioDevicePropertyNominalSampleRate` and
  aggregate invalidation → full rebuild.
- **Silent-failure self-test** (`Permissions`): after start, while `CoreAudio` reports non-idle
  system, RMS>0 expected within 5 s; else set `permissionState = .silentFailure` and power off.

### Acceptance checklist (M1 done when)
- [ ] Play Apple Music/YouTube → hear audio through the app; Audio MIDI Setup shows the private
      aggregate while running and nothing while off.
- [ ] Power toggle: audio reverts to normal within 200 ms and re-routes through the app on re-enable.
- [ ] Kill the app while running: system audio returns (no stuck mute) — also verified after
      force-quit (aggregate/tap are object-lifetime owned; document any recovery step needed).
- [ ] No glitching for 30 min; IOProc overrun counter stays 0; CPU < 5 % on M4.
- [ ] Works on built-in speakers, HDMI, and a Bluetooth headset.
