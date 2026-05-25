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

## Running on a real iPhone

You can run on any iPhone with a **free** Apple ID — no $99 Apple Developer membership needed. Free signing lets you install the app on devices you own; the build expires every 7 days and re-installs with another ⌘R.

### One-time setup

**1. Sign in to your Apple ID inside Xcode**

- Xcode → Settings (⌘,) → **Accounts** tab
- `+` (bottom-left) → **Apple ID** → enter your Apple ID + password
- Once added, you'll see a free "Personal Team" listed under that Apple ID

**2. Configure code signing for the project**

- Open `SlavchevMachine.xcodeproj` in Xcode
- Click the blue **SlavchevMachine** project icon at the top of the left sidebar
- Select the **SlavchevMachine** *target* (under TARGETS)
- Open the **Signing & Capabilities** tab
- Check **Automatically manage signing**
- For **Team**, pick your **Personal Team (your name)**
- The **Bundle Identifier** is `com.slavchev.machine` by default. If Xcode complains that it's taken (Apple requires unique IDs even for free signing), change it to something like `com.yourname.slavchevmachine`

**3. Connect your iPhone**

- Plug iPhone into Mac with a USB-C / Lightning cable (Wi-Fi pairing works too — see [§Wireless](#wireless-debugging) below)
- On first connection iPhone asks **"Trust this Computer?"** — tap **Trust** and enter your passcode
- In Xcode's top toolbar, click the run-destination dropdown (says "iPhone 16" or similar) and pick your **real device** from the list — it will appear under "iOS Device" once paired

**4. Enable Developer Mode on the iPhone** *(iOS 16+)*

- First time you try to run on a real device, iOS will show an alert saying "Developer Mode required"
- On the iPhone: **Settings → Privacy & Security → Developer Mode → toggle ON**
- iPhone will reboot — after reboot, confirm "Turn On" when prompted

**5. Build & install**

- In Xcode press **⌘R** (or click the ▶ Play button)
- First time, Xcode builds + uploads the `.app` to your device (~30–60s)
- iPhone will show: *"Untrusted Developer"* — this is normal for free signing
  - On iPhone: **Settings → General → VPN & Device Management → Developer App** → your Apple ID → **Trust**
- Now go back to Xcode and press **⌘R** again — app launches on the iPhone

### Permissions you'll see on first launch

- **Microphone access** — the looper needs it to record audio loops. Tap **Allow**. If you tap Don't Allow, the looper will silently fail on first arm; you can re-enable it later in **Settings → SlavchevMachine → Microphone**.
- **Bluetooth** — only if you pair a Bluetooth page-turner / external keyboard for hardware transport control. The app itself doesn't request it; iOS prompts the first time you use a BLE input.

### Hardware key control with a Bluetooth foot pedal

- Pair your foot pedal / page-turner in **iPhone Settings → Bluetooth** first
- In the app, **long-press** any transport button (PLAY · STOP · ‹ · › · B · FILL 1 · FILL 2) → context menu → tap **LEARN BT KEY** → press the pedal once → it's bound
- **Important iOS limitation:** keys only work while the app is in the **foreground**. Unlike Android's AccessibilityService, iOS does not let third-party apps receive HID key events in the background. Audio keeps playing in the background (background-audio capability), but to advance scenes / trigger fills via the pedal you need the app visible.
- Looper REC / STOP keys: bind them from inside the **LOOPER** pane → REC KEY / STOP KEY → LEARN.

### Wireless debugging

Once paired over USB at least once, you can run wirelessly:

- Xcode → **Window → Devices and Simulators**
- Select your iPhone
- Check **Connect via network**
- Unplug — iPhone appears in the run-destination dropdown with a Wi-Fi 🛜 icon next to its name
- Press **⌘R** as normal

### Re-signing after 7 days

With a free Apple ID, the provisioning profile expires after 7 days and the app stops launching from the home screen ("Untrusted" alert reappears). To extend it just plug the iPhone in and press ⌘R again — Xcode re-signs and reinstalls in ~10s, no data is lost.

If you upgrade to a **paid Apple Developer Program** ($99/yr) the signing lasts 1 year and you can also distribute via TestFlight / App Store.

### Troubleshooting

| Symptom | Fix |
|---|---|
| `Could not launch "SlavchevMachine"` + "Untrusted Developer" | iPhone Settings → General → VPN & Device Management → trust your developer profile |
| Xcode shows *"No code signing identities found"* | Signing & Capabilities → tick "Automatically manage signing" + pick your Personal Team |
| Bundle ID conflict (`com.slavchev.machine` is taken) | Change Bundle Identifier to `com.yourname.slavchevmachine` |
| No audio / very quiet on iPhone | Increase phone media volume, not ringer volume. Lock-screen rocker is ringer; use the side buttons while the app is foreground for media |
| Looper records silence | Mic permission was denied. Settings → SlavchevMachine → Microphone → ON |
| Latency feels high vs Android | Open Settings → SlavchevMachine → make sure no other audio apps are running. iOS picks lowest latency device available; AirPods Bluetooth add ~100ms (use wired / built-in speaker for testing) |
| App crashes at launch with codesign error | Run **Product → Clean Build Folder** (⇧⌘K) then ⌘R again |

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
