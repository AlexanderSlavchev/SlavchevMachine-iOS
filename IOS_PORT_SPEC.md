# SlavchevMachine — iOS Port Specification

A complete, implementation-ready description of **SlavchevMachine** for porting
the existing Android app (Kotlin + Jetpack Compose + C++/Oboe) to **iOS**
(Swift + SwiftUI + AudioUnit / AVAudioEngine). The goal is a maximally
**identical** experience — same audio behaviour, same gestures, same visual
language.

Read top-to-bottom for context; jump to a numbered section for the spec of a
specific subsystem.

---

## Contents

0.  [Document purpose & scope](#0-document-purpose--scope)
1.  [Application overview](#1-application-overview)
2.  [Recommended iOS technology stack](#2-recommended-ios-technology-stack)
3.  [Audio engine](#3-audio-engine)
4.  [Pads, kits, samples](#4-pads-kits-samples)
5.  [Step sequencer](#5-step-sequencer)
6.  [Time signatures](#6-time-signatures)
7.  [Beat library](#7-beat-library)
8.  [Tempo, BPM, tap tempo, lock](#8-tempo-bpm-tap-tempo-lock)
9.  [Master EQ](#9-master-eq)
10. [Multiband compressor](#10-multiband-compressor)
11. [Audio looper](#11-audio-looper)
12. [LOOPER pane (input/output, EQ)](#12-looper-pane-inputoutput-eq)
13. [Scenes & setlists](#13-scenes--setlists)
14. [Saved-loops manager](#14-saved-loops-manager)
15. [Beat-library dialog & user presets](#15-beat-library-dialog--user-presets)
16. [Hardware key control](#16-hardware-key-control)
17. [Onboarding (interactive tour)](#17-onboarding-interactive-tour)
18. [Settings](#18-settings)
19. [UI / UX design language](#19-ui--ux-design-language)
20. [Main-screen layout](#20-main-screen-layout)
21. [Pane layouts](#21-pane-layouts)
22. [Dialog patterns](#22-dialog-patterns)
23. [Gesture reference](#23-gesture-reference)
24. [Permissions & background](#24-permissions--background)
25. [Persistence summary](#25-persistence-summary)
26. [Algorithms & code references](#26-algorithms--code-references)

---

## 0. Document purpose & scope

This document is the **single source of truth** for an iOS implementation. It
specifies:

- The app's **features** and exact **behaviour**.
- All **constants**, **ranges**, **defaults** and **data formats** used by the
  Android version (which the iOS port must mirror).
- The **UI/UX** in enough detail (colour, type, spacing, gestures, animation)
  to produce a near-identical look and feel.
- Where the Android implementation uses a platform-specific mechanism, the
  recommended iOS equivalent.

It does **not** prescribe Swift code — the iOS implementer should choose
idiomatic Swift / SwiftUI patterns. It prescribes **what** and **how it
behaves**.

---

## 1. Application overview

**SlavchevMachine** is a **drum machine and groovebox** for handheld devices,
inspired by the **Alesis SR-18**. The user plays drums on 16 velocity-sensitive
pads, programs a step sequencer, mixes through a master EQ and a multiband
compressor, records audio loops synced to the sequencer, and saves the whole
state as scenes organised into setlists for live performance.

Core characteristics:

- **Native low-latency audio** (sub-15 ms round-trip on capable devices).
- **Touch-first** — every parameter is a direct gesture (drag, tap, long-press).
- **Live-performance ergonomics** — scenes, setlists, hardware foot-pedal
  bindings, foreground audio playback under lock screen.
- **Dark, neon-LCD aesthetic** — monospace technical type, accent-coloured
  glows, gradient chassis backgrounds.

The app is intentionally **scope-bounded**: it is not a DAW. It does one thing
— grooveboxing — and does it with as little visual chrome as possible.

---

## 2. Recommended iOS technology stack

| Concern | Android (current) | iOS recommendation |
|---|---|---|
| UI framework | Jetpack Compose | **SwiftUI** (declarative, mirrors Compose) |
| Audio engine | C++ + Google Oboe (AAudio/OpenSL ES) | **AudioUnit** (`AURemoteIO` / `kAudioUnitSubType_VoiceProcessingIO` *not* recommended — use `RemoteIO` for music) with C++ DSP behind it. **AVAudioEngine** is a viable fallback but `AudioUnit` is closer to Oboe in latency profile. |
| Real-time audio thread | Oboe data callback | `AURenderCallback` (C function pointer, never allocates). |
| Sample decoding | Custom WAV parser | `ExtAudioFile` / `AVAudioFile` (system decoders cover PCM, AAC, ALAC, FLAC). |
| Persistence | SharedPreferences + filesDir | `UserDefaults` + `FileManager` (`Application Support/` for setlists). |
| Hardware keys | `dispatchKeyEvent` + AccessibilityService | `UIKeyCommand` on the responder chain (foreground only — see §16/§24). |
| Background audio | Foreground service | iOS `audio` UIBackgroundMode + `AVAudioSession` `playAndRecord`. |
| Mic permission | `RECORD_AUDIO` runtime grant | `NSMicrophoneUsageDescription` + `AVAudioSession.requestRecordPermission`. |
| File-picker | `OpenDocument` ActivityResult | `UIDocumentPickerViewController` / `.fileImporter`. |

**Minimum iOS:** iOS 15.0 recommended (SwiftUI `onChange` etc. mature).
**Target device:** iPhone (portrait). The Android version's layout is built for
phones in portrait orientation; iPad support is a later step.

---

## 3. Audio engine

### 3.1 Topology

A single output stream (stereo, default device rate — typically 48 kHz) and,
when the user uses the looper, a second **input** stream.

```
                                       ┌──── Master EQ (8-band)
voices ┐                              │
       ├──► mixer bus ──► looper mix ─┤
loop   ┘                              │
                                       ├──── Multiband Compressor (4-band)
                                       │
                                       └──── Soft clip ──► output
```

### 3.2 Constants

```
kNumPads        = 16
kMaxVoices      = 32        // polyphony
kMaxPadLayers   = 3         // round-robin variants per pad
kPadCloseHat    = 4         // pads that participate in the hi-hat choke
kPadOpenHat     = 5
outputSampleRate (default) = 48000
outputChannels  = 2 (stereo)
```

### 3.3 Voice mixer

A flat array of **32 voices**. A `Voice` holds:

- `sample: atomic<const Sample*>` — non-null while playing.
- `frameIndex: int64` — current read position.
- `gain: float` — velocity × pad volume.
- `padIndex: int32` — which pad triggered it (for choke groups).

**Lock-free triggering.** The UI / JNI thread picks the first voice with
`sample == null`, writes `frameIndex`/`gain`/`padIndex`, then **release-stores**
`sample`. The audio thread does an **acquire-load** of `sample` per voice and
either mixes or skips. No locks, no allocations on the audio path. (On iOS:
use `atomic<…>` from `<atomic>` in the C++ DSP, with the same ordering.)

**Voice stealing.** If all 32 voices are busy, the trigger is dropped (no
stealing in the current implementation — out of scope for v1 of the port too).

**Choke groups.** Triggering pad `kPadCloseHat` (4) silences any voice with
`padIndex == kPadOpenHat` (5), and vice-versa — the classic closed-chokes-open
hat behaviour.

### 3.4 Sample storage

`SampleStore` keeps decoded samples alive by **integer id**. A sample is:

```
struct Sample {
    std::vector<float> data;   // interleaved, float32
    int32_t channels;
    int32_t sampleRate;
    int64_t frameCount;
}
```

WAV decoding supports PCM 16/24/32-bit and 32-bit float. On iOS, replace the
custom decoder with `ExtAudioFile` set to `AVAudioCommonFormat.pcmFormatFloat32`.

### 3.5 Sample-rate handling

Samples are played back at the device output rate **without resampling** —
loading a 44.1 kHz sample on a 48 kHz device shifts the pitch ~9 %. This is a
known limitation; the iOS port can simply use `AVAudioConverter` to resample on
load if desired (recommended).

### 3.6 Per-pad volume

`std::atomic<float> padVolumes_[16]`, range `0…1`. Applied at trigger time:
`voice.gain = velocity × padVolumes_[pad]`.

### 3.7 Soft-clip

After the compressor, a per-sample soft clip:

```
out[i] = clamp(out[i], -1, +1)
```

(The current implementation uses a hard clamp; a `tanh()` or similar curve
would be more musical and is a recommended polish.)

---

## 4. Pads, kits, samples

### 4.1 Pad labels (one kit currently — DRUMS · CAJON·KIT)

| Idx | Label  | Canonical filename |
|----:|--------|--------------------|
| 0   | KICK   | `kick`             |
| 1   | SNARE  | `snare`            |
| 2   | RIM    | `snare2`           |
| 3   | CLAP   | `clap`             |
| 4   | C-HAT  | `hihat`            |
| 5   | O-HAT  | `hihatOpen`        |
| 6   | RIDE   | `ride`             |
| 7   | CRASH  | `crash`            |
| 8   | TOM L  | `tomL`             |
| 9   | TOM M  | `tomM`             |
| 10  | TOM H  | `tomHi`            |
| 11  | CB     | `cb`               |
| 12  | SHKR   | `shkr`             |
| 13  | PERC   | `perc`             |
| 14  | FX 1   | `fx1`              |
| 15  | FX 2   | `fx2`              |

Pads 4 and 5 are the **choke pair** (close-hat chokes open-hat).

### 4.2 Velocity by finger Y

When a pad is touched, the velocity is `1 - (touchY / padHeight)` clamped to
`[0, 1]` — top of the pad = soft, bottom = loud. (UI shows a velocity bar that
grows from the bottom as the finger descends.)

### 4.3 Round-robin (machine-gun killer)

A pad may have up to **3** sample variants (e.g. `hihat`, `hihat_sample2`,
`hihat_sample3`). On each trigger:

- If count == 1, play it.
- Otherwise pick a random index ≠ the last index played for that pad. The
  native engine uses an internal **xorshift32 PRNG** to avoid `rand()` calls
  on the audio thread.

The user assigns variants through the per-pad sample picker (multi-select up
to 3 files).

### 4.4 Loading samples

- **Long-press a pad** → system file picker → choose `.wav`s (1–3).
- **Bundled kits** — for each pad, the engine loads `<kit>/<filename>.wav`
  from the app's sample directory at startup.

---

## 5. Step sequencer

### 5.1 Model

- Step = a **16th note**.
- Bar length = `numerator × 16 / denominator` steps (capped at 32 — see §6).
- For each pad, the sequencer stores a `velocity: 0…127` per step
  (`0` = off, `1–127` = on with that velocity).
- Two sections **A** and **B** (independent matrices) — the user flips between
  them; when a new scene/preset is loaded, **B** is auto-seeded as a musically-
  related variation of A.

### 5.2 The ticker

A Kotlin coroutine on `Dispatchers.Default`:

```
while (playing) {
    delay(intervalMs)          // intervalMs = round(60000 / bpm / 4)
    currentStep = (currentStep + 1) mod stepCount
    for each enabled pad row:
        if matrix[pad][currentStep] > 0: trigger pad with that velocity
    if currentStep == 0: signal "bar start" (used by looper, metronome, fills)
}
```

**Important caveat for iOS:** the Android ticker uses `delay(intervalMs.toLong())`,
which rounds to integer milliseconds and drifts at non-round BPMs (e.g. at 130
BPM a bar is ~6 ms short). The iOS port should compute an **absolute target
time** for each step (`hostTime + n × stepFrames`) and sleep to it, using
`mach_absolute_time` or a similar precise clock, to eliminate this drift.

### 5.3 A → B section derivation (`PatternVariation`)

When seeding B from A: count active steps in A; if A is sparse, B is a busier
variant; if A is busy, B is a lighter variant. (Implementation: pick a small
subset of A's steps to drop or add, weighted toward off-beats. See
`PatternVariation.deriveBSection` in the Android source for the exact rules.)

### 5.4 Fills

Two fill slots — **Fill 1** (snare-led) and **Fill 2** (tom-led). Triggering a
fill schedules a fixed pattern to start on the **next bar** instead of the
normal section's row. When the fill ends (next bar wrap), the engine plays a
**crash** (pad 7) on step 0 of the new bar — the "fill resolves into a crash"
behaviour.

### 5.5 Humanize

A toggle. When on, each scheduled trigger is randomly delayed by a few ms
(uniform in `[0, ~12ms]`) so the groove breathes.

### 5.6 Metronome

A click on each **beat-group start** (see §6 grouping) — accent on step 0,
soft on the other group starts. Click sound = pad `PAD_CLICK = 2` (the RIM
sample).

---

## 6. Time signatures

### 6.1 Model

```
struct TimeSignature(numerator: Int, denominator: Int)
```

- `stepCount = numerator × 16 / denominator` (sixteenths).
- `denominator ∈ {2, 4, 8, 16}`.
- Cap: `MAX_STEPS = 32`.

### 6.2 Common presets (offered in the picker)

```
4ths : 2/4 3/4 4/4 5/4 6/4 7/4
8ths : 3/8 5/8 6/8 7/8 9/8 12/8
16ths: 5/16 7/16 11/16 13/16
```

Default = **4/4**.

### 6.3 Beat grouping (for metronome accents and on-screen shading)

```kotlin
val unit = 16 / denominator                // sixteenths per beat unit
val beatGroups: List<Int> = when {
    isCompound ->
        List(numerator / 3) { 3 * unit }    // 6/8 → [6,6]; 9/8 → [6,6,6]; 12/8 → [6,6,6,6]
    denominator <= 4 || numerator <= 4 ->
        List(numerator) { unit }            // 3/4 → [4,4,4]; 4/4 → [4,4,4,4]
    else -> {
        // odd/additive — pairs of 2, with a trailing 3 if the count is odd
        // 5/8 → [2,2,3]·unit ;  7/8 → [2,2,3]·unit ;  11/16 → [2,2,2,2,3] ; 13/16 → [2,2,2,2,2,3]
    }
}

isCompound = denominator >= 8 && numerator >= 6 && numerator % 3 == 0
```

`groupStartSteps` = the set of step indices where a beat group begins (used by
the metronome to choose accent vs soft click, and by `SequencerRow` to draw a
3-level shading — step 0 brightest, other group starts mid, in-between
darkest).

### 6.4 Bar length in frames (used by the looper)

`barFrames = round(60 / bpm / 4 × stepCount × sampleRate)`

---

## 7. Beat library

### 7.1 BeatStyle categories

```
JAZZ · POP · HIPHOP · R&B · LATIN · BOSSA · SWING ·
6/8 · COMPOUND · WALTZ · UNEVEN · MARCH
```

Built-in presets are organised by category and shown as filter chips in the
Beat Library dialog.

### 7.2 Velocity shorthand (in `DefaultPresets`)

```
A = 127  (accent)
S = 110  (strong)
M =  90  (medium)
L =  70  (light)
G =  50  (ghost)
```

### 7.3 Preset factory

```kotlin
beat(
    name: String, style: BeatStyle, bpm: Float,
    timeSignature: TimeSignature = 4/4,
    kick = ..., snare = ..., rim = ..., clap = ...,
    hat = ..., hatOpen = ..., ride = ..., crash = ...,
    tomL = ..., tomM = ..., tomH = ...,
    cb = ..., shkr = ..., perc = ..., fx1 = ..., fx2 = ...,
)
```

Each row is an `IntArray` whose length must equal the time signature's
`stepCount`; missing pads default to silence. About 55 built-in presets ship
with the app (the iOS port should re-encode the same patterns).

---

## 8. Tempo, BPM, tap tempo, lock

- **Range:** 40–240 BPM.
- **Set live:** drag the BPM number up/down (drag-Y → ΔBPM). The Android
  implementation uses `delta_BPM = -dy_px × 0.25` for a comfortable sensitivity.
- **Type exact:** tap the BPM number → numeric input dialog.
- **Tap tempo:** a small button with an LED that flashes on each beat; the
  user taps along; the average of the last few intervals becomes the BPM.
- **Tempo lock toggle:** when ON, loading a beat preset keeps the current BPM
  instead of snapping to the preset's tempo. Scenes always override (they
  carry tempo intentionally).

---

## 9. Master EQ

8 fixed-frequency **peaking** biquads in series; the user adjusts only gain.

```
bands  : 60, 170, 310, 600, 1k, 3k, 6k, 12k  Hz
gain   : ±12 dB per band
Q      : 1.41 (Butterworth)
filter : RBJ peaking EQ (see §26)
```

**Threading.** Coefficient updates from UI use **relaxed atomic stores**; the
audio thread does relaxed loads once per buffer (not per sample) → lock-free,
no per-sample atomic cost.

The master EQ is **global** — not saved per scene.

---

## 10. Multiband compressor

A 4-band compressor inspired by the **Waves C6**. Used as a global
post-EQ glue/punch tool. Not saved per scene.

### 10.1 Topology

3 Linkwitz-Riley crossovers split the signal into 4 bands; each band has its
own dynamic processor (peak detector → envelope follower with attack/release
→ gain reduction toward a `range` target); bands are summed; an output gain
is applied.

### 10.2 Per-band parameters

| Param | Range | Default |
|---|---|---|
| Threshold | −60 … 0 dB | −24 dB |
| Range | −30 … +15 dB (negative = compress, positive = expand) | −6 dB |
| Attack | 0.5 … 120 ms | 15 ms |
| Release | 10 … 1000 ms | 120 ms |
| Makeup | −12 … +12 dB | 0 dB |
| Solo | bool | off |
| Bypass | bool | off |

### 10.3 Master / crossovers

| Param | Range | Default |
|---|---|---|
| Output gain | −18 … +18 dB | 0 dB |
| Crossover 1 (low / lo-mid) | 40 … 500 Hz | 120 Hz |
| Crossover 2 (lo-mid / hi-mid) | 300 … 3000 Hz | 800 Hz |
| Crossover 3 (hi-mid / high) | 2000 … 12000 Hz | 5000 Hz |

Band names in UI: **LOW · LO-MID · HI-MID · HIGH**.

### 10.4 Gain-reduction meter

Each band exposes its current gain change in dB (negative = reducing) via a
non-blocking atomic. The UI polls at ~30 Hz to draw VU-style meters next to
each band.

### 10.5 Factory presets

Output gains in dB, frequencies in Hz, attack/release in ms.

#### PUNCH — *Slow attack, snap*
- Output **+1**, Xover **110 · 800 · 5000**
- LOW: T −22 R −5 A 30 Re 180 M +1
- LO-MID: T −22 R −4 A 35 Re 160 M +0.5
- HI-MID: T −20 R −3 A 25 Re 120 M 0
- HIGH: T −24 R −3 A 15 Re 90 M 0

#### GLUE — *Gentle cohesion*
- Output **+1**, Xover **120 · 750 · 5500**
- LOW: T −24 R −4 A 20 Re 200 M +1
- LO-MID: T −24 R −4 A 20 Re 200 M +1
- HI-MID: T −24 R −4 A 20 Re 200 M +0.5
- HIGH: T −26 R −3 A 15 Re 150 M 0

#### TIGHT LOW — *Tame boom*
- Output **+1.5**, Xover **90 · 600 · 5000**
- LOW: T −28 R −10 A 12 Re 140 M +2
- LO-MID: T −24 R −7 A 18 Re 130 M +1
- HI-MID: T −22 R −3 A 25 Re 110 M 0
- HIGH: T −26 R −2 A 15 Re 90 M 0

#### FAT BEAT — *Dense & loud*
- Output **+2**, Xover **120 · 850 · 6000**
- LOW: T −30 R −12 A 8 Re 120 M +3
- LO-MID: T −28 R −10 A 6 Re 110 M +2.5
- HI-MID: T −26 R −8 A 5 Re 90 M +2
- HIGH: T −28 R −6 A 8 Re 80 M +1.5

---

## 11. Audio looper

A **bar-synchronised audio looper**. Records audio from the device input —
the built-in microphone, a USB-C audio interface or external sound card —
and loops it locked to the sequencer's bar grid. The drum machine itself is
**never** captured.

### 11.1 State machine

7 states (the order matters — the ordinals are persisted in the engine ↔ UI
bridge):

| Ord | State        | Meaning |
|----:|--------------|---------|
| 0   | Empty        | No loop. |
| 1   | Armed        | Tapped REC; waiting for the next bar to start capture. |
| 2   | Recording    | Capturing input into the buffer. |
| 3   | EndArmed     | Tapped END; waiting for the next bar to finalise. |
| 4   | Playing      | Loop is playing through the output bus. |
| 5   | Stopped      | Loop exists but is muted. |
| 6   | PlayArmed    | Cued resume — waiting for the next bar to play from position 0. |

### 11.2 Actions

Two distinct actions — both are also assignable to a hardware key (§16):

**TAP / REC (`looperTap`)** — the rec/play cycle:
- Empty → Armed
- Armed → Empty (cancel)
- Recording → EndArmed (will land in Playing)
- EndArmed → Recording (cancel the end)
- Playing → Stopped (on-screen toggle)
- Stopped → **PlayArmed** (cue resume from 0 on the next downbeat)
- PlayArmed → Stopped (cancel cue)

**STOP (`looperStop`)** — a dedicated stop:
- Playing → Stopped
- PlayArmed → Stopped
- Recording → EndArmed with **endIntoStopped = true** → finalises into
  **Stopped** (the recorded loop is kept but is not played)
- EndArmed → flip endIntoStopped = true
- otherwise no-op

**CLEAR (long-press on the on-screen looper button)** — discards the loop;
goes to Empty. The native input stream remains open.

### 11.3 Quantised recording

- ARM → on next `onBar` → state = Recording, `recordLen = 0`,
  `barOffsets = [0]`.
- Every `onBar` while Recording → push the current `recordLen` into
  `barOffsets` (this records where the next bar starts inside the buffer).
- END → on next `onBar` → finalise:
  - `loopBars = barOffsets.size`
  - `loopFrames = recordLen` (the actual captured length — not an average)
  - state = `endIntoStopped ? Stopped : Playing`
- The input audio callback writes into `buffer[recordLen…]` while
  `state ∈ {Recording, EndArmed}`. (EndArmed continues to record so the loop's
  final partial bar is captured up to the next bar boundary.)

### 11.4 Bar-accurate playback sync (multi-bar correctness)

The naïve approach — snap playback to multiples of the **average** bar length
— drifts for multi-bar loops, because real recorded bars aren't equally
spaced (ticker jitter, callback granularity). The implementation **snaps to
the real recorded bar offsets**:

On each `onBar` during Playing:
```
barsSincePlay += 1
b = barsSincePlay mod loopBars
snapTarget = barOffsets[b]        // published as atomic
```
The output callback, at the start of its mix, reads and clears `snapTarget`;
if non-negative, it sets `playPos = snapTarget`. Between snaps, playback
advances `playPos` by `numFrames` per callback and wraps at `loopFrames`.

This makes every loop-bar align with the sequencer's downbeat, regardless of
the loop's bar count or the recording timing jitter.

### 11.5 Latency compensation

The user reacts to sound they **hear**, which is delayed by the **output**
latency. Their playing then arrives delayed by the **input** latency. So the
recorded content sits a full **round-trip** late inside the buffer.

Compensation:
```
latencyComp = inputLatencyFrames + outputLatencyFrames
read_pos    = (playPos + latencyComp) mod loopFrames
```

`inputLatency` comes from `inputStream.calculateLatencyMillis()` (Oboe);
`outputLatency` from `outputStream.calculateLatencyMillis()`. Computed at
**finalise time** when both readings are stable. Clamped to `[0, sampleRate/2]`.

iOS equivalent: `AVAudioSession.outputLatency` and `inputLatency` give the
round-trip in seconds; multiply by sample rate.

### 11.6 Resume snapped to "beat 1"

Tapping REC on a Stopped loop sets state to **PlayArmed**, not Playing
directly. The next `onBar` sets `playPos = 0`, `barsSincePlay = 0`,
state = Playing. So a resumed loop always starts from its beginning, aligned
to the sequencer's downbeat.

### 11.7 Input gain & meter

- **Input gain** (dB, −24 … +12): applied in the input callback as
  `buffer[pos] = in[ch0] × gain` — baked into the recording (acts as a record
  trim).
- **Input peak** (atomic, linear 0…~1): tracked in every input callback,
  post-gain. The LOOPER pane polls and resets it ~20 Hz to drive a meter.

### 11.8 Output gain & EQ

- **Output gain** (dB, −24 … +12): applied during `mixInto` after the EQ.
- **Parametric EQ** (`ParametricEq`, 6 bands — see §12): the loop's mono
  samples are pulled into a scratch buffer, EQ-processed mono, then mixed into
  the stereo output (`out[f, c] += scratch[f] × outputGain`).

### 11.9 "Stop with sequencer" toggle

A toggle in the LOOPER pane. When ON: each time the sequencer transitions
from playing → stopped, the engine calls `looperStop()` automatically. Default:
OFF (the loop is independent of the transport).

### 11.10 Buffer model

- Pre-allocated mono `vector<float>` sized to **60 s × sampleRate** the first
  time it is needed (either by `startInput` or `importLoop`). **Never
  reallocated** afterwards — so the audio thread can read it lock-free.
- This caps the maximum loop length at 60 s. Loop content is stored without
  any latency offset baked in (the offset is applied on read, see §11.5).

### 11.11 Input stream open / permission

The input stream is opened **lazily**, the first time the user taps the
looper button from the Empty state. `handleLooperTap` only requests the
microphone permission when state == Empty (i.e. arming a fresh recording).
For Stopped / PlayArmed / Playing states (a loop already exists, including
one imported from a scene), the looper button just calls `looperTap` —
**no permission prompt needed for playback** of an imported loop.

### 11.12 Threading summary

| Thread | Touches |
|---|---|
| Input audio callback | `buffer_` (writes when Recording/EndArmed), `recordLen_`, `inputPeak_` |
| Output audio callback | `buffer_` (reads when Playing), `playPos_`, `snapTarget_` (exchange), `loopEq_`, `outputGain_` |
| Sequencer ticker | `onBar()` — state transitions, push to `barOffsets_`, publish `snapTarget_` |
| UI thread | `tap()`, `stopLoop()`, `clear()`, EQ/level setters, `importLoop()`, `exportPcm()` |

Recording and Playing are **mutually exclusive states**, so the two audio
threads never touch `buffer_` simultaneously. The state atomic (with
acquire/release ordering) is the synchronization fence. The ticker- and UI-
thread state-machine transitions are serialised by a small `std::mutex`
(`transitionMutex_`); the audio callbacks are never blocked by it.

---

## 12. LOOPER pane (input/output, EQ)

A dedicated pane (tab) on the main screen. Layout top-to-bottom:

1. **Header label** — small monospace `"LOOPER · LEVELS & EQ"`.
2. **Levels row** — two compact horizontal faders:
   - **INPUT** — label + dB readout, then a thin **peak meter** bar (4 dp tall,
     fills 0…100 %, turns red at >95 %), then a draggable track. Double-tap
     resets to 0 dB.
   - **OUTPUT** — same layout, no meter.
3. **Interactive EQ curve** (the centerpiece) — see §12.1 below; flexes to
   fill remaining vertical space.
4. **Selected-band strip** — when a band is selected:
   - Read-out line: `BAND N · {freq} · {±gainDb}` (gain hidden for cut shapes).
   - **REMOVE** button (right-aligned, red).
   - Row of 5 shape chips: **BELL · LO SHELF · HI SHELF · LO CUT · HI CUT**
     (selected chip highlights with accent).
   - **Q** slider with numeric readout (range 0.3 … 10, default 1.0).
   - If no band selected: a hint line `"Double-tap the graph to add an EQ band."`
5. **Controls section**:
   - **Toggle** — `STOP WITH SEQUENCER` (a 38×20 pill-style switch).
   - **REC KEY** row — label + bound-key name (or `—`) + LEARN/RELEARN pill +
     ✕ (unbind) when bound.
   - **STOP KEY** row — same layout.

### 12.1 The interactive EQ curve

A FabFilter-Pro-Q-3-style draggable response graph.

**Geometry:**
- X axis: logarithmic frequency, **20 Hz – 20 kHz**.
- Y axis: gain, **±15 dB** centred on the box.
- Grid: vertical lines at 50, 100, 500, 1k, 5k, 10k Hz (faint white α 0.06);
  horizontal lines at ±EQ_GAIN_MAX/2 (faint), and a slightly brighter line
  at 0 dB (white α 0.14).

**Math:**
```
xForFreq(f) = w × log10(f / 20) / 3            // 20→0  20000→w
freqForX(x) = 20 × 10^(3 × x / w)
yForGain(g) = h/2 − (g / 15) × (h/2)
gainForY(y) = (h/2 − y) / (h/2) × 15
```

**Curve drawing.** Sample ~140 x-positions; at each:
```
db = Σ (band[i] enabled) magnitudeDb(band[i], freq)
```
where `magnitudeDb` computes the band's RBJ biquad magnitude response at
that frequency (see §26.1). Clamp to ±15 dB, build a `Path`, stroke 2 dp
in the accent colour.

**Band nodes.** Each enabled band is drawn as a circle at
`(xForFreq(b.freq), yForGain(b.gain))` (for cut shapes the y is fixed at
0 dB). Selected band uses a brighter accent and 2.5 dp stroke; others 1.5 dp.
A dark background disc behind the ring so the node reads against the curve.

**Gestures:**
| Gesture | Behaviour |
|---|---|
| **Drag** a node | Update frequency from X and gain from Y (gain ignored for cut shapes). |
| **Tap** a node | Select it. |
| **Tap** empty | Deselect. |
| **Double-tap** empty | Add a new band at that point (`Bell`, Q = 1). If all 6 slots are used → no-op. |
| **Double-tap** a node | Remove (disable) that band. |

**Touch hit-test radius**: 44 dp.

**Band defaults**: Bell shape, Q 1.0, freq picked from the tap point, gain
picked from the tap point.

---

## 13. Scenes & setlists

### 13.1 Concept

A **scene** is a full performance snapshot:

- Tempo, time signature, humanize toggle.
- Both sequencer sections (A and B), 16 pads × `stepCount` velocities each.
- Per-pad mix volumes.
- Which pads have a sample (and the WAV bytes are stored alongside).
- The complete LOOPER section settings (input/output gains, follow-stop,
  6 EQ bands).
- *Optionally* the recorded loop audio (raw float32 PCM) + its metadata
  (bar offsets, latency compensation).

A **setlist** is an ordered group of scenes.

### 13.2 On-disk layout

```
<app files dir>/setlists/
└── <SetlistName>/
    ├── order.json                — explicit scene ordering for live use
    └── <SceneName>/
        ├── scene.json            — all parameters (incl. LOOPER block)
        ├── pad_00.wav            — sample for pad 0 (only if assigned)
        ├── pad_01.wav
        ├── …
        └── looper.pcm            — raw mono float32 LE (only if user opted in)
```

`SetlistName` and `SceneName` are sanitised (`[\\\\/:*?"<>|]` → `_`, trimmed
to 48 chars). Saving a scene with the same name **overwrites** (the scene
folder is recursively deleted first, then rewritten).

### 13.3 `scene.json` schema

```json
{
  "name": "MY GROOVE",
  "bpm": 124.0,
  "humanize": false,
  "timeSignature": "7/8",
  "drumsMatrix":  [[127, 0, …], [0, 110, …], …],   // 16 rows × stepCount
  "drumsMatrixB": [[127, 0, …], …],
  "padVolumes":   [1.0, 0.8, …],                   // 16 floats, 0..1
  "padHasSample": [true, true, false, …],          // 16 booleans
  "looper": {
    "inputGainDb": 0.0,
    "outputGainDb": 0.0,
    "followStop": false,
    "hasLoop": true,
    "latencyComp": 1234,
    "barOffsets": [0, 96000, 192000],              // frames
    "eqBands": [
      {"shape": 0, "freqHz": 1000.0, "gainDb": 0.0, "q": 1.0, "enabled": false},
      …6 entries…
    ]
  }
}
```

Backward compatibility: older scenes have no `drumsMatrixB` (derived from A
via `PatternVariation`), no `timeSignature` (default `4/4`), no `looper` block
(LOOPER defaults to flat settings, no loop).

### 13.4 `looper.pcm` format

- Raw **float32 little-endian** mono PCM, no header.
- Length = `loopFrames × 4` bytes.
- Sample rate: the device's output rate at save time (usually 48 000).

### 13.5 Saving a scene

1. The user opens the Scene Library and confirms a name (via
   `SaveSceneAsDialog`).
2. If a loop currently exists in the engine (state ∈ {Playing, Stopped,
   PlayArmed}) → show the **"SAVE LOOP" dialog** (SKIP / INCLUDE).
3. Call `saveCurrentScene(setlist, name, includeLoop)`:
   - Build the `Scene` with LOOPER settings (always) + barOffsets / latency
     (only if includeLoop).
   - On `Dispatchers.IO`: optionally export the PCM (`engine.looperExportPcm()`
     — a `FloatArray`), then `SceneStore.saveScene(…, looperPcm)`.

### 13.6 Loading a scene

1. Read `scene.json`.
2. Restore tempo, humanize, time signature.
3. Resize both pattern matrices to the time signature's `stepCount`.
4. Load every pad WAV → engine sample id → bind to pad. Push round-robin
   variants.
5. Restore LOOPER settings via `looperEq.restore(…)` — sets in/out gains,
   followStop, all 6 EQ bands, pushes each to the engine.
6. If `looperHasLoop`: read `looper.pcm` (on IO), then
   `engine.looperImportLoop(pcm, barOffsets, latencyComp)`. State becomes
   **Stopped**. If `!looperHasLoop`: `engine.looperClear()`. (A scene is a
   full snapshot — switching to a scene without a loop clears any live loop.)

### 13.7 Search

The Scene Library dialog has a search field. Filter logic (case-insensitive
substring):

- A **setlist** is shown if its name matches OR it has ≥1 matching scene.
- For a shown setlist: if its own name matches → show all its scenes; else →
  only the matching scenes.
- During search all shown setlists are **auto-expanded** so results are
  immediately visible. The "paste zone" item at the bottom of the list is
  hidden while a query is active.

---

## 14. Saved-loops manager

Reachable from **Settings → SAVED LOOPS → VIEW & MANAGE**. A standalone
dialog that lists every `looper.pcm` across all setlists.

For each loop, one row shows:
- **Scene name** (bold, monospace, 12 sp).
- `setlist  ·  Xs · X.X MB` (dim, monospace, 9 sp).
  - Duration = `bytes / 4 / 48000` (seconds, assuming 48 kHz).
  - Size formatted as `B` / `KB` / `MB`.
- A **DELETE** pill — first tap turns the pill solid red with label
  `CONFIRM`; the second tap actually deletes. Pressing DELETE on another row
  cancels the first row's arm (only one row armed at a time).

Header shows `N loops · X.X MB` total.

**Deleting** (`SceneStore.deleteLoop`):
1. Delete the `looper.pcm` file.
2. Read the scene's `scene.json`, flip its `looper.hasLoop = false`, write
   back. The rest of the scene is untouched.

The list refreshes after every delete (re-listing the loops on IO).

---

## 15. Beat-library dialog & user presets

A dialog browsing built-in and user-saved beat presets.

- **Top row** — filter chips: ALL · JAZZ · POP · HIPHOP · R&B · LATIN ·
  BOSSA · SWING · 6/8 · COMPOUND · WALTZ · UNEVEN · MARCH. `FlowRow` wraps
  them across multiple lines.
- **List** — for each preset: name (bold) + `style · bpm · time signature`
  (dim). Tap → load the preset (bpm + drumsMatrix; if tempo-lock is ON, only
  the matrix is loaded). User presets show a delete affordance.
- **SAVE PRESET** at the top — pops a small naming dialog, snapshots the
  current sequencer + bpm into a `BeatPreset`, persisted via
  `UserPresetStore`.

---

## 16. Hardware key control

### 16.1 Concept

The app supports a **Bluetooth page-turner pedal** (or any HID keyboard) for
hands-free transport during live performance.

### 16.2 Bindable actions

```
TransportAction:
  Play, Stop, NextScene, PreviousScene, SectionToggle,
  Fill1, Fill2, TempoStepUp, TempoStepDown,
  LooperRecord, LooperStop                   ← new looper actions
```

Each action has a display name (`"PLAY"`, `"LOOPER REC"`, …) used in the
learn UI.

### 16.3 Learn flow (Android pattern; mirror on iOS)

- The user **long-presses** a transport button (Play, Stop, ‹, ›, B, Fill 1,
  Fill 2) → a **context menu** opens listing the bound key (if any) and
  offering **LEARN / RELEARN BT KEY**, **UNBIND**, **CANCEL**.
- Choosing LEARN sets `learningAction = action` → a full-screen overlay
  appears: `"LEARN BT KEY for {action.displayName}"` with a live diagnostic
  line showing the last detected keycode (so the user can see whether their
  device's events are arriving at all).
- The next physical key press is captured: any existing binding for that key
  is removed, and a new mapping `action → keyCode` is stored. The overlay
  dismisses.
- For the **looper** actions (REC KEY, STOP KEY): the learn rows live
  inside the **LOOPER pane** (see §12), not in a long-press menu, because the
  looper button on screen has a different long-press meaning (clear).

The tempo step actions (TempoStepUp / Down) have learn rows in **Settings**
(plus a step-size spinner each: 1–50 BPM).

### 16.4 Persistence

```
SharedPreferences "transport_keys"
    key_Play          → keyCode (Int)
    key_Stop          → …
    …
    key_LooperRecord  → keyCode
    key_LooperStop    → keyCode
```

On iOS: use `UserDefaults` with the same keys.

### 16.5 Key dispatch

A single `TransportKeyController` filters keys (ignores SHIFT/CTRL/ALT/META/
HOME/BACK/APP_SWITCH/POWER/MENU/UNKNOWN), captures keydown for learning, and
on a bound key fires the controller's `onAction(action)` callback.

The screen registers `keyController.onAction = { action -> fireTransportAction(action) }`
inside a `DisposableEffect(keyController)` so the callback always sees the
latest state via remembered delegates.

For `LooperRecord`, the callback indirects through a **remembered holder**
(an `arrayOfNulls<() -> Unit>(1)`) because `fireTransportAction` is declared
*before* `handleLooperTap` lexically; the holder is set right after
`handleLooperTap` is defined.

### 16.6 Background dispatch (Android only)

On Android, an **AccessibilityService** with
`flagRequestFilterKeyEvents` captures keys system-wide so the bindings keep
working while the app is in the background. The accessibility service routes
events to the same `TransportKeyController.handleKeyEvent`, and stays out of
the way while the activity has window focus (to avoid firing actions twice).

**On iOS this is structurally not possible**: iOS does not let third-party
apps receive arbitrary key events in the background. The best the iOS port
can do is:
- Foreground: use `UIKeyCommand` on the responder chain (or
  `pressesBegan`/`pressesEnded`) to receive HID keys.
- Background: silently lose key control (the audio keeps playing under the
  background-audio capability, but the keyboard cannot reach the app).

Document this difference in the iOS port's onboarding text.

### 16.7 Human-friendly key names

Used in the learn UI for the bound-key label. Map common keys to friendly
names:

```
VOLUME UP/DOWN, PAGE UP/DOWN, ARROW UP/DOWN/LEFT/RIGHT,
OK (DPAD_CENTER), ENTER, NUMPAD ENTER, SPACE,
MEDIA PLAY/PAUSE, MEDIA PLAY, MEDIA NEXT, MEDIA PREV
```

Fallback: the platform's keycode name with prefix stripped.

---

## 17. Onboarding (interactive tour)

### 17.1 Mechanism

A semi-transparent scrim with a **rounded-rect spotlight cutout** around the
current step's target UI element, plus a **callout card** placed on the
opposite half of the screen with title + body + step counter + BACK / SKIP /
NEXT pills.

When a step has no target (welcome / closing), a centered card on plain
dark scrim is shown instead.

### 17.2 Target registry

A `TourTargetRegistry` (essentially a `Dictionary<String, Rect>`) is provided
via a context-local. Any UI element calls `Modifier.tourTarget("id")` to
publish its bounds-in-root via an `onGloballyPositioned` hook.

iOS equivalent: a `@Environment` `TourRegistry` (an `ObservableObject`); each
target view uses a `GeometryReader` + `.onAppear/.onChange(of: geometry)` to
register its frame in window coordinates.

### 17.3 Tour targets

```
brand · scene_library_icon · bpm_display · time_signature · play_button ·
looper_button · scene_nav · sequencer_step · drum_pad · section_b ·
fill_button · mode_switcher
```

### 17.4 Tour steps (in order)

| # | Target | Title | Body |
|--:|--------|-------|------|
| 0 | (none) | WELCOME | Interactive tour of the gestures that aren't obvious. Walk through with NEXT — re-open any time from Settings. |
| 1 | brand | SETTINGS LIVE HERE | Tap the SLAVCHEV MACHINE wordmark to open Settings — accent colour, Bluetooth bindings, and this tour. |
| 2 | scene_library_icon | SCENE LIBRARY | Save full snapshots (sequencer + samples + mix) as scenes, organise them into setlists for live performance. |
| 3 | bpm_display | TEMPO | Drag up/down directly on the BPM number to change tempo live — the playhead doesn't drop a beat. Tap to type a precise value. LOCK keeps the tempo when you load a beat preset. |
| 4 | time_signature | TIME SIGNATURE | Tap the TIME chip to switch the sequencer between 4/4, 3/4, 6/8, 7/8, 11/16 and more. The step count and the beat grouping adapt instantly. |
| 5 | play_button | PLAY — AND LONG-PRESS | Tap to start/stop. Long-press to bind a Bluetooth page-turner button. Same long-press trick works on Stop, ‹ ›, B, and Fill 1 / 2. |
| 6 | looper_button | AUDIO LOOPER | Records audio from the mic, a USB-C interface or sound card and loops it locked to the bars. Tap to record, tap to finish, tap to play/stop. Long-press to clear. Set its levels and EQ in the LOOPER tab. |
| 7 | scene_nav | SCENE NAVIGATION | Use the ‹ › arrows to jump between scenes in the current setlist. Tap the label between them to jump straight into the Scene Library. |
| 8 | sequencer_step | STEP SEQUENCER | Tap a step to toggle on/off. Drag up/down on a step to fine-tune velocity (taller fill = louder). |
| 9 | drum_pad | DRUM PADS | Tap to trigger. The vertical position of your finger sets velocity — top = soft, bottom = loud. Long-press to pick a different .wav. |
| 10 | section_b | A / B VARIATION | Flip the sequencer between A and B sections. B starts as a smart variation of A — busier patterns get lighter Bs, sparse ones get more energetic Bs. |
| 11 | fill_button | FILLS | Trigger a delicate fill that lands on the next downbeat. Snare-led (Fill 1) and tom-led (Fill 2). A crash punctuates the new bar. |
| 12 | mode_switcher | PADS / LOOPER / MIX / EQ | Switches the bottom panel: the pad grid, the looper's levels & interactive EQ, per-pad volume faders, or the 8-band master EQ. Looper, Mix and EQ are global mix tools — they don't change when you load a scene. |
| 13 | (none) | YOU'RE READY | Re-open this tour any time from Settings (tap the wordmark). Have fun. |

### 17.5 Persistence

A single boolean `onboarding_seen` in the settings prefs file. The first
launch shows the tour automatically; Settings → "SHOW TOUR AGAIN" resets and
re-shows it.

---

## 18. Settings

A `Dialog` with the following stacked sections:

1. **APPEARANCE** — a row of three accent swatches (Cyan / Green / Fuchsia);
   tapping selects.
2. **BLUETOOTH** — diagnostic count (`X keys bound`) and a **RESET** button.
3. **BACKGROUND CONTROL** — instructions + a button that opens the
   Accessibility Settings screen (Android-only — see §16.6). On iOS, this
   section can be replaced with a note explaining the foreground-only
   limitation of HID input.
4. **TEMPO STEP** — two rows: STEP UP and STEP DOWN. Each row has:
   - A numeric input field (1–50, default 5).
   - The currently bound key (or `—`).
   - LEARN / UNBIND pills.
5. **TUTORIAL** — `SHOW TOUR AGAIN` button.
6. **SAVED LOOPS** — `VIEW & MANAGE` button (opens §14).
7. **ABOUT** — version, credits, the project link.

Persisted keys (SharedPreferences `slavchev_settings`):
- `accent: String` ("Cyan" / "Green" / "Fuchsia") — default Cyan.
- `tempo_step_up: Int` — default 5.
- `tempo_step_down: Int` — default 5.
- `onboarding_seen: Bool` — default false.

---

## 19. UI / UX design language

### 19.1 Palette — `Chassis`

```
Top         #16191E   — dialog & panel background (top of vertical gradient)
Mid         #0C0D10
Bot         #08090B
Body        #0A0B0D
PadIdleA    #20242B   — pad gradient top (idle)
PadIdleB    #14171C   — pad gradient bottom (idle)
PadPressedA #14161A
PadPressedB #1A1D22
OledA       #07090C   — OLED gradient top
OledB       #0B1116
OledC       #060A0E   — OLED gradient bottom
IconBtnA    #20242B   — icon button gradient top
IconBtnB    #141619   — icon button gradient bottom
RecRed      #FF4060   — recording indicator + danger buttons
PlayGreen   #22FFA0   — playback indicator
```

### 19.2 Accent — three options

Each accent is one base hex with four alpha variants:

```
Cyan    base = #22E6FF     dim α=0x2E (~18%)
                            soft α=0x8C (~55%)
                            hex α=0xFF
                            bright α=0xF2 (~95%)

Green   base = #22FFA0
Fuchsia base = #FF44C8
```

`accent.tokens.hex` is the body colour used for most highlighted text and
fills; `bright` is for the brightest UI hairlines (curve strokes, selected
ring); `dim` for hairline borders and gentle backgrounds; `soft` is reserved
for backgrounds where a stronger tint is needed.

### 19.3 Typography

The entire interface uses **system Monospace** for technical text and
**system SansSerif** for headings / buttons. (On iOS: SF Mono / SF Pro — set
via `.system(.body, design: .monospaced)` / `.default`.)

Common sizes / weights (sp ≈ scaled points; use the same pt values on iOS):

| Use | Size | Family | Weight | Letter spacing |
|---|---:|---|---|---:|
| BPM number | 32 | Monospace | Bold | −1 |
| Section header (e.g. "MASTER EQ · 8 BAND") | 12 | SansSerif | Bold | 0.5 |
| Pad label / sequencer label | 9 | Monospace | SemiBold | 2 |
| Kit / section indicator | 9 | Monospace | SemiBold | 2 |
| Sequencer step label | 11 | SansSerif | Bold | 3 |
| Transport / chip labels | 10 | SansSerif/Mono | Bold | 1–2 |
| Compressor band name | 11 | Monospace | SemiBold | 3 |
| Dialog title | 12 | SansSerif | Bold | 0.5 |
| Small button | 8 | Monospace | Bold | 0.5–1 |
| OLED PLAY/STOP / TIME chip text | 10–13 | Monospace | Bold | 1–2 |

### 19.4 Spacing system

- Outer screen padding: **16 dp horizontal / 16 dp top / 20 dp bottom** above
  the status bar.
- Major vertical gap between top-level rows: **14 dp**.
- Inner row gaps: 6–10 dp.
- Dialog padding: 18–20 dp.
- Corner radii: 14–16 dp (panels), 6–8 dp (chips/buttons), 99 dp (pills).
- Borders: 1 dp hairline at `Color.White.copy(alpha 0.06–0.18)` or tinted
  with the accent.

### 19.5 Animations

- **Tap-tempo LED**: fades from `α 1.0` to `α 0.18` over `intervalMs / 4` ms,
  then holds; restarts every beat. The animation is keyed on bpm so the LED
  also flashes on user taps.
- **Recording dot**: blinks at 2 Hz (`α 1.0` ↔ `α 0.35`, 500 ms each).
- **Looper button "waiting" states (Armed, EndArmed, PlayArmed)**: pulse
  every 280 ms by halving the colour alpha.
- **Coach-mark cutout**: snaps to the next target (no morph animation), but
  uses Compose's `BlendMode.Clear` to punch a transparent rounded-rect hole
  in the scrim — replicate on iOS with `CAShapeLayer` mask or
  `compositingGroup() + .blendMode(.destinationOut)`.

### 19.6 Visual primitives

- **Pad button**: rounded-rect 16 dp corners, vertical gradient PadIdleA →
  PadIdleB, accent border when active, glow when hit. A small velocity bar
  (accent gradient) grows from the bottom while a finger is down at that Y.
- **OLED panel**: rounded-rect 14 dp corners, vertical gradient OledA → OledB
  → OledC, faint horizontal scanline overlay (3 px repeating gradient at
  α 0.03), interior content in accent hex with monospace.
- **Pill button**: 99 dp corners, white α 0.06 background, 1 dp accent
  border, monospace label.
- **Chip (toggle/segment)**: 6 dp corners, accent-tinted background when
  selected, faint white border when not.

---

## 20. Main-screen layout

Portrait, top-to-bottom. The numbers in the diagram are typical pt heights;
the actual layout uses a `Column` with `Arrangement.spacedBy(14.dp)` between
the major rows and `Modifier.weight(1f)` on the pane area so it absorbs
extra height.

```
┌─────────────────────────────────────────────────────────────────────┐
│  BrandAndUtilityRow                            (≈ 40 pt)           │ ← logo + scenes icon + settings + accent swatch
├─────────────────────────────────────────────────────────────────────┤
│  ◀  SCENE NAME · SETLIST  ▶                    (≈ 36 pt)           │ ← SceneNavRow  (tour: SCENE_NAV)
├─────────────────────────────────────────────────────────────────────┤
│  TrackTabRow                                   (≈ 44 pt)           │ ← KIT button · A/B (SECTION_B) · FILL 1 (FILL_BUTTON) · FILL 2
├─────────────────────────────────────────────────────────────────────┤
│  SequencerHeader (label + humanize toggle)     (≈ 14 pt)           │
│  SequencerRow — 16 step toggles                (≈ 40 pt) (SEQUENCER_STEP)
├─────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────── pane ────────────────────┐                   │
│  │  (PADS | LOOPER | MIX | EQ)                 │  weight 1 — flex  │
│  └─────────────────────────────────────────────┘                   │
├─────────────────────────────────────────────────────────────────────┤
│  ModeSwitcherRow — [PADS][LOOPER][MIX][EQ]     (≈ 28 pt) (MODE_SWITCHER)
├─────────────────────────────────────────────────────────────────────┤
│  OledAndTransportRow                           (≈ 92 pt)           │
│    OLED display (weight 1f) + transport column │
│    OLED rows:                                                       │
│      row 1: [BPM 32sp] ............ [LOCK]                         │
│              ........................ [TAP]                         │
│      row 2: [▶ PLAY / ■ STOP]  ....... [TIME 4/4]                  │
│    transport column (right):                                        │
│      [LOOP] [REC] [STOP]   ← 39 pt each                            │
│           [   PLAY   ]     ← 47 pt (PLAY_BUTTON)                    │
└─────────────────────────────────────────────────────────────────────┘
```

The chassis background is a radial gradient (Top → Mid → Bot) with a soft
accent glow at the top-right corner (320-pt circle at α 0.08).

### 20.1 OLED display detail

Two rows, content vertically distributed (`Column(spaceBetween)`):

- **Row 1**:
  - Left: `BPM number` (32 sp Monospace Bold accent.hex) + small `"BPM"` label
    (10 sp). Two stacked pointer-inputs: vertical drag for ±BPM, tap for
    numeric input.
  - Right: a fixed-width 66 pt column with two stacked chips:
    - **LOCK** chip (top) — small `□`/`■` glyph + `LOCK` text; styles
      change when locked. Both chips `fillMaxWidth()` so they end with the
      same right and left edges.
    - **TAP** chip (bottom) — accent LED + `TAP` text; the LED flashes once
      per beat.
- **Row 2**:
  - Left: a small `▶ PLAY` / `■ STOP` status (10 sp). If recording, a
    blinking red dot precedes it.
  - Right: the **TIME** chip — `TIME` label + the time-signature string
    (`4/4`, `7/8`, …). Tap to open the picker.

### 20.2 Looper transport button

The on-screen looper button is a circular 39 pt button placed at the start of
the [REC, STOP] sub-row, so the row becomes **LOOP · REC · STOP** with **PLAY**
below. The button shows the looper state with colour + label:

| State | Label | Colour | Style |
|---|---|---|---|
| Empty | LOOP | white α 0.5 | dim |
| Armed | ARM | accent | pulsing |
| Recording | REC | red | solid, thicker border |
| EndArmed | END | red | pulsing, thicker border |
| Playing | LOOP | accent | solid, thicker border |
| Stopped | STOP | white α 0.5 | dim |
| PlayArmed | CUE | accent | pulsing |

Long-press = clear (engine.looperClear) regardless of state.

---

## 21. Pane layouts

### 21.1 PADS — `PadGrid4x4`

A 4×4 grid of pad buttons. Each pad shows its label (top), a sample-loaded
glow (when assigned), a velocity bar that grows from the bottom while a
finger is down, and a tap flash. Long-press opens a multi-select file picker
(up to 3 files = round-robin variants). Tour spotlights the KICK pad (index 0).

### 21.2 MIX — `PadMixPane`

Header `PAD MIX · 16 CH` + RESET button. 16 vertical faders in a 4×4 grid.
Drag a fader up/down to set 0–100 %; double-tap resets to 100 %. Each fader
shows the percentage at the bottom and the pad name at the top.

### 21.3 EQ — `MasterEqPane`

Header `MASTER EQ · 8 BAND` + FLAT button + a `Compressor` strip at the
bottom (with an enable toggle and a gear icon → opens the compressor dialog,
plus per-band tiny GR meters polled at ~30 Hz).

8 vertical faders, equal width (`weight(1f)`). Each fader shows the band's
frequency (top), a vertical bar with a fill that grows up from the centre
(positive gain) or down (negative gain), and the dB value (bottom). Drag = set
gain; double-tap resets to 0 dB. Range ±12 dB.

### 21.4 LOOPER — `LooperPane`

See §12.

---

## 22. Dialog patterns

All dialogs share a common look:

```
Column
  .clip RoundedCornerShape(16)
  .background Chassis.Top
  .border 1 dp accent.dim
  .padding 18–20

  Title  (small caps, accent or white, 11–12 sp, letterSpacing 2–3)
  short body / form / list
  Spacer
  Row(SpaceBetween end) {
      Pill("CANCEL"  …, primary = false)
      Pill("CONFIRM" …, primary = true)
  }
```

Notable dialogs:

- **NameInputDialog** — a labelled text field for naming a setlist / scene.
- **SaveSceneAsDialog** — two panels (setlist picker + scene name).
- **ConfirmDialog** — destructive confirm with a two-step *ARM → DELETE*
  pattern (the first DELETE tap only arms the second; protects against
  accidents).
- **IncludeLoopDialog** — yes/no for saving the loop with the scene
  ("SAVE LOOP — This scene has a recorded loop. Save the loop audio with
  it? [SKIP] [INCLUDE]").
- **TimeSignaturePickerDialog** — a chip grid (the 16 COMMON signatures)
  plus +/- steppers for the numerator and denominator + a step-count /
  groups readout.
- **MultibandCompressorDialog** — the parameter window with 4 band columns
  (threshold, range, attack, release, makeup) + master output + crossovers +
  preset chips + per-band GR meter (~30 Hz polling).
- **BeatLibraryDialog** — category filter chips + preset list.
- **SceneLibraryDialog** — header + new-setlist / save / save-as pills +
  search field + scrollable list of setlists with expandable scenes;
  drag-to-reorder scenes; long-press context menu (copy/paste); confirm
  dialog for destructive actions.
- **SettingsDialog** — see §18.
- **SavedLoopsDialog** — see §14.
- **TransportLearnOverlay** — a full-screen scrim with a centered card
  ("LEARN BT KEY for {action.displayName}") and a diagnostic detection box.

---

## 23. Gesture reference

| Gesture | Location | Behaviour |
|---|---|---|
| Drag ↕ | BPM number | Change BPM live (~−0.25 BPM/px). |
| Tap | BPM number | Numeric BPM input. |
| Tap | TIME chip | Open time-signature picker. |
| Tap | TAP chip | Tap-tempo. |
| Tap | LOCK chip | Toggle tempo lock. |
| Tap | step | Toggle step on/off. |
| Drag ↕ | step | Set step velocity (taller = louder). |
| Tap | pad | Trigger (velocity by finger Y). |
| Long-press | pad | Open file picker (multi-select up to 3 for round-robin). |
| Long-press | PLAY / STOP / ‹ / › / B / FILL 1 / FILL 2 | Open the transport context menu (LEARN BT KEY / UNBIND / CANCEL). |
| Tap | LOOPER button | Advance looper state (REC cycle / play / stop / cue). |
| Long-press | LOOPER button | Clear loop. |
| Double-tap | LOOPER-tab EQ graph (empty) | Add an EQ band there. |
| Tap | LOOPER-tab EQ graph (node) | Select that band. |
| Drag | LOOPER-tab EQ node | Move freq + gain (gain ignored for Cuts). |
| Double-tap | LOOPER-tab EQ node | Remove that band. |
| Tap | mode switcher pill | Switch between PADS / LOOPER / MIX / EQ. |
| Tap | wordmark "SLAVCHEV MACHINE" | Open Settings. |

---

## 24. Permissions & background

### 24.1 Permissions

| Android | Reason | iOS equivalent |
|---|---|---|
| `RECORD_AUDIO` (runtime) | Looper input | `NSMicrophoneUsageDescription` + `AVAudioSession.requestRecordPermission` |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | Foreground service for audio | `audio` UIBackgroundMode in `Info.plist` |
| `POST_NOTIFICATIONS` (API 33+) | Foreground service notification | (not needed on iOS) |
| `WAKE_LOCK` | Keep CPU running | (handled by `playAndRecord` audio session) |

The microphone permission is requested **lazily** — only when the user first
arms a recording from the Empty state. If a scene with a saved loop is
loaded, the loop plays without any permission prompt (the input stream isn't
needed for playback).

### 24.2 Background audio

Android uses an `AudioPlaybackService` (`foregroundServiceType =
mediaPlayback`) that holds a persistent notification with scene + play state.
On iOS:

- Add `audio` to `UIBackgroundModes`.
- Configure `AVAudioSession`:
  - For pure playback: `.playback`, options `.mixWithOthers` off.
  - For playback **with** looper recording: `.playAndRecord`,
    options `[.defaultToSpeaker, .allowBluetoothA2DP]`,
    mode `.measurement` for the lowest latency.
- Optionally implement Now Playing info / `MPRemoteCommandCenter` for control
  centre integration.

---

## 25. Persistence summary

| Item | Path | Format |
|---|---|---|
| Settings (accent, tempo step, onboarding seen) | SharedPreferences `slavchev_settings` | key/value |
| Transport key bindings | SharedPreferences `transport_keys` | key `key_<ActionName>` → keycode Int |
| Setlists & scenes | `filesDir/setlists/<set>/<scene>/scene.json` | JSON (UTF-8) |
| Per-pad WAV per scene | `…/<scene>/pad_NN.wav` | WAV bytes (copied from source) |
| Recorded loop per scene | `…/<scene>/looper.pcm` | raw float32 LE mono PCM |
| Scene ordering per setlist | `…/<set>/order.json` | JSON array of scene names |
| User beat presets | `filesDir/user_presets.json` | JSON array (see `UserPresetStore`) |

On iOS the equivalents live in `Application Support/SlavchevMachine/setlists/…`
and `UserDefaults` for the simple key-value pieces.

---

## 26. Algorithms & code references

### 26.1 RBJ biquad coefficients (used by Master EQ and ParametricEq)

`omega = 2π × f0 / fs`, `cosw = cos(omega)`, `sinw = sin(omega)`,
`alpha = sinw / (2Q)`, `A = 10^(gainDb / 40)` (for peaking / shelf).

**Peaking (Bell):**
```
b0 = 1 + α·A
b1 = -2·cosw
b2 = 1 - α·A
a0 = 1 + α/A
a1 = -2·cosw
a2 = 1 - α/A
```

**Low shelf:**
```
b0 =    A·((A+1) - (A-1)·cosw + 2·√A·α)
b1 =  2·A·((A-1) - (A+1)·cosw)
b2 =    A·((A+1) - (A-1)·cosw - 2·√A·α)
a0 =       (A+1) + (A-1)·cosw + 2·√A·α
a1 =   -2·((A-1) + (A+1)·cosw)
a2 =       (A+1) + (A-1)·cosw - 2·√A·α
```

**High shelf:**
```
b0 =    A·((A+1) + (A-1)·cosw + 2·√A·α)
b1 = -2·A·((A-1) + (A+1)·cosw)
b2 =    A·((A+1) + (A-1)·cosw - 2·√A·α)
a0 =       (A+1) - (A-1)·cosw + 2·√A·α
a1 =    2·((A-1) - (A+1)·cosw)
a2 =       (A+1) - (A-1)·cosw - 2·√A·α
```

**Low-cut (high-pass):**
```
b0 =  (1+cosw)/2
b1 = -(1+cosw)
b2 =  (1+cosw)/2
a0 =   1+α
a1 =  -2·cosw
a2 =   1-α
```

**High-cut (low-pass):**
```
b0 =  (1-cosw)/2
b1 =   1-cosw
b2 =  (1-cosw)/2
a0 =   1+α
a1 =  -2·cosw
a2 =   1-α
```

All coefficients are normalised by dividing `b0,b1,b2,a1,a2` by `a0`.

### 26.2 Biquad magnitude response (for the EQ curve)

For coefficients `b0,b1,b2,a1,a2` (a0 already normalised to 1), at digital
frequency `w = 2π × f / fs`:

```
numRe = b0 + b1·cos(w) + b2·cos(2w)
numIm = -(b1·sin(w) + b2·sin(2w))
denRe = 1 + a1·cos(w) + a2·cos(2w)
denIm = -(a1·sin(w) + a2·sin(2w))

|H|² = (numRe² + numIm²) / max(denRe² + denIm², 1e-12)
dB = 10 · log10(max(|H|², 1e-9))
```

The combined response of N cascaded biquads is the **sum of each band's dB**
response (since `|H1·H2·…| → 20log10 = 20log10|H1| + 20log10|H2| + …`).

### 26.3 Round-robin pick (xorshift32)

A lock-free pad-trigger needs randomness without calling `rand()` on the
audio thread:

```cpp
uint32_t s = state.fetch_add(1, relaxed);  // dummy advance
s ^= s << 13; s ^= s >> 17; s ^= s << 5;   // xorshift32
int next = s % count;
if (next == lastPlayed.load(relaxed)) next = (next + 1) % count;
lastPlayed.store(next, relaxed);
play(samples[next]);
```

### 26.4 Linkwitz-Riley crossover (for the compressor)

Two 2nd-order Butterworth filters cascaded — a 4th-order Linkwitz-Riley
(24 dB/oct). Implement as two RBJ low-pass (or high-pass) biquads in series
with Q = 0.7071. Use **subtractive** splitting:
```
high = input - low_pass(input)
```
to guarantee perfect summation back to the input when no compression is
applied. Three crossover frequencies → four bands.

### 26.5 Compressor band (Range model)

For each band, per sample:
```
absX     = |sample|
envelope = envelope · coef_release + max(absX - envelope, 0) · coef_attack
overdB   = 20·log10(envelope) - threshold_dB        // > 0 means above thr
overdB   = max(overdB, 0)
gainDB   = clamp(-overdB, range_dB, 0)              // Range is the floor (negative)
                                                    // — or ceiling if Range > 0 (expand)
sample  *= 10^((gainDB + makeup_dB) / 20)
```

Attack/release coefficients are computed from the time constants once per
parameter change, not per sample.

### 26.6 Where the bar-snap math lives (looper)

`Looper::onBar(barFrames)`:

```cpp
case kArmed:      // start recording at this bar
    recordLen = 0;
    barOffsets.clear();
    barOffsets.push_back(0);
    state = kRecording;

case kRecording:  // each subsequent bar — mark where the new bar begins
    barOffsets.push_back(recordLen);

case kEndArmed:   // finalise into a loop (Playing or Stopped per flag)
    finalizeLoop();

case kPlayArmed:  // cued resume — start from frame 0 on this downbeat
    playPos = 0;
    barsSincePlay = 0;
    snapTarget = -1;
    state = kPlaying;

case kPlaying:    // re-lock to the sequencer's downbeat each bar
    ++barsSincePlay;
    b = barsSincePlay mod barOffsets.size();
    snapTarget = barOffsets[b];     // atomic, consumed by mixInto
```

### 26.7 Lock-free voice triggering pattern

```cpp
// UI / JNI thread
for (Voice& v : voices) {
    if (v.sample.load(memory_order_acquire) == nullptr) {
        v.frameIndex = 0;
        v.gain = velocity * padVolume;
        v.padIndex = padIndex;
        v.sample.store(&sample, memory_order_release);  // publishes the writes
        break;
    }
}

// Audio thread (per voice, per buffer)
const Sample* s = v.sample.load(memory_order_acquire);
if (!s) continue;
// safe to read v.frameIndex, v.gain, v.padIndex — they were written before
// the release-store above
```

---

## End of spec

Everything the Android version does is captured above. If you need the exact
Kotlin / C++ source for a specific subsystem, it lives in the repository at
the paths referenced throughout (`app/src/main/cpp/…`,
`app/src/main/java/com/slavchev/machine/…`).

When in doubt about **behaviour**, match the Android version. When in doubt
about **idiom**, use idiomatic Swift / SwiftUI. The goal is a port that
*plays* identically, not a line-for-line transliteration.
