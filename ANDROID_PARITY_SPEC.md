# iOS ↔ Android Parity Spec

**Goal:** bring the iOS app (`/Users/aleksandarslavchev/Documents/SlavchevMachine/iOS/slavchevMachine`)
up to feature parity with the current Android app
(`/Users/aleksandarslavchev/Documents/SlavchevMachine/SlavchevMachine`).

The iOS app already has a solid core (sequencer, pads, looper, master EQ, multiband
compressor, scenes, kits, transport key bindings, onboarding). Everything below was added
to Android **after** the iOS port and is currently missing or different on iOS.

## How to use this document

- The **Android source is the reference implementation.** Each item lists the exact Android
  files to read. The C++ DSP (`app/src/main/cpp/*`) should be re-implemented in Swift DSP
  classes mirroring the existing iOS ones (`SlavchevMachine/Audio/*.swift`, e.g. `Biquad.swift`,
  `MasterEqualizer.swift`, `MultibandCompressor.swift` already show the manual-DSP pattern).
- Kotlin UI (`app/src/main/java/com/slavchev/machine/ui/*`) maps to SwiftUI views under
  `SlavchevMachine/UI/*`.
- Persistence on Android is SharedPreferences + JSON files; on iOS mirror with
  `SettingsStore`/`UserDefaults` + JSON files in Application Support (the iOS `SceneStore`/
  `KitStore` already show the pattern).
- Keep DSP parameter names/ranges identical so presets and behaviour match.

## Priority order (recommended)

1. FX subsystem (input effects) — biggest gap
2. FX scenes
3. Beatbox → beat (on-device DSP + optional Gemini cloud)
4. Full-state autosave (incl. recorded loop audio)
5. Master bus mixer (BEAT vs LOOP/LIVE)
6. Beat-only EQ (drums)
7. Pad mix LOCK
8. Smaller polish (tab order/labels, scrollable tabs, fills 9× + no-repeat + lead-in)

---

# 1. FX subsystem — per-channel input effects (LARGEST GAP)

**What it is:** A new **FX tab** with a chain of 5 real-time effects applied to the *input*
signal **per looper channel**, *before* the looper records — so the loop captures the wet
signal — and also heard live when monitoring is on. Two channels can carry two different chains.

**Android reference:**
- DSP: `app/src/main/cpp/Reverb.{cpp,h}`, `Amp.{cpp,h}`, `FxCompressor.{cpp,h}`,
  `FxDelay.{cpp,h}`, `Rotary.{cpp,h}`, `FxChain.h` (owns the chain + process order).
- Integration: `Looper.cpp` `feedInput()` — deinterleave per channel → `fxChains_[c].process()`
  → meter → monitor (lock-free `RingBuffer.h`) → record. `AudioEngine.cpp` `looperFx*`
  passthroughs; `native-lib.cpp` `nativeLooperFx*` JNI.
- Kotlin: `ui/FxState.kt` (state + presets + JSON), `ui/FxPane.kt` (UI modules), facade
  `audio/AudioEngine.kt` `looperFxAmp*/Comp*/Delay*/Rotary*/Reverb*`.

**Chain process order (per channel):** `Amp → Compressor → Rotary → Delay → Reverb`.

**Effect parameters (keep names/ranges identical):**
- **Reverb** (Dattorro figure-8 plate): `mix, decay, size, damping, preDelay`.
- **Tube Amp** (Overloud TH-U + Mark Studio voicing): `drive, bass, mid, treble, presence,
  vle, vpf, levelDb, cab` (RBJ biquad tone stack: peaking/low-shelf/high-shelf/low-pass/high-pass;
  tanh saturation; Markbass VLE/VPF + cab voicing).
- **Compressor** (Waves RComp style): `threshold, ratio, attack, release, makeup, opto, arc,
  warm`; expose a `gainReductionDb()` meter.
- **Delay** (FabFilter Timeless 3 / tape): `timeMs, feedback, mix, lowCut, highCut, drive,
  modRate, modDepth, drift`. **Tempo-synced note divisions:** 1/2, 1/4, 1/8, 1/16 + dotted
  variants; when synced, `effectiveMs` is computed from current BPM and re-pushed on tempo
  change (see `FxState.DelayState.effectiveMs/pushTime/onBpmChanged` and companion
  `NOTE_DIVISIONS`).
- **Rotary** (Strymon Lex / Leslie): `fast (bool), drive, mix, balance, accel, depth`
  (crossover + Doppler-modulated delay + tremolo + spin-up ramp).

**Presets:** Android ships preset banks per effect (see `FxState` companion: `AMP_PRESETS`,
`COMP_PRESETS`, `DELAY_PRESETS`, `ROTARY_PRESETS`, `REVERB_PRESETS`). Port the values verbatim.

