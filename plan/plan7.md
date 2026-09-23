# Plan 7 — Phase 3: Presets system

**Milestone M3: "Presets work."** The 13 FxSound built-ins are selectable and sound as intended;
users can save, rename, delete, undo, auto-save, import/export.

---

## 1. `Preset.swift` — the model (JSON, Codable)

```swift
struct Preset: Codable, Identifiable {
    var id: UUID
    var name: String
    var isBuiltIn: Bool
    var effects: EffectsState          // bass, fidelity, ambience, surround, dynamicBoost (0…10)
    var masterGainDB: Double           // −20…+20
    var balanceDB: Double              // −20…+20
    var levelingDB: Double             // 0…4
    var filterQ: Double                // 1.0…3.0
    var eqOn: Bool
    var bands: [Band]                  // center Hz + gain dB  (any count 5…31)
}
```
`v` field for future migration. One file per user preset in
`~/Library/Application Support/FxSound/Presets/<uuid>.json`; built-ins are bundled
`BuiltInPresets.json` (read-only).

## 2. Porting the 13 built-ins (data extraction → `BuiltInPresets.json`)

`.fac` layout (from plan1 §6): 6 `Main` values (scaled ints) + per-band `CF`/`Boost/Cut` lines.

**Extracted band centers per preset** (from `Installer/Resources/Factsoft/*.fac`, all 10-band):

| Preset | Band centers (Hz) |
|---|---|
| Default | 62.5, 121.5, 225, 416.5, 770.5, 1425, 2645, 4895, 9060, 13885 |
| General | 62.5, 115, 250, 450, 630, 1250, 2700, 5300, 7500, 13000 |
| Music | 62.5, 110, 250, 370, 650, 1200, 2130, 4550, 6850, 16000 |
| Voice / Movies / TV / Streaming Video / Gaming / Light & Classic Processing / Bass Boost / Volume Boost / Transcription | (own log-ish sets — extracted to CSV during implementation; script reads all files, no hand transcription) |

**`Main[0…5]` → semantic mapping** (implementation task #1 of this phase, ≤ half a day):
map each preset's 6 main values onto `effects/masterGain/leveling` by cross-reading
`dsp/DfxDspPrivate.cpp` + `u_dfxp.h` (which registry/dfxp parameter each `Main i` writes) and the
known UI defaults (e.g. *Default* = all zeros = neutral; *Volume Boost* has the largest master
boost; *Transcription* emphasizes speech band 3430/4630 Hz). Validation: after mapping, no
built-in exceeds documented ranges, *Default* is fully neutral, and *Voice/Transcription* cut the
low band (their `.fac` curves do). If ambiguity remains for an index, set it to the *Default*
value and note it — audible QA with music/voice tracks decides.

Also port **bonus presets** if the mapping generalizes cleanly (70's, 80's, Alternative Rock,
Classical, Classic Rock, Jazz, Metal, Modern Country, Modern Rock, Pop, R&B, Trap) from
`bin/BonusPresets/*.fac`; else ship the 13.

## 3. `PresetStore.swift` — lifecycle (FxSound parity)

- `presets: [Preset]` (built-ins first, user's alphabetical); `select(_: )` applies via
  AppController (atomic param push, 20 ms crossfade between old/new curve).
- **Autosave/modified semantics**: edits to the active preset mark `modified`; leaving the preset
  or app quit auto-saves to a shadow copy (user preset if user's, shadow-overlaid if built-in);
  undo reverts to the stored copy (single-level, FxSound parity); "Reset Presets…" restores all
  built-ins to factory (with confirm).
- CRUD: Save New Preset… (name uniqueness enforced), Overwrite (user presets only), Rename,
  Delete (user only), Import…/Export… (`JSON`, `.fxsoundpreset`; optional `.fac` reader —
  straightforward text parse if desired).
- Built-ins are **never** written; user edits of a built-in live in the shadow file.

## 4. Preset UI (in `ProView`/`LiteView`)

- Combo: grouped list "Presets" / "My Presets"; active preset bold; `•` modified dot; ↩ undo
  button; ✎ rename; 🗑 delete (user only); "Save As New…" row.
- Import/Export buttons in Preset menu; drag-and-drop `.fxsoundpreset` onto the window imports.

### Acceptance checklist (M3 done when)
- [ ] All 13 built-ins appear and each sounds like its name (QA pass with 3 reference tracks +
      a podcast: Bass Boost thumps, Voice clarifies dialog, Volume Boost loudens).
- [ ] Switching presets mid-playback is click-free and < 100 ms.
- [ ] Save/rename/delete/undo/reset/autosave all work; app relaunch restores state exactly.
- [ ] Export → delete → import round-trips a user preset byte-equivalently.
- [ ] Built-ins remain pristine after editing them (shadow semantics verified).
