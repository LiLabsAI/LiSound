# Plan 6 — Phase 2: EQ & effects DSP

**Milestone M2: "The EQ works."** The 10-band preset EQ audibly shapes sound, master gain boosts
volume safely, effect sliders do something perceptually real, and the spectrum visualizer dances.

---

## 1. `EQParameters.swift` — the band model (FxSound parity)

- Band counts: **5, 10, 15, 20, 31** (default 10) — FxSound `--num_bands` set.
- Default 10-band centers (FxSound "Default" preset): `62.5, 121.5, 225, 416.5, 770.5, 1425,
  2645, 4895, 9060, 13885` Hz (log-spaced); for other counts generate log-spaced 31.5 Hz–16 kHz
  layouts; per-band centers remain user-movable within neighbor bounds (`getEqBandFrequencyRange`
  parity: center ± ~1/3 octave).
- Gain: **±12 dB** per band. Q: `filterQ` multiplier **1.0–3.0** (default 1.0) →
  `AVAudioUnitEQ.bandwidth` (octaves) = `octavesPerBand / q` where `octavesPerBand` derives from
  the band layout; clamp 0.1–2.0 octaves. Unit-test the mapping.
- Implementation: one `AVAudioUnitEQ` sized to `maxBands = 31 + 2` (see below); unused bands
  `bypass = true` so band-count switching is allocation-free.

## 2. Effect mapping (`EffectChain.swift`) — perceptual equivalents of DFX

Every slider is 0.0–10.0, linear UI, mapped through the curve noted. Documented, testable,
deliberately *not* a copy of DFX's proprietary networks (plan1 §8).

| Effect (0–10) | Implementation in the chain |
|---|---|
| **Bass** | Low-shelf @ 100 Hz, gain `0…+12 dB` (`v*1.2`), Q n/a. Engages with ≥0.5. |
| **Fidelity** (clarity) | High-shelf @ 7 kHz, gain `0…+9 dB` (`v*0.9`). |
| **Ambience** | Stereo width (mid/side): `sideGain = 1 + v*0.35`, subtle crossfeed `≤ 8 %` at low frequencies — in `RenderDSP`. |
| **Surround** (3D) | Wider width `sideGain = 1 + v*0.55` + tiny complementary mid cut (−`v*1.5 dB`) to open the stage; optional 8–14 ms unilateral Haas micro-delay behind a flag (off by default; latency-safe). |
| **Dynamic Boost** | Loudness contour tied to master gain: when master < −6 dB or source is quiet, tilt EQ (low-shelf +`v dB` @ 80 Hz, high-shelf +`v*0.6 dB` @ 10 kHz), `v = v*1.0` scaled by deficit. MVP: static mapping; AGC-aware version later. |
| **Master gain** (−20…+20 dB) | `AVAudioUnitEQ.globalGain`. For `> 0`: pre-gain `−(gain*0.35) dB` into the limiter so boosts stay clean instead of clipping (headroom management; limiter ceiling −0.5 dBFS). |
| **Balance** (−20…+20 dB) | Channel gains in `RenderDSP`: weak side `−|b| dB`, strong side untouched; at ±20 also allow −3 dB mid attenuation (FxSound's extreme behavior approximated). |
| **Volume leveling** (0–4 dB) | Slow RMS AGC in `RenderDSP`: 1 s attack / 4 s release, target median loudness snapshot per session, makeup capped at the slider value; bypass when 0. |

## 3. `RenderDSP.swift` (the custom `AVAudioSourceNode` stage)

One render closure does: ring-buffer pull → deinterleave → mid/side width → balance gains →
leveling AGC → hand frame downstream. vDSP ops only; atomics for params; no allocation; per-callback
work bounded; denormals flushed. Slider changes land via a param block with 15 ms ramps
(zero zipper noise). Unit tests: gain matrices, width matrix identity at v=0, AGC time constants
on synthetic ramps.

## 4. `SpectrumAnalyzer.swift`

- Source: extra `ringBuffer` reader (or post-EQ tap copy) at ≤ 60 Hz cadence.
- vDSP FFT (size 2048, Hann), 10 log bands 50 Hz–16 kHz, per-band RMS → dB → normalized 0–1,
  peak-hold decay for the UI; published via a lock-free triple buffer read on main at 30 Hz.
- Drives `VisualizerView` (SwiftUI Canvas bars — FxSound's 10-band visualizer parity).

## 5. EQ UI plumbing (minimal now, full polish in plan8)

`ProView` renders n vertical sliders bound to `AppState.eq.bands[i].gain`, drag = set gain,
double-click = 0 dB; Q stepper; band-count picker; EQ on/off. Bands' center freq labels update on
band-count change. This phase ships the controls; styling follows plan8.

### Acceptance checklist (M2 done when)
- [ ] Bass Boost preset audibly boosts low end; treble presets audible on headphones.
- [ ] Sliders change sound in < 50 ms, no clicks/zipper.
- [ ] Master +10 dB on loud content: no clipping (limiter engages, meter confirms), +20 dB
      usable on quiet content.
- [ ] Balance extremes: opposite channel silent at ±20 without pathologies.
- [ ] Band count switch preserves perceived curve (no level jump).
- [ ] Visualizer tracks music at 30 fps, < 1 % CPU.
- [ ] Bypass (EQ off + all effects 0 + gain 0) is audibly/numerically transparent:
      null test vs. phase-1 passthrough within −60 dB.
