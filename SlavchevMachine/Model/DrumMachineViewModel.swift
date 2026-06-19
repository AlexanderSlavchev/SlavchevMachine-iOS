import Foundation
import SwiftUI
import Combine

enum SequencerSection: Int { case a = 0, b = 1 }

enum PaneMode: Int, CaseIterable {
    case pads, looper, mix, eq
    var label: String {
        switch self {
        case .pads: return "PADS"
        case .looper: return "LOOPER"
        case .mix: return "MIX"
        case .eq: return "EQ"
        }
    }
}

enum FillSlot { case one, two }

/// Pending request to open a context-menu for a long-pressed transport button.
struct TransportMenuRequest: Identifiable, Equatable {
    let id = UUID()
    let action: TransportAction
}

@MainActor
final class DrumMachineViewModel: ObservableObject {
    let audio = AudioEngine.shared
    let ticker = SequencerTicker()
    let keyController = TransportKeyController()

    // Top-level
    @Published var accent: AccentChoice = SettingsStore.accent {
        didSet { SettingsStore.accent = accent }
    }
    @Published var paneMode: PaneMode = .pads

    // Transport
    @Published var bpm: Float = 120
    @Published var humanize: Bool = false
    @Published var tempoLock: Bool = false
    @Published var timeSignature: TimeSignature = .default
    @Published var isPlaying: Bool = false
    @Published var recording: Bool = false
    @Published var currentStep: Int = -1
    @Published var activeSection: SequencerSection = .a

    // Sequencer
    @Published var matrixA: [[Int]] = Array(repeating: Array(repeating: 0, count: 16),
                                            count: AudioConstants.numPads)
    @Published var matrixB: [[Int]] = Array(repeating: Array(repeating: 0, count: 16),
                                            count: AudioConstants.numPads)
    @Published var selectedPad: Int = 0    // which pad's row the sequencer edits

    // Fills
    @Published var armedFill: FillSlot? = nil   // visual "armed" indicator
    private var activeFill: [[Int]]? = nil      // overlay matrix while fill is playing
    private var pendingCrashAtNextStep: Bool = false

    // Pads
    @Published var padVolumes: [Float] = Array(repeating: 1, count: AudioConstants.numPads)
    @Published var padHasSample: [Bool] = Array(repeating: false, count: AudioConstants.numPads)
    @Published var padSources: [PadSampleSource?] = Array(repeating: nil,
                                                          count: AudioConstants.numPads)

    // Master EQ + compressor
    @Published var eqGains: [Float] = Array(repeating: 0, count: 8)
    @Published var compressorEnabled: Bool = true

    // Looper
    @Published var looperState: LooperState = .empty
    @Published var looperInputDb: Float = 0
    @Published var looperOutputDb: Float = 0
    @Published var looperFollowStop: Bool = false
    @Published var looperEqBands: [EqBandConfig] = Array(repeating: EqBandConfig(), count: 6)

    // Looper multi-input routing + per-track mute
    @Published var looperActiveTracks: Int = 1
    @Published var looperTrackMuted: [Bool] = Array(repeating: false, count: Looper.maxTracks)
    @Published var looperChannelNames: [String] = []
    @Published var inputChannelCount: Int = 1

    // Scene / setlist
    @Published var setlist: String = ""
    @Published var sceneName: String = "INIT"

    // Transport learn UI
    @Published var transportMenuFor: TransportMenuRequest? = nil
    @Published var pendingMicPrompt: Bool = false

    // Tap tempo (rolling timestamps; reset window 2s)
    private var tapTimes: [Date] = []

    // Recording quantization
    private var lastStepFiredAt: Date?
    private var lastIntervalMs: Double = 250

    // Polling
    private var stateTimer: Timer?

    init() {
        ticker.bpm = bpm
        ticker.stepCount = timeSignature.stepCount
        ticker.onStep = { [weak self] step in
            DispatchQueue.main.async { self?.handleStep(step) }
        }
        ticker.onBar = { [weak self] in
            Task { @MainActor in self?.handleBar() }
        }
        keyController.onAction = { [weak self] action in
            Task { @MainActor in self?.fire(action: action) }
        }
    }

    func bootstrap() {
        do { try audio.start() } catch { print("Audio start failed: \(error)"); return }
        loadKit(.init(name: "cajon", origin: .builtIn))
        applyLooperRouting()
        startStatePolling()
    }

