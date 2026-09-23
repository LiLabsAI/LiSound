# Plan 9 — Phase 5: Permissions, packaging, testing, roadmap

**Milestone M5: "Shippable build."** A notarized app with a clean first-run story, a test pass,
and a documented backlog.

---

## 1. Permissions hardening (the make-or-break UX)

- Matrix covered by `Permissions.swift` + UI states (plan3 §4): unknown → welcome; TCC prompt
  shown on first enable; denied → guidance card with deep link
  (`x-apple.systempreferences:com.apple.preference.security?Privacy_AudioRecording`) + re-test;
  silent-failure (zero buffers while system plays) → same guidance + "Still broken? Send report".
- Re-check on window focus and on `NSWorkspace` wake notifications.
- Regression test: run the app with the Info.plist key removed in a debug scheme — confirm the
  silent-failure detector fires (guards against future key loss).

## 2. Known limitations to document in-app (About → Notes)

- DRM-protected content (e.g. some Apple TV/streaming apps) may bypass or mute through taps.
- Microphone-isolated modes / some call apps route around taps by design.
- Latency ~20–50 ms; not for monitoring-critical workflows (e.g. live guitar via BT).
- macOS 14.4+ required (documented BlackHole manual fallback for older systems).

## 3. Performance & stability pass

- Instruments: Time Profiler (audio threads ≤ 3 % CPU each), Allocations (steady state flat after
  30-min soak), Audio Unit latency report; assert ring buffer never overruns at 44.1/48/96 kHz.
- Chaos checklist: sleep/wake, fast user switching, screen lock, device plug/unplug storms,
  sample-rate flips, force-quit recovery, two displays w/ different outputs, AirPlay drop.
- Energy: App Nap eligible when power off; no timers when window closed & power off.

## 4. Packaging & distribution

- **Direct download (v1)**: Developer ID Application signing + notarization (`stapler`),
  DMG with drag-to-Applications; Sparkle for updates (appcast later).
- **App Store (v2)**: App Sandbox already on; remove private-API usages (none planned — AudioCap's
  TCC hacks are *not* needed since we use the documented prompt flow); screenshot/privacy-label
  ("Audio Recording — processes audio on device").
- Build automation: `xcodebuild archive -configuration Release` script in `Scripts/`; version bump
  & changelog checklist.
- Icon: original artwork (SF-symbol-derived speaker+sliders), all sizes incl. menu-bar template.

## 5. Full test plan (consolidated acceptance)

| Area | Gate |
|---|---|
| M1 audio path | plan5 checklist green |
| M2 DSP | plan6 checklist incl. null test at bypass |
| M3 presets | plan7 checklist incl. round-trip import/export |
| M4 daily use | plan8 checklist incl. hotkeys/device storms |
| Permissions | all four states reachable & correct UI |
| Perf | gates in §3 pass on M4 hardware (and one Intel Mac if available) |
| i18n | EN complete; RTL smoke test |
| Fresh-install run-through | download → open → enable → boost → restart Mac → still configured |

## 6. Backlog (post-v1, pulled from FxSound parity + Mac-native ideas)

1. URL scheme/CLI remote control (`fxsound://preset/Music`, `--status` JSON parity — plan1 §7).
2. Bonus preset pack UI + community preset sharing.
3. Per-app profiles (tap is per-process-capable: "Music app only" EQ).
4. Parametric page (free band placement) & presets import from `.fac`/`.aps`/REW.
5. Loudness-normalized "night mode", crossfeed for headphones, virtualizer upgrade (AirPods
   spatial-style HRTF behind a research spike).
6. Local network remote / Shortcuts actions / Now-Playing integration.
7. Optional BlackHole-bundled "classic mode" for macOS < 14.4 builds.

## 7. Execution order & effort sketch (solo dev, focused)

| Phase | Plans | Estimate | Depends on |
|---|---|---|---|
| P1 engine core | plan5 | 3–5 d | — (riskiest: do first) |
| P2 DSP | plan6 | 4–6 d | P1 |
| P3 presets | plan7 | 2–3 d | P2 (values audible) |
| P4 device/UI/hotkeys/settings | plan8 | 4–6 d | P1 (UI can start in parallel after P1 lands) |
| P5 polish/package | plan9 | 2–4 d | all |

Critical path: P1 → P2 → P3/P4 → P5. Highest-risk item (tap + aggregate + mute ordering + TCC)
is Milestone M1 — prove it before building anything else on top.
