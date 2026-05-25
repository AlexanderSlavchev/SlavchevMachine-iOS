# SlavchevMachine — iOS

iOS port of [SlavchevMachine](../SlavchevMachine) — drum machine + groovebox inspired by the Alesis SR-18. Pure Swift + SwiftUI, AVAudioEngine for audio. Mirrors the Android version per `IOS_PORT_SPEC.md`.

## Setup

This project requires **Xcode 16+** (currently built against Xcode 26.3).

First time only:

```bash
sudo xcodebuild -license accept
```

Then open the project:

```bash
open SlavchevMachine.xcodeproj
```

In Xcode:

1. Select the **SlavchevMachine** scheme.
2. Pick an iPhone simulator (iOS 16+) or your device.
3. Press **⌘R**.

The project uses Xcode 16+'s filesystem-synchronized groups, so any `.swift` you add anywhere under `SlavchevMachine/` is picked up automatically — no need to edit `project.pbxproj`. The `Resources/Kits/` folder is bundled with WAV samples for the two built-in drum kits (`cajon`, `AlexDrumKit`).

## What's implemented

Per the spec:

| Subsystem | Status |
|---|---|
| Audio engine — voices, choke groups, round-robin, soft clip | done (Swift, AVAudioEngine source node) |
| Master EQ — 8 peaking biquads, RBJ formulae | done |
| Multiband compressor — 4-band L-R crossover, range model | done |
| Looper — 7-state machine, bar-snap, latency comp, parametric EQ | done |
| Sequencer ticker — absolute-time loop (no drift) | done |
| Time signatures, beat grouping, group-start shading | done |
| All 56 default beat presets | done |
| Scene/setlist persistence (Application Support JSON + WAV + raw PCM) | done |
| Settings (accent, tempo step, onboarding flag) | done |
| Hardware key bindings (UIKeyCommand, `UIKeyboardHIDUsage`) | done — foreground only on iOS (see §16.6) |
| Background audio (`AVAudioSession.playAndRecord`, UIBackgroundModes audio) | configured |
| Microphone permission (`NSMicrophoneUsageDescription`) | configured |
| Main screen, OLED display, transport row, mode switcher, scene nav | done |
| PADS / MIX / EQ / LOOPER panes (incl. interactive EQ graph) | done |
| Dialogs — Settings, Time signature, Beat library, Scene library, Saved loops, Compressor, Kit browser, Save-as | done |
| Onboarding coach-mark tour (14 steps) | done |

## What's deferred / TODO

- Sequencer step-row currently edits the KICK row only. Adding a per-pad row selector (or 16 rows like Android) is the next iteration.
- Fills (Fill 1/2) trigger a placeholder pattern — the Android version's `PatternVariation` for fills can be ported in a follow-up.
- `TransportLearnOverlay` UI for visualising key learn — bindings work via `TransportKeyController`, but the overlay is not yet wired into the long-press menus on transport buttons.
- `ConfirmDialog` two-step arm pattern is used inline in `SavedLoopsDialog`; not extracted as a reusable component.
- User custom kits (save your own kit folder) — `KitStore.listKits()` reads user kits, but there is no save-kit UI yet.
- `IncludeLoopDialog` is folded into `SaveSceneAsDialog`'s `INCLUDE LOOP AUDIO` toggle.
- DSP is pure Swift (no C++). For lower latency / lower CPU you can later replace `AudioEngine.render` with a custom AudioUnit. The current Swift render runs comfortably at 48 kHz / 256-frame buffers.

## Architecture

```
SlavchevMachine/
├── SlavchevMachineApp.swift           App entry, wires DrumMachineViewModel
├── Info.plist                         (auto-generated INFOPLIST_KEYS)
├── Audio/                             AVAudioEngine + DSP
│   ├── AudioEngine.swift              Voice mixer, render callback, looper input tap
│   ├── Biquad.swift                   RBJ coefficient builders + magnitude response
│   ├── MasterEqualizer.swift          8-band peaking EQ
│   ├── ParametricEqualizer.swift      Up to 6 user bands (5 shapes)
│   ├── MultibandCompressor.swift      4-band Linkwitz-Riley crossovers, range comp
│   ├── Looper.swift                   60s buffer, 7-state machine, bar-snap, EQ
│   ├── SampleStore.swift              Stable-ID sample registry (lock-free reads)
│   ├── WAVDecoder.swift               AVAudioFile-backed decoder → mono float32
│   ├── SequencerTicker.swift          Absolute-time stepping (mach_absolute_time)
│   └── TransportKeyController.swift   UIKeyCommand binding manager
├── Model/                             View-model + persistence
│   ├── DrumMachineViewModel.swift     Central @MainActor state
│   ├── TimeSignature.swift            stepCount, beatGroups, groupStartSteps
│   ├── PatternVariation.swift         A→B section derivation
│   ├── Scene.swift                    Codable scene snapshot
│   ├── SceneStore.swift               Application Support FS persistence
│   ├── PadSampleSource.swift          asset / localFile / external URL
│   ├── KitStore.swift                 Built-in + user kits, round-robin discovery
│   ├── SettingsStore.swift            UserDefaults wrappers
│   ├── BeatPreset.swift               Codable preset
│   └── DefaultPresets.swift           All 56 bundled beats
└── UI/
    ├── DrumMachineScreen.swift        Top-level layout
    ├── Theme/                         Accent, Chassis, typography
    ├── Components/                    OledPanel, Pill, Chip
    ├── MainScreen/                    Brand, SceneNav, TrackTab, Sequencer, ModeSwitcher, OLED, transport
    ├── Panes/                         PadGrid4x4, PadMixPane, MasterEqPane, LooperPane (+ EQ graph)
    ├── Dialogs/                       Settings, Scenes, BeatLibrary, TimeSig, Compressor, SavedLoops, KitBrowser
    └── Onboarding/                    Coach-mark registry + overlay
```

## Notes on iOS vs Android parity

- **Hardware keys in background**: Android uses an AccessibilityService; iOS forbids that. Keys only work while the app is foreground.
- **Sample rate**: We resample on load via `AVAudioConverter`, so loading a 44.1 kHz sample on a 48 kHz device sounds correct (Android's port pitches it).
- **Soft clip**: `tanhf` instead of the Android hard clamp — slightly more musical.
- **Threading**: Pure-Swift voice mixer is coarsely locked with `os_unfair_lock` (rare contention; the audio thread holds it only briefly). If you measure CPU pressure later, the path forward is a `UnsafeAtomic`-based publish/acquire on each `Voice.sample` pointer like the Android C++ engine does.

## Building from the command line

```bash
xcodebuild -project SlavchevMachine.xcodeproj \
           -scheme SlavchevMachine \
           -destination 'platform=iOS Simulator,name=iPhone 16' \
           -derivedDataPath build \
           build
```