    private func startStatePolling() {
        stateTimer?.invalidate()
        stateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let lp = self.audio.looper else { return }
            Task { @MainActor in
                let s = lp.state
                if s != self.looperState {
                    let wasRecording = self.looperState == .recording || self.looperState == .endArmed
                    let nowPlaying = s == .playing
                    self.looperState = s
                    // When the loop finalises (recording → playing), recalculate compensation
                    // using current session latency readings — they're most accurate now that
                    // the input has been actively delivering for a while.
                    if wasRecording && nowPlaying {
                        self.audio.recalculateLoopLatency()
                    }
                }
            }
        }
    }

    // MARK: - Transport

    func play() {
        isPlaying = true
        ticker.bpm = bpm
        ticker.stepCount = timeSignature.stepCount
        ticker.humanize = humanize
        ticker.start()
    }

    /// Stop button: stop transport, clear active fill, allNotesOff, then a punctuating kick + crash.
    func stop() {
        isPlaying = false
        ticker.stop()
        audio.allNotesOff()
        currentStep = -1
        activeFill = nil
        armedFill = nil
        pendingCrashAtNextStep = false
        if looperFollowStop { audio.looper?.stopAction() }
        audio.triggerPad(FillPatterns.kPadKick, velocity: 1.0)
        audio.triggerPad(FillPatterns.kPadCrash, velocity: 0.9)
    }

    func togglePlay() { if isPlaying { stop() } else { play() } }

    func toggleRecording() {
        recording.toggle()
    }

    /// Tap tempo with 2s reset window between taps.
    func tapTempo() {
        let now = Date()
        if let last = tapTimes.last, now.timeIntervalSince(last) > 2 {
            tapTimes.removeAll()
        }
        tapTimes.append(now)
        if tapTimes.count > 4 { tapTimes.removeFirst() }
        if tapTimes.count >= 2 {
            let intervals = zip(tapTimes.dropFirst(), tapTimes).map { $0.timeIntervalSince($1) }
            let avg = intervals.reduce(0, +) / Double(intervals.count)
            if avg > 0 {
                let candidate = Float(60.0 / avg)
                setBpm(candidate)
            }
        }
    }

    func setBpm(_ value: Float) {
        let clamped = max(40, min(240, value))
        bpm = clamped
        ticker.bpm = clamped
    }

    func adjustBpm(_ delta: Float) { setBpm(bpm + delta) }

    func setTimeSignature(_ ts: TimeSignature) {
        timeSignature = ts
        ticker.stepCount = ts.stepCount
        resizeMatrices(to: ts.stepCount)
    }

    private func resizeMatrices(to steps: Int) {
        matrixA = matrixA.map { resizeRow($0, to: steps) }
        matrixB = matrixB.map { resizeRow($0, to: steps) }
    }

    private func resizeRow(_ row: [Int], to steps: Int) -> [Int] {
        var out = Array(repeating: 0, count: steps)
        for i in 0..<min(row.count, steps) { out[i] = row[i] }
        return out
    }

    // MARK: - Sequencer step (with fill overlay + humanize)

    private func handleStep(_ step: Int) {
        let interval = 60_000.0 / Double(max(bpm, 1)) / 4.0
        lastIntervalMs = interval
        lastStepFiredAt = Date()
        currentStep = step

        // Metronome click during recording.
        if recording {
            let groupStarts = timeSignature.groupStartSteps
            if step == 0 {
                audio.triggerPad(FillPatterns.kPadClick, velocity: 1.0)
            } else if groupStarts.contains(step) {
                audio.triggerPad(FillPatterns.kPadClick, velocity: 0.55)
            }
        }

        // Crash that punctuates the start of a new bar after a fill.
        if pendingCrashAtNextStep && step == 0 {
            audio.triggerPad(FillPatterns.kPadCrash, velocity: 1.0)
            pendingCrashAtNextStep = false
        }

        let base = (activeSection == .a) ? matrixA : matrixB
        for pad in 0..<AudioConstants.numPads {
            let baseRaw = base[pad].indices.contains(step) ? base[pad][step] : 0
            let fillRaw: Int = {
                guard let f = activeFill, f.indices.contains(pad),
                      f[pad].indices.contains(step) else { return 0 }
                return f[pad][step]
            }()
            let raw = max(baseRaw, fillRaw)
            if raw <= 0 { continue }
            var velocity = Float(raw) / 127.0
            var delayMs: Double = 0
            if humanize {
                velocity *= Float.random(in: 0.75...1.0)
                delayMs = Double.random(in: 0...15)
            }
            if delayMs > 0 {
                let v = velocity
                DispatchQueue.main.asyncAfter(deadline: .now() + delayMs / 1000.0) { [weak self] in
                    self?.audio.triggerPad(pad, velocity: v)
                }
            } else {
                audio.triggerPad(pad, velocity: velocity)
            }
        }
    }

    private func handleBar() {
        audio.looper?.onBar()
        // Bar wrap: clear fill, arm crash.
        if activeFill != nil {
            activeFill = nil
            armedFill = nil
            pendingCrashAtNextStep = true
        }
    }

    // MARK: - Sequencer cell editing

    func toggleStep(pad: Int, step: Int) {
        if activeSection == .a {
            matrixA[pad][step] = matrixA[pad][step] > 0 ? 0 : 127
        } else {
            matrixB[pad][step] = matrixB[pad][step] > 0 ? 0 : 127
        }
    }

    func setStepVelocity(pad: Int, step: Int, velocity: Int) {
        let v = max(0, min(127, velocity))
        if activeSection == .a { matrixA[pad][step] = v } else { matrixB[pad][step] = v }
    }

    // MARK: - Pads

    func selectPad(_ pad: Int) {
        guard pad >= 0 && pad < AudioConstants.numPads else { return }
        selectedPad = pad
    }

    func setPadVolume(_ pad: Int, volume: Float) {
        let v = max(0, min(1, volume))
        padVolumes[pad] = v
        audio.setPadVolume(pad: pad, volume: v)
    }

    /// Trigger a pad. If recording AND playing, also write the velocity to the quantized step.
    func triggerPad(_ pad: Int, velocity: Float) {
        audio.triggerPad(pad, velocity: velocity)
        if recording && isPlaying {
            let target = quantizedStep()
            let v = max(1, min(127, Int((velocity * 127.0).rounded())))
            if activeSection == .a { matrixA[pad][target] = v } else { matrixB[pad][target] = v }
        }
    }

    /// Quantize the wall-clock moment of a live pad tap to the nearest 16th step.
    private func quantizedStep() -> Int {
        let steps = timeSignature.stepCount
        guard currentStep >= 0 else { return 0 }
        guard let last = lastStepFiredAt else { return currentStep }
        let elapsedMs = Date().timeIntervalSince(last) * 1000.0
        if elapsedMs > lastIntervalMs / 2 {
            return (currentStep + 1) % steps
        }
        return currentStep
    }

    // MARK: - Fills

    func armFill(_ slot: FillSlot) {
        armedFill = slot
        activeFill = (slot == .one) ? FillPatterns.randomFill1() : FillPatterns.randomFill2()
        if !isPlaying { play() }
    }

    // MARK: - EQ

    func setEqGain(band: Int, db: Float) {
        eqGains[band] = max(-12, min(12, db))
        audio.masterEq.setGain(band, db: eqGains[band])
    }

    func flattenEq() { for i in 0..<8 { setEqGain(band: i, db: 0) } }

    // MARK: - Looper

    func looperTap() {
        if audio.looper?.state == .empty {
            requestMicPermissionIfNeeded { [weak self] granted in
                guard let self = self, granted else { return }
                Task { @MainActor in
                    try? self.audio.looperStartInput()
                    self.audio.looper?.tap()
                }
            }
        } else {
            audio.looper?.tap()
        }
    }

    func looperStop() { audio.looper?.stopAction() }
    func looperClear() { audio.looper?.clear() }

    func setLooperInputDb(_ db: Float) {
        looperInputDb = db
        audio.looper?.setInputGain(db: db)
    }

    func setLooperOutputDb(_ db: Float) {
        looperOutputDb = db
        audio.looper?.setOutputGain(db: db)
    }

    func setLooperEqBand(_ i: Int, _ cfg: EqBandConfig) {
        looperEqBands[i] = cfg
        audio.looper?.setEqBand(i, cfg)
    }

    // MARK: - Looper routing & per-track mute

    /// Apply the saved Looper Routing to the engine and refresh the UI-facing state.
    func applyLooperRouting() {
        audio.applyLooperRouting()
        refreshLooperRouting()
    }

    /// Pull track count + channel labels from the engine into published state.
    func refreshLooperRouting() {
        looperActiveTracks = audio.looper?.trackCount ?? 1
        inputChannelCount = audio.availableInputChannelCount()
        looperChannelNames = audio.inputChannelNames()
        // Mirror current mute flags from the looper.
        if let lp = audio.looper {
            for t in 0..<Looper.maxTracks { looperTrackMuted[t] = lp.isMuted(track: t) }
        }
    }

    func toggleLooperMute(_ track: Int) {
        guard track >= 0 && track < Looper.maxTracks else { return }
        setLooperMute(track, !looperTrackMuted[track])
    }

    func setLooperMute(_ track: Int, _ on: Bool) {
        guard track >= 0 && track < Looper.maxTracks else { return }
        looperTrackMuted[track] = on
        audio.looper?.setMuted(track: track, on)
    }

    /// Label for a routed track (hardware channel name when available, else "INPUT n").
    func looperTrackLabel(_ track: Int) -> String {
        let map = audio.looperRoutingMap()
        if track < map.count {
            let ch = map[track]
            if ch < looperChannelNames.count { return looperChannelNames[ch] }
        }
        return "INPUT \(track + 1)"
    }

    private func requestMicPermissionIfNeeded(_ completion: @escaping (Bool) -> Void) {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted: completion(true)
        case .denied: completion(false)
        case .undetermined:
            pendingMicPrompt = true
            session.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    self.pendingMicPrompt = false
                    completion(granted)
                }
            }
        @unknown default: completion(false)
        }
    }

    // MARK: - Kits & samples

    func loadKit(_ kit: KitRef) {
        let rr = KitStore.roundRobinSourcesForKit(kit)
        var loadedMultiVariant = 0
        for pad in 0..<AudioConstants.numPads {
            let sources = rr[pad] ?? []
            let samples = sources.compactMap { $0.decode(targetSampleRate: Double(audio.sampleRate)) }
            audio.setPadSamples(pad: pad, samples: samples)
            padHasSample[pad] = !samples.isEmpty
            padSources[pad] = sources.first
            if samples.count > 1 { loadedMultiVariant += 1 }
        }
        #if DEBUG
        print("[Kit] loaded '\(kit.name)' — \(loadedMultiVariant) pad(s) have round-robin variants")
        #endif
    }

    func assignPad(_ pad: Int, sources: [PadSampleSource]) {
        let samples = sources.prefix(AudioConstants.maxPadLayers).compactMap {
            $0.decode(targetSampleRate: Double(audio.sampleRate))
        }
        audio.setPadSamples(pad: pad, samples: samples)
        padHasSample[pad] = !samples.isEmpty
        padSources[pad] = sources.first
    }

    // MARK: - Beat presets / scenes

    func loadBeatPreset(_ p: BeatPreset) {
        if !tempoLock { setBpm(p.bpm) }
        setTimeSignature(p.timeSignature)
        if activeSection == .a {
            matrixA = p.matrix
            matrixB = PatternVariation.deriveBSection(p.matrix)
        } else {
            matrixB = p.matrix
        }
        selectedPad = 0
    }

    /// Snapshot the current visible section as a user preset.
    func snapshotAsBeatPreset(name: String) -> BeatPreset {
        let matrix = activeSection == .a ? matrixA : matrixB
        return BeatPreset(name: name, bpm: bpm, style: nil, kitName: "cajon",
                          matrix: matrix, timeSignatureString: timeSignature.format())
    }

    func loadScene(setlist setName: String, scene s: SceneSnapshot, padSources: [PadSampleSource?]) {
        setBpm(s.bpm)
        humanize = s.humanize
        setTimeSignature(TimeSignature.parse(s.timeSignature))
        matrixA = s.drumsMatrix
        matrixB = s.drumsMatrixB ?? PatternVariation.deriveBSection(s.drumsMatrix)
        for (i, v) in s.padVolumes.enumerated() where i < AudioConstants.numPads {
            setPadVolume(i, volume: v)
        }
        for (i, src) in padSources.enumerated() where i < AudioConstants.numPads {
            if let src = src {
                assignPad(i, sources: [src])
            } else {
                audio.clearPad(pad: i)
                padHasSample[i] = false
                self.padSources[i] = nil
            }
        }
        if let lp = s.looper {
            setLooperInputDb(lp.inputGainDb)
            setLooperOutputDb(lp.outputGainDb)
            looperFollowStop = lp.followStop
            for (i, b) in lp.eqBands.enumerated() where i < 6 {
                let cfg = EqBandConfig(shape: EqShape(rawValue: b.shape) ?? .bell,
                                       freqHz: b.freqHz, gainDb: b.gainDb, q: b.q, enabled: b.enabled)
                setLooperEqBand(i, cfg)
            }
            let trackCount = lp.trackCount ?? 1
            let muted = lp.trackMuted ?? Array(repeating: false, count: trackCount)
            if lp.hasLoop {
                let tracks = SceneStore.loadLooperTracks(setlist: setName, name: s.name, trackCount: trackCount)
                if !tracks.isEmpty {
                    audio.looper?.importTracks(pcms: tracks, barOffsets: lp.barOffsets,
                                               latencyComp: lp.latencyComp, muted: muted)
                } else {
                    audio.looper?.clear()
                }
            } else {
                audio.looper?.clear()
            }
            for t in 0..<Looper.maxTracks {
                looperTrackMuted[t] = t < muted.count ? muted[t] : false
            }
            refreshLooperRouting()
        }
        sceneName = s.name
        setlist = setName
        selectedPad = 0
    }

    func snapshotScene(name: String, includeLoop: Bool) -> SceneSnapshot {
        let lpBands = looperEqBands.map {
            SceneEqBand(shape: $0.shape.rawValue, freqHz: $0.freqHz,
                        gainDb: $0.gainDb, q: $0.q, enabled: $0.enabled)
        }
        let lpState = audio.looper?.state ?? .empty
        let hasLoop = includeLoop && (lpState == .playing || lpState == .stopped || lpState == .playArmed)
        return SceneSnapshot(
            name: name,
            bpm: bpm,
            humanize: humanize,
            timeSignature: timeSignature.format(),
            drumsMatrix: matrixA,
            drumsMatrixB: matrixB,
            padVolumes: padVolumes,
            padHasSample: padHasSample,
            looper: .init(inputGainDb: looperInputDb,
                          outputGainDb: looperOutputDb,
                          followStop: looperFollowStop,
                          hasLoop: hasLoop,
                          latencyComp: audio.looper?.latencyCompFrames ?? 0,
                          barOffsets: audio.looper?.barOffsets ?? [],
                          eqBands: lpBands,
                          trackCount: audio.looper?.trackCount ?? 1,
                          trackMuted: looperTrackMuted)
        )
    }

    // MARK: - Scene navigation (within current setlist)

    func navigateScene(delta: Int) {
        guard !setlist.isEmpty else { return }
        let scenes = SceneStore.listScenes(setlist: setlist)
        guard let i = scenes.firstIndex(of: sceneName) else { return }
        let next = i + delta
        guard next >= 0 && next < scenes.count else { return }
        let target = scenes[next]
        if let (s, srcs) = SceneStore.loadScene(setlist: setlist, name: target) {
            loadScene(setlist: setlist, scene: s, padSources: srcs)
        }
    }

    // MARK: - Hardware key actions

    func fire(action: TransportAction) {
        switch action {
        case .play: togglePlay()
        case .stop: stop()
        case .nextScene: navigateScene(delta: 1)
        case .previousScene: navigateScene(delta: -1)
        case .sectionToggle: activeSection = (activeSection == .a) ? .b : .a
        case .fill1: armFill(.one)
        case .fill2: armFill(.two)
        case .tempoStepUp: adjustBpm(Float(SettingsStore.tempoStepUp))
        case .tempoStepDown: adjustBpm(-Float(SettingsStore.tempoStepDown))
        case .looperRecord: looperTap()
        case .looperStop: looperStop()
        case .looperMute1, .looperMute2, .looperMute3, .looperMute4:
            if let t = action.looperMuteTrack { toggleLooperMute(t) }
        }
    }

    // MARK: - Transport learn helpers

    func openTransportMenu(for action: TransportAction) {
        transportMenuFor = TransportMenuRequest(action: action)
    }

    func startLearning(_ action: TransportAction) {
        transportMenuFor = nil
        keyController.startLearning(action)
    }

    // MARK: - Accent cycling

    func cycleAccent() {
        let all = AccentChoice.allCases
        if let i = all.firstIndex(of: accent) {
            accent = all[(i + 1) % all.count]
        }
    }
}

// Needed for AVAudioSession import.
import AVFoundation