**iOS implementation notes:**
- Add Swift DSP structs/classes under `Audio/Fx/` mirroring each C++ file. Use the existing
  `Biquad.swift` for the amp tone stack.
- Apply the chain in the looper input tap (where iOS currently feeds the looper — see
  `Audio/AudioEngine.swift` input/render path and `Audio/Looper.swift`). Process **per channel**
  before recording; for monitoring, route the wet signal to output (iOS already has a monitor
  path — reuse it). Use atomics/lock-free handoff equivalent (or `os_unfair_lock`-free SPSC ring
  like Android's `RingBuffer`).
- Parameters set from UI thread, read on audio thread — use atomics / `Atomic`-style wrappers.

**UI:** New `FxPane.swift` with one module per effect (sliders + enable toggle + a GR meter on
the compressor + cab toggle on the amp), a **channel chip selector** (per channel chain), and
the FX-scenes strip (see section 2). Mirror `ui/FxPane.kt` layout.

**Acceptance:** Selecting a channel and dialing an effect changes the live monitored sound and
the recorded loop captures it wet; switching channels shows that channel's independent chain;
delay locks to tempo and follows BPM changes.

---

# 2. FX scenes (shared snapshot of the whole FX tab)

**What it is:** A **single common** FX scene for the whole FX tab (all channels) — NOT per
channel. Save/load/delete/**rename** presets; the dialog shows, per channel, which effects are
in the chain and lets you activate/deactivate effects per channel for that scene. Separate from
the general (sequencer) scenes.

**Android reference:** `model/FxSceneStore.kt` (flat JSON store in `filesDir/fx_scenes/`,
sanitized filenames + display name in JSON; `list/save/load/delete/rename`),
`ui/FxScenesDialog.kt` (per-channel effect enable matrix, SAVE field, saved list with inline
rename + two-tap delete), and the `FxSceneNav` strip in `ui/FxPane.kt`. Serialization:
`FxState.toJson/fromJson` (all channels + monitor).

**iOS implementation:** `Model/FxSceneStore.swift` (JSON files in Application Support, mirror
`SceneStore.swift` conventions) + `UI/Dialogs/FxScenesDialog.swift` + a nav strip above the
channel chips in `FxPane.swift`.

**Acceptance:** Save current FX setup as a named scene; navigate scenes; rename and delete;
loading a scene restores every channel's chain + enabled effects + monitor state.

---

# 3. Beatbox → beat

**What it is:** A **BEATBOX** button opens a dialog: count-in (audible clicks), record one bar
of beatboxing, then **Transform** turns it into kick/snare/hi-hat steps on the sequencer grid.
Two engines: **on-device DSP** (default, offline) and **Gemini cloud AI** (optional, needs key).

**Android reference:**
- On-device DSP: `app/src/main/cpp/BeatboxAnalyzer.{cpp,h}`
  (`analyzeBeatbox(x, n, sampleRate, bpm, stepCount, outVel)` → `outVel` size `3*stepCount`,
  **role-major** kick(0)/snare(1)/hat(2)). Algorithm: hop=128 energy envelope → positive flux →
  threshold = mean·1.6 → local-peak onsets w/ ~50 ms refractory; per onset ~50 ms window →
  **Hann-windowed DFT** (≈40 log-spaced bins 60 Hz–14 kHz via rotating phasor) → **spectral
  centroid** + band energies (low <250 Hz, mid 250–4000, high >6000) + **zero-crossing rate**;
  **score-based** classification (kickScore/snareScore/hatScore), pick max; quantize
  `step = round(s/framesPerStep) % stepCount`; `vel = clamp(peak*200+25, 1, 127)`.
- Capture: `Looper.cpp` beatbox capture (`startBeatboxCapture/stopBeatboxCapture/beatboxData/
  beatboxLength/beatboxSampleRate`), `AudioEngine.cpp` `beatboxStart/Stop/Analyze/Pcm`,
  `native-lib.cpp` JNI.
- Cloud AI: `audio/GeminiBeatbox.kt` — builds 16-bit mono **WAV** from captured float PCM →
  base64 → POST to `gemini-2.5-flash:generateContent` with a **responseSchema**
  (`{kick:[], snare:[], hat:[]}` integer arrays) + a prompt describing the mouth-sound mapping;
  parses back into `3*stepCount` role-major velocities. Graceful fallback to on-device on any
  HTTP/parse error (surface the real error message).
- UI: `ui/BeatboxDialog.kt` (count-in via tone generator, phase machine idle/count/rec/
  thinking/done, preview grid KICK/SNARE/HAT × steps, AI·GEMINI / ON-DEVICE chips, source label,
  Apply). Apply writes velocities into the current section's matrix: KICK→pad0, SNARE→pad1,
  HAT→pad2 (`DrumMachineScreen.kt applyBeatbox`).
- Key storage: `SettingsStore.loadGeminiKey/saveGeminiKey`; Settings UI exposes a "BEATBOX AI
  KEY" field. Android added `INTERNET`/`ACCESS_NETWORK_STATE` permissions (iOS: ATS is fine for
  HTTPS; no extra entitlement needed).

**iOS implementation:**
- Port `BeatboxAnalyzer` to Swift (`Audio/BeatboxAnalyzer.swift`) — pure DSP, straightforward.
  You may use Accelerate/vDSP for the DFT if convenient, but a direct phasor DFT is fine.
- Capture one bar of mono input into a buffer (reuse the looper input tap; add a
  `beatboxStart/Stop/pcm` path on `AudioEngine.swift`).
- `Audio/GeminiBeatbox.swift` using `URLSession` (async/await); build WAV; `responseMimeType:
  application/json` + `responseSchema`. Store key in `SettingsStore` ("sm.gemini_api_key").
- `UI/Dialogs/BeatboxDialog.swift` with count-in (AVAudioPlayer/`AudioServicesPlaySystemSound`
  or a synthesized click), preview grid, engine toggle, fallback.
- Apply into the active section matrix (kick→pad0, snare→pad1, hat→pad2, sized to step count).

**Acceptance:** Beatbox a simple "b … k … ts" pattern → on-device produces a recognizable
kick/snare/hat grid; with a valid key the AI·GEMINI mode returns a tighter transcription; AI
failure cleanly falls back to on-device and shows why.

---

# 4. Full-state autosave (survive process kill, incl. loop audio)

**What it is:** Every change is persisted to an autosave state and restored on next launch
(including the recorded loop audio), so a phone call / backgrounding / kill doesn't lose work
or reset to defaults.

**Android reference:** `model/AppStateStore.kt` (`save/load` → `autosave.json`;
`saveLoop/loadLoop/clearLoop` → `autosave_loop.pcm` float32 LE; `clear`). Wiring in
`ui/DrumMachineScreen.kt`: `buildAutosaveJson(hasLoop)`, `saveAutosave()` (exports loop PCM via
`engine.looperExportPcm()`), `restoreAutosave(o)`, `restoreSounds(...)`; saved on lifecycle
`ON_PAUSE`; bootstrap restores autosave or loads the default kit.

**Autosave JSON keys (port all):** `paneMode, kit, sceneSetlist/sceneName, timeSig, section,
bpm, humanize, patA, patB, vols, padMixLock, sources, eq, beateq, beatDb, auxDb, comp (toJson),
looper{inDb,outDb,eqBands,routing,monitor,...}, fx (FxState.toJson), fx scene/monitor` — i.e.
the entire working state. (Match whatever the current Android `buildAutosaveJson` emits.)

**iOS implementation:** `Model/AppStateStore.swift` writing JSON + a float32 PCM file in
Application Support. Save on `scenePhase`/`UIApplication.didEnterBackgroundNotification`. Restore
on launch in `DrumMachineViewModel`. The loop PCM round-trips through the iOS looper
(`Looper.swift` export/import).

**Acceptance:** Make changes + record a loop → force-quit → relaunch → everything (incl. the
loop) is exactly as left.

---

# 5. Master bus mixer (BEAT vs LOOP/LIVE)

**What it is:** Two faders in the MASTER tab: one for the sequencer **beat** bus, one for
**everything else** (looper playback + live monitoring), in dB.

**Android reference:** C++ `AudioEngine.cpp` `setBeatBusGainDb/setAuxBusGainDb` (atomics,
pow10 dB). In `onAudioReady`: beat voices mixed → `*= beatGain`; aux (looper mix + monitor pull)
mixed into a scratch buffer → `out += aux * auxGain`. UI: `ui/MasterEqPane.kt` `MixFader`
(-24..+12 dB, double-tap = 0). State `beatBusDb/auxBusDb` in `DrumMachineScreen.kt`, persisted in
autosave (`beatDb`/`auxDb`).

**iOS implementation:** In `Audio/AudioEngine.swift` render path, apply a beat-bus gain to the
voice mix and an aux-bus gain to the looper+monitor sum before they're combined. Add two
`MixFader` sliders to `MasterEqPane.swift`.

**Acceptance:** Beat fader changes only the sequencer level; LOOP/LIVE fader changes only the
looper + monitor level; both persist.

---

# 6. Beat-only EQ (drums)

**What it is:** A second 8-band EQ that affects **only the sequencer drums** (the beat bus),
opened from a button in the MASTER tab under the BEAT fader. Global (outside per-scene state).

**Android reference:** C++ second `Equalizer beatEqualizer_` in `AudioEngine.{h,cpp}`;
`setBeatEqBandGain()`; in `onAudioReady` it runs on `out` **while it still holds only the drum
voices** (after beatGain, before aux sum). JNI `nativeSetBeatEqBandGain`; facade
`setBeatEqBandGain`. UI: `MasterEqPane.kt` `BeatEqButton` (glows when non-flat) → `BeatEqDialog`
(8 sliders, FLAT/reset; header "BEAT EQ · 8 BAND / AFFECTS ONLY THE SEQUENCER DRUMS / GLOBAL ·
NOT AFFECTED BY SCENES"). State `beatEqGains`, persisted in autosave (`beateq`).

**iOS implementation:** Add a second `MasterEqualizer` instance applied to the drum-voice sum
before the looper/monitor is added. Add the button + dialog to `MasterEqPane.swift`. Make the
header text equally explicit that it's drums-only and global.

**Acceptance:** Boosting/cutting a band changes only the drum timbre; looper/live unaffected;
persists across scene loads and relaunch.

---

# 7. Pad mix LOCK (global, scene-independent)

**What it is:** A **LOCK** button in the MIX tab (left of RESET) that locks the current pad
mixer globally so loading a scene does **not** change pad volumes, until unlocked. The button
must clearly communicate its effect.

**Android reference:** `ui/PadMixPane.kt` `LockButton` (🔓 LOCK ↔ 🔒 LOCKED, glows when active)
+ a one-line explainer that changes with state. State `padMixLocked` in `DrumMachineScreen.kt`:
on scene load, when locked, skip overwriting `padVolumes` from the scene and re-assert current
values to the engine. Persisted in autosave (`padMixLock`).

**iOS implementation:** Add `locked`/`onToggleLock` to `PadMixPane.swift`; add the lock state to
`DrumMachineViewModel`; guard the scene-load pad-volume application; persist in autosave.

**Acceptance:** Lock → load a scene → pad levels stay; unlock → load a scene → pad levels follow
the scene.

---

# 8. Smaller polish items

**8a. Tab order + labels.** Android order is **PADS · MIX · LOOPER · FX · MASTER** (LOOPER·FX
connected with a "·"); the EQ tab is labelled **MASTER**. iOS currently: PADS, MIX, EQ, LOOPER.
Reorder, add FX, rename EQ→MASTER. Ref: `DrumMachineScreen.kt ModeSwitcherRow`,
`ModeSwitcherRow.swift`.

**8b. Scrollable tab row.** Make the tab row horizontally scrollable so pills keep their shape
on narrow screens instead of squeezing (Android uses BoxWithConstraints + horizontalScroll +
widthIn(min = fullWidth) to stay centered when they fit). iOS: wrap the tabs in a horizontal
`ScrollView` that centers when content fits.

**8c. Fills: 9 variations each + no-repeat + lead-in.** Android `DrumMachineScreen.kt`:
`FILL1_VARIATIONS`/`FILL2_VARIATIONS` now have **9 each** (back-loaded, content in steps 10–15);
`fireFill` picks a random variation **that isn't the last one played** for that slot
(`lastFillIndex`); and when fired **while stopped**, the fill plays as a **lead-in/pickup** — the
ticker starts at `firstFillStep(fill)` with the base groove suppressed, then on bar wrap clears
the fill, fires a crash, and the groove proper begins. iOS currently has 3 each, pure random, and
just auto-starts playback. Port the extra variations (values verbatim from
`DrumMachineScreen.kt`), the no-repeat picker, and the lead-in (`fillIntroFromStep` + suppress
base while `fillLeadIn`). Ref: `Model/FillPatterns.swift`, `DrumMachineViewModel.swift`
`armFill()` + the ticker.

**8d. Settings: Gemini API key field.** Add a "BEATBOX AI KEY" section to `SettingsDialog.swift`
(read/write `SettingsStore` "sm.gemini_api_key"), with a hint linking to
aistudio.google.com/apikey. (Comes with #3.)

---

# Notes / non-gaps (do NOT treat as missing)

- **Multi-channel / USB input:** Android needed a custom usbfs UAC isochronous reader to recover
  discrete channels (HAL summed them to mono). iOS already does multichannel input natively via
  `AVAudioSession` + looper routing — **keep the native approach**; no port needed.
- **Loop-present indicator:** Android added a dot under the LOOP button; iOS uses state-colored
  button labels (EMPTY/ARM/REC/LOOP/…) — already equivalent.
- **Latency compensation / monitor level:** iOS already has latency comp + a user offset slider —
  comparable to Android's monitor/latency handling.

# Definition of done

Each section's **Acceptance** holds, the FX/beatbox/EQ/mixer/lock state all round-trips through
autosave (#4), DSP parameter names/ranges match Android (so presets are portable), and the
MASTER/MIX/FX tabs match Android's order, labels, and scroll behaviour.
