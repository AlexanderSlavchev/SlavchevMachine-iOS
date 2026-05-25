import Foundation
import AVFoundation
import os.lock

/// Public constants — mirrors the Android version.
enum AudioConstants {
    static let numPads = 16
    static let maxVoices = 32
    static let maxPadLayers = 3
    static let padCloseHat = 4
    static let padOpenHat = 5
}

/// One playing voice. Fields written by UI thread under voiceLock; read by audio thread between locks.
/// (We keep a coarse lock around the voice array; for a 32-element flat array on a non-RT thread it's negligible.)
final class Voice {
    var sample: AudioSample?
    var frameIndex: Int = 0
    var gain: Float = 0
    var padIndex: Int = -1
}

final class AudioEngine {
    static let shared = AudioEngine()

    let avEngine = AVAudioEngine()
    private(set) var sampleRate: Float = 48000

    // DSP
    let masterEq = MasterEqualizer()
    let compressor = MultibandCompressor()
    let sampleStore = SampleStore()
    private(set) var looper: Looper!

    // Voices
    private var voices: [Voice] = (0..<AudioConstants.maxVoices).map { _ in Voice() }
    private var voiceLock = os_unfair_lock_s()

    // Per-pad
    private var padSamples: [[AudioSample]] = Array(repeating: [], count: AudioConstants.numPads)
    private var padLastVariant: [Int] = Array(repeating: -1, count: AudioConstants.numPads)
    private(set) var padVolumes: [Float] = Array(repeating: 1.0, count: AudioConstants.numPads)
    private var padConfigLock = os_unfair_lock_s()

    private var rngState: UInt32 = 0x12345678

    // Source node
    private var sourceNode: AVAudioSourceNode!
    private var inputBusFormat: AVAudioFormat!
    // Input monitor mixer — input → mixer → main-mixer. Volume is 0 by default (silent — keeps the
    // input bus alive in the graph so its HW format negotiates) and becomes 1.0 when the user
    // enables live monitoring. Audio stays in the engine's optimised render pipeline so latency
    // is just the I/O round-trip (~10–15 ms on iPhone).
    private var inputSilentSink: AVAudioMixerNode?
    // Debounce: collapse rapid config-change bursts into one rebuild.
    private var pendingReconfig: DispatchWorkItem?
    // Re-entry guard — when we're in the middle of a rebuild, ignore further notifications.
    private var isReconfiguring = false
    // Cooldown — settling notifications fire 200–800ms after our own restart. We ignore
    // any config change notification within `reconfigCooldown` of our last completed rebuild
    // (otherwise our own restart would trigger an immediate next rebuild → infinite loop).
    private var lastReconfigCompletedAt: Date = .distantPast
    private let reconfigCooldown: TimeInterval = 1.0
    // Loop detector — if reconfigs fire faster than we can finish them, we'd thrash forever.
    private var reconfigTimestamps: [Date] = []
    // Idempotent route override — only call overrideOutputAudioPort when the desired state
    // would actually change.
    private var appliedOverride: AVAudioSession.PortOverride = .none
    #if DEBUG
    private var tapDiagnostic = TapDiagnostic()
    #endif

    private init() {}

    // MARK: - Lifecycle

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        // .playAndRecord + .defaultToSpeaker — when no external device is connected, route to
        // the loudspeaker (not the call earpiece). When something IS connected (USB / BT / wired
        // headphones), iOS auto-routes to it unless the user has explicitly forced speaker.
        try session.setCategory(.playAndRecord,
                                mode: .default,
                                options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
        try session.setPreferredSampleRate(48000)
        // Aggressively low I/O buffer — iPhones support down to ~2.5 ms; the system clamps
        // higher if hardware can't comply.
        try session.setPreferredIOBufferDuration(0.003)
        try session.setActive(true, options: [])
        applyRoutingPreferences()
        applyPreferredInput()

        // Disable iOS voice processing on the input node. Voice processing applies AGC,
        // noise suppression, and echo cancellation — collectively adding 20–40 ms to the
        // input path. Music apps (GarageBand, AUM) all disable it. Must be called BEFORE
        // any node is attached to the engine — and only once per engine instance.
        do {
            try avEngine.inputNode.setVoiceProcessingEnabled(false)
            let actually = avEngine.inputNode.isVoiceProcessingEnabled
            #if DEBUG
            let inFmt = avEngine.inputNode.outputFormat(forBus: 0)
            print("[Audio] voice processing requested OFF, actually=\(actually) — input format: \(inFmt)")
            #endif
        } catch {
            print("[Audio] couldn't disable voice processing: \(error) — continuing with default")
        }

        // Route changes — re-apply speaker override when external device is disconnected.
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification, object: session)

        // Engine configuration changes — fired whenever the audio route changes the I/O format
        // (USB sound card plugged in, headphone SR changes, etc.). The engine auto-stops; we
        // must rebuild the graph with the NEW output format and restart, otherwise the source
        // node is stuck at the old SR and produces silence.
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleEngineConfigChange(_:)),
            name: .AVAudioEngineConfigurationChange, object: avEngine)

        try setupOutputGraph()
        try avEngine.start()
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        avEngine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// Build / rebuild the source-node → main-mixer connection using the *current* output format.
    /// Idempotent: safe to call multiple times. Detaches the old source node if its format is stale.
    private func setupOutputGraph() throws {
        let session = AVAudioSession.sharedInstance()
        let outFormat = avEngine.outputNode.inputFormat(forBus: 0)
        // Fall back to session sample rate if outputNode hasn't initialized yet.
        let targetSR = outFormat.sampleRate > 0 ? outFormat.sampleRate : session.sampleRate
        let newSR = Float(targetSR)

        // Refresh shared DSP state.
        sampleRate = newSR
        masterEq.setSampleRate(sampleRate)
        compressor.setSampleRate(sampleRate)
        // Looper buffer is sized in seconds; we re-use it across config changes so any
        // recorded loop survives. Sample-rate field is set at construction — if it changes
        // mid-session we accept slight pitch drift on already-recorded loops.
        if looper == nil { looper = Looper(sampleRate: sampleRate) }

        guard let newBusFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: targetSR,
                                               channels: 2,
                                               interleaved: false) else { return }
        // If a source node already exists with a stale format, detach it and rebuild.
        let needsRebuild = sourceNode == nil
            || sourceNode.outputFormat(forBus: 0).sampleRate != targetSR
        if needsRebuild {
            if let old = sourceNode, avEngine.attachedNodes.contains(old) {
                avEngine.detach(old)
            }
            inputBusFormat = newBusFormat
            sourceNode = AVAudioSourceNode(format: newBusFormat) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
                guard let self = self else { return noErr }
                self.render(frameCount: Int(frameCount), bufferList: audioBufferList)
                return noErr
            }
        }
        if let src = sourceNode {
            if !avEngine.attachedNodes.contains(src) { avEngine.attach(src) }
            avEngine.disconnectNodeOutput(src)
            avEngine.connect(src, to: avEngine.mainMixerNode, format: inputBusFormat)
        }
    }

    /// Route changed (device plugged / unplugged / system override).
    /// When a device is *unplugged* mid-playback iOS automatically falls back to the next
    /// best device (built-in speaker thanks to `.defaultToSpeaker`), but the AVAudioEngine
    /// can be left in an invalid state. We schedule a recovery check on a short delay.
    @objc private func handleRouteChange(_ notification: Notification) {
        applyRoutingPreferences()

        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }

        switch reason {
        case .oldDeviceUnavailable:
            // External device was disconnected. Give iOS ~100ms to settle on the fallback
            // device, then make sure our engine is still alive.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.recoverAfterDeviceLoss()
            }
        case .newDeviceAvailable, .categoryChange, .routeConfigurationChange,
             .wakeFromSleep, .noSuitableRouteForCategory, .override, .unknown:
            break
        @unknown default:
            break
        }
    }

    /// After a device disconnect, verify the engine is still producing audio. If it isn't,
    /// rebuild the graph against whatever fallback route iOS picked (usually built-in speaker).
    /// Also clear setPreferredInput so iOS picks the built-in mic when the previously-preferred
    /// USB / BT input is gone.
    private func recoverAfterDeviceLoss() {
        // If our preferred input is no longer available, drop the active preference
        // (but keep the saved UID so it auto-restores when the device is re-plugged).
        if let preferredUID = SettingsStore.preferredInputUID,
           AVAudioSession.sharedInstance().availableInputs?.contains(where: { $0.uid == preferredUID }) != true {
            try? AVAudioSession.sharedInstance().setPreferredInput(nil)
            print("[Audio] preferred input '\(preferredUID)' gone — fell back to system default")
        }
        if !avEngine.isRunning {
            attemptEngineRestart(reason: "device loss")
        }
    }

    /// Restart the engine. Tries immediately, then with widening delays so iOS has time to
    /// settle on the new route (some configurations — e.g. built-in mic + USB output — need
    /// 150–300ms before the session is in a state where the I/O unit will actually start).
    /// Falls back to a full session reset on the last attempt. Never crashes.
    private func attemptEngineRestart(reason: String) {
        doRestartAttempt(reason: reason, attempt: 1)
    }

    private func doRestartAttempt(reason: String, attempt: Int) {
        // Don't try to start an already-running engine.
        if avEngine.isRunning {
            applyRoutingPreferences()
            return
        }
        do {
            try setupOutputGraph()
            try avEngine.start()
            applyRoutingPreferences()
            print("[Audio] engine restarted after \(reason) (attempt \(attempt))")
            return
        } catch {
            print("[Audio] restart attempt \(attempt) (\(reason)) failed: \(error)")
        }
        // Schedule next attempt with widening delay (50ms, 200ms, 500ms).
        let delays = [0.05, 0.20, 0.50]
        if attempt < delays.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + delays[attempt - 1]) { [weak self] in
                self?.doRestartAttempt(reason: reason, attempt: attempt + 1)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.fullSessionReset(reason: reason)
            }
        }
    }

    private func fullSessionReset(reason: String) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("[Audio] session deactivate failed: \(error)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            do {
                try session.setActive(true, options: [])
                try self.setupOutputGraph()
                try self.avEngine.start()
                self.applyRoutingPreferences()
                print("[Audio] recovered via full session reset")
            } catch {
                print("[Audio] full session reset failed (\(reason)): \(error) — will retry on next route change")
            }
        }
    }

    /// Returns true if an external output device (USB / BT / wired headphones / lineOut / etc.)
    /// is currently in the route.
    private func hasExternalOutput() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { out in
            switch out.portType {
            case .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE,
                 .usbAudio, .lineOut, .airPlay, .carAudio, .HDMI, .displayPort:
                return true
            default:
                return false
            }
        }
    }

    /// Apply the user's output routing preference. Idempotent — only calls
    /// `overrideOutputAudioPort` if the desired override differs from what we last applied.
    /// Repeated override calls trigger spurious route-change notifications which trigger more
    /// reconfigs → infinite loop.
    func applyRoutingPreferences() {
        let desired: AVAudioSession.PortOverride
        if SettingsStore.forceSpeakerOutput {
            desired = .speaker
        } else if hasExternalOutput() {
            desired = .none
        } else {
            desired = .speaker
        }
        guard desired != appliedOverride else { return }
        do {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(desired)
            appliedOverride = desired
        } catch {
            print("[Audio] overrideOutputAudioPort(\(desired)) failed: \(error)")
        }
    }

    /// Apply the user's preferred input (mic) selection. Falls back to system default if the
    /// chosen device is no longer present (e.g., USB card unplugged) — but keeps the saved
    /// UID so the preference is re-applied automatically when the device is re-plugged.
    func applyPreferredInput() {
        let session = AVAudioSession.sharedInstance()
        guard let uid = SettingsStore.preferredInputUID else {
            // No preference — let iOS pick (will be built-in mic by default).
            try? session.setPreferredInput(nil)
            return
        }
        if let pref = session.availableInputs?.first(where: { $0.uid == uid }) {
            try? session.setPreferredInput(pref)
        } else {
            // Saved preference unavailable — silent fallback to system default.
            try? session.setPreferredInput(nil)
        }
    }

    /// List of inputs we can pick between in Settings.
    func availableInputs() -> [AVAudioSessionPortDescription] {
        AVAudioSession.sharedInstance().availableInputs ?? []
    }

    /// Currently active input (whatever iOS resolved to).
    func currentInput() -> AVAudioSessionPortDescription? {
        AVAudioSession.sharedInstance().currentRoute.inputs.first
    }

    /// Human-readable name of the active output (e.g. "Speaker", "USB Audio Device").
    func currentOutputName() -> String {
        AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "Default"
    }

    /// Live input monitoring (hear what the mic captures). Routed through the engine graph —
    /// no cross-thread copies → minimal latency (just the I/O round-trip).
    func setMonitorEnabled(_ on: Bool) {
        SettingsStore.monitorInput = on
        inputSilentSink?.outputVolume = on ? 1.0 : 0.0
    }

    /// Recalculate loop latency compensation using the engine's own measurements.
    ///
    /// `AVAudioIONode.presentationLatency` is the most accurate API — it includes the engine's
    /// internal processing on top of the raw HW I/O latency. We use this instead of
    /// `session.outputLatency / inputLatency`, which only counts the hardware buffer and tends
    /// to under-report by 10–20 ms.
    ///
    /// Compensation = inputPresentation + outputPresentation + tap_buffer + user_offset.
    func recalculateLoopLatency() {
        guard let lp = looper else { return }
        let session = AVAudioSession.sharedInstance()
        let inputPres = avEngine.inputNode.presentationLatency
        let outputPres = avEngine.outputNode.presentationLatency
        // Fallback to session values if presentationLatency is 0 (engine not started yet, or
        // node hasn't been activated for I/O).
        let inLat = inputPres > 0 ? inputPres : session.inputLatency
        let outLat = outputPres > 0 ? outputPres : session.outputLatency
        let tapDuration = Double(tapBufferSize) / Double(sampleRate)
        let total = outLat + inLat + tapDuration + SettingsStore.latencyOffsetMs / 1000.0
        let frames = Int(total * Double(sampleRate))
        lp.setLatencyComp(frames: max(0, frames))
        #if DEBUG
        print(String(format: "[Audio] latency: out=%.1fms in=%.1fms tap=%.1fms offset=%.1fms → comp=%d frames (sessionOut=%.1f sessionIn=%.1f)",
                     outLat * 1000, inLat * 1000, tapDuration * 1000,
                     SettingsStore.latencyOffsetMs, frames,
                     session.outputLatency * 1000, session.inputLatency * 1000))
        #endif
    }

    /// Smaller tap buffer = less recording delay. 256 frames @ 48 kHz = 5.3 ms (was 512 = 10.7 ms).
    private let tapBufferSize: AVAudioFrameCount = 256

    /// Engine reconfigured itself (route change with format change, e.g. USB sound card).
    /// Debounced (150ms coalesce). Cooldown-guarded against our own restart's settling notifications.
    /// Loop-detected so an unstable iOS configuration can't thrash forever.
    @objc private func handleEngineConfigChange(_ notification: Notification) {
        if isReconfiguring { return }
        // Cooldown — ignore notifications that arrive while we're still "settling" from our last restart.
        if Date().timeIntervalSince(lastReconfigCompletedAt) < reconfigCooldown {
            return
        }
        pendingReconfig?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.isReconfiguring = true
            self.performReconfig()
            self.lastReconfigCompletedAt = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.isReconfiguring = false
            }
        }
        pendingReconfig = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// Loop detector — break out if reconfigs are firing way too fast (>5 in 3s) even after
    /// our cooldown. Does NOT clear user preferences; just skips this one rebuild so iOS settles.
    private func detectReconfigLoop() -> Bool {
        let now = Date()
        reconfigTimestamps.append(now)
        reconfigTimestamps.removeAll { now.timeIntervalSince($0) > 3 }
        if reconfigTimestamps.count > 5 {
            print("[Audio] reconfig loop detected (\(reconfigTimestamps.count) in 3s) — skipping this rebuild")
            reconfigTimestamps.removeAll()
            return true
        }
        return false
    }

    /// Rebuild the entire graph (output path + input tap if needed) in a SINGLE stop/start cycle.
    /// Two separate restarts would each trigger their own config-change notification, causing a loop.
    private func performReconfig() {
        if detectReconfigLoop() { return }
        print("[Audio] performing graph rebuild")
        let hadInputTap = inputTapInstalled

        // Cleanup old graph state.
        avEngine.inputNode.removeTap(onBus: 0)
        inputTapInstalled = false
        if let sink = inputSilentSink, avEngine.attachedNodes.contains(sink) {
            avEngine.detach(sink)
        }
        inputSilentSink = nil
        inputConverter = nil
        inputConverterSourceFormat = nil

        if avEngine.isRunning { avEngine.stop() }

        do {
            try setupOutputGraph()
            if hadInputTap {
                try wireInputTap()       // builds silent sink + installs tap, engine still stopped
            }
            try avEngine.start()
            applyRoutingPreferences()
        } catch {
            print("[Audio] reconfig start failed: \(error) — will retry asynchronously")
            attemptEngineRestart(reason: "reconfig fallback")
        }
    }

    func allNotesOff() {
        os_unfair_lock_lock(&voiceLock)
        defer { os_unfair_lock_unlock(&voiceLock) }
        for v in voices {
            v.sample = nil
            v.frameIndex = 0
        }
    }

    // MARK: - Pads & samples

    func setPadSamples(pad: Int, samples: [AudioSample]) {
        guard pad >= 0 && pad < AudioConstants.numPads else { return }
        let limited = Array(samples.prefix(AudioConstants.maxPadLayers))
        os_unfair_lock_lock(&padConfigLock)
        padSamples[pad] = limited
        padLastVariant[pad] = -1
        os_unfair_lock_unlock(&padConfigLock)
    }

    func clearPad(pad: Int) {
        guard pad >= 0 && pad < AudioConstants.numPads else { return }
        os_unfair_lock_lock(&padConfigLock)
        padSamples[pad].removeAll()
        padLastVariant[pad] = -1
        os_unfair_lock_unlock(&padConfigLock)
    }

    func padHasSample(_ pad: Int) -> Bool {
        os_unfair_lock_lock(&padConfigLock)
        defer { os_unfair_lock_unlock(&padConfigLock) }
        return !padSamples[pad].isEmpty
    }

    func setPadVolume(pad: Int, volume: Float) {
        guard pad >= 0 && pad < AudioConstants.numPads else { return }
        padVolumes[pad] = max(0, min(1, volume))
    }

    /// xorshift32 — same algorithm as the Android engine.
    private func nextRandom() -> UInt32 {
        var s = rngState
        s ^= s << 13
        s ^= s >> 17
        s ^= s << 5
        rngState = s
        return s
    }

    func triggerPad(_ pad: Int, velocity: Float = 1.0) {
        guard pad >= 0 && pad < AudioConstants.numPads else { return }
        let v = max(0, min(1, velocity))

        // Pick variant.
        os_unfair_lock_lock(&padConfigLock)
        let samples = padSamples[pad]
        var lastIdx = padLastVariant[pad]
        os_unfair_lock_unlock(&padConfigLock)
        guard !samples.isEmpty else { return }
        let pick: Int
        if samples.count == 1 {
            pick = 0
        } else {
            var n = Int(nextRandom() % UInt32(samples.count))
            if n == lastIdx { n = (n + 1) % samples.count }
            pick = n
            lastIdx = n
            os_unfair_lock_lock(&padConfigLock)
            padLastVariant[pad] = lastIdx
            os_unfair_lock_unlock(&padConfigLock)
        }
        let sample = samples[pick]
        let gain = v * padVolumes[pad]

        // Choke pair (close-hat <-> open-hat).
        os_unfair_lock_lock(&voiceLock)
        if pad == AudioConstants.padCloseHat {
            for vv in voices where vv.padIndex == AudioConstants.padOpenHat { vv.sample = nil }
        } else if pad == AudioConstants.padOpenHat {
            for vv in voices where vv.padIndex == AudioConstants.padCloseHat { vv.sample = nil }
        }
        // Find a free voice.
        for vv in voices where vv.sample == nil {
            vv.sample = sample
            vv.frameIndex = 0
            vv.gain = gain
            vv.padIndex = pad
            os_unfair_lock_unlock(&voiceLock)
            return
        }
        os_unfair_lock_unlock(&voiceLock)
        // No free voice — drop.
    }

    // MARK: - Render

    private func render(frameCount: Int, bufferList: UnsafeMutablePointer<AudioBufferList>) {
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        guard abl.count >= 2 else { return }
        let leftPtr = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let rightPtr = abl[1].mData!.assumingMemoryBound(to: Float.self)
        // Clear.
        for n in 0..<frameCount { leftPtr[n] = 0; rightPtr[n] = 0 }

        // Voices (mono samples → both channels equally).
        os_unfair_lock_lock(&voiceLock)
        for v in voices {
            guard let s = v.sample else { continue }
            let data = s.data
            var idx = v.frameIndex
            let g = v.gain
            for n in 0..<frameCount {
                if idx >= s.frameCount {
                    v.sample = nil
                    break
                }
                let x = data[idx] * g
                leftPtr[n] += x
                rightPtr[n] += x
                idx += 1
            }
            v.frameIndex = idx
        }
        os_unfair_lock_unlock(&voiceLock)

        // Looper.
        if let lp = looper {
            lp.mixInto(left: leftPtr, right: rightPtr, frameCount: frameCount)
        }

        // Master EQ.
        masterEq.processStereo(leftPtr, rightPtr, frameCount: frameCount)

        // Multiband compressor.
        compressor.processStereo(leftPtr, rightPtr, frameCount: frameCount)

        // Soft clip.
        for n in 0..<frameCount {
            leftPtr[n] = tanhf(leftPtr[n])
            rightPtr[n] = tanhf(rightPtr[n])
        }
    }

    // MARK: - Looper input

    private var inputTapInstalled = false
    private var inputConverter: AVAudioConverter?
    private var inputConverterSourceFormat: AVAudioFormat?
    private var inputMonoFormat: AVAudioFormat?

    /// Build the input → silent mixer → main mixer path and install the tap.
    /// Caller must ensure engine is stopped; does NOT start the engine.
    /// The silent mixer keeps the input bus active so its HW format negotiates correctly
    /// (an unwired input node reports 0 Hz / 0 ch and crashes installTap).
    private func wireInputTap() throws {
        guard !inputTapInstalled else { return }

        inputMonoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                        sampleRate: Double(sampleRate),
                                        channels: 1,
                                        interleaved: false)

        let inputNode = avEngine.inputNode
        inputNode.removeTap(onBus: 0)   // defensive — never install on top of an existing tap

        if inputSilentSink == nil {
            let sink = AVAudioMixerNode()
            avEngine.attach(sink)
            // Initial volume reflects the user's monitor preference. 0 = silent (mic only fills
            // the buffer for the tap to read); 1 = audible passthrough (live monitor).
            sink.outputVolume = SettingsStore.monitorInput ? 1.0 : 0.0
            let downstreamFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                 sampleRate: Double(sampleRate),
                                                 channels: 2,
                                                 interleaved: false)
            avEngine.connect(sink, to: avEngine.mainMixerNode, format: downstreamFormat)
            avEngine.connect(inputNode, to: sink, format: nil)
            inputSilentSink = sink
        }

        // Smaller bufferSize → shorter recording-tap latency. 256 @ 48 kHz = 5.3 ms.
        inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: nil) { [weak self] buffer, _ in
            guard let self = self, let lp = self.looper else { return }
            self.handleInputBuffer(buffer, into: lp)
        }
        inputTapInstalled = true
    }

    /// Public entry: prepare the looper to record. Stops engine, wires input tap, restarts.
    func looperStartInput() throws {
        if inputTapInstalled { return }
        let wasRunning = avEngine.isRunning
        if wasRunning { avEngine.stop() }
        try wireInputTap()
        // Reassert source-node connection in case it got dropped.
        if let src = sourceNode, let fmt = inputBusFormat {
            if avEngine.attachedNodes.contains(src) {
                avEngine.disconnectNodeOutput(src)
            } else {
                avEngine.attach(src)
            }
            avEngine.connect(src, to: avEngine.mainMixerNode, format: fmt)
        }
        if wasRunning {
            do { try avEngine.start() }
            catch { print("[Audio] start after wireInputTap failed: \(error)") }
            applyRoutingPreferences()
        }
        recalculateLoopLatency()
        // Mark this as "our own" so the resulting config-change notification gets skipped.
        lastReconfigCompletedAt = Date()
        print("[Audio] input tap installed — current=\(currentInput()?.portName ?? "—")")
    }

    /// Convert the input buffer to mono float32 at the session SR and pump it into the looper.
    /// Cached converter is rebuilt if/when the input format changes (e.g. BT headset reconnect).
    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer, into lp: Looper) {
        let sourceFormat = buffer.format

        #if DEBUG
        // One-time peak diagnostic so we can verify the input is actually delivering audio.
        if let ptr = buffer.floatChannelData?[0] {
            var peak: Float = 0
            for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(ptr[i])) }
            tapDiagnostic.observe(peak: peak, state: lp.state)
        }
        #endif

        // Fast path — already mono float32 non-interleaved at the right sample rate.
        if sourceFormat.commonFormat == .pcmFormatFloat32 &&
           sourceFormat.channelCount == 1 &&
           !sourceFormat.isInterleaved &&
           sourceFormat.sampleRate == Double(sampleRate) {
            if let ptr = buffer.floatChannelData?[0] {
                let bp = UnsafeBufferPointer(start: ptr, count: Int(buffer.frameLength))
                lp.appendInput(bp)
            }
            return
        }

        // (Re)build the converter lazily when source format changes.
        if inputConverterSourceFormat != sourceFormat {
            if let mono = inputMonoFormat {
                let conv = AVAudioConverter(from: sourceFormat, to: mono)
                // Low-latency: no priming, no silence padding.
                conv?.primeMethod = .none
                inputConverter = conv
                inputConverterSourceFormat = sourceFormat
                #if DEBUG
                print("[Audio] converter rebuilt: \(sourceFormat) → \(mono)")
                #endif
            }
        }
        guard let mono = inputMonoFormat,
              let conv = inputConverter else {
            #if DEBUG
            print("[Audio] no converter or mono format — dropping \(buffer.frameLength) input frames")
            #endif
            return
        }

        // Output capacity must accommodate sample-rate up-conversion.
        let ratio = mono.sampleRate / max(sourceFormat.sampleRate, 1)
        let outCap = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: outCap) else { return }

        var err: NSError?
        var supplied = false
        let status = conv.convert(to: outBuf, error: &err) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }

        if let err = err {
            #if DEBUG
            print("[Audio] converter error: \(err)")
            #endif
            return
        }
        // Even with success status, frameLength may be 0 (e.g., still priming) — log if so.
        if outBuf.frameLength == 0 {
            #if DEBUG
            converterEmptyCount += 1
            if converterEmptyCount % 10 == 0 {
                print("[Audio] converter produced 0 frames \(converterEmptyCount) times — status=\(status.rawValue), input had \(buffer.frameLength) frames")
            }
            #endif
            return
        }

        if let ptr = outBuf.floatChannelData?[0] {
            let bp = UnsafeBufferPointer(start: ptr, count: Int(outBuf.frameLength))
            lp.appendInput(bp)
        }
    }

    #if DEBUG
    private var converterEmptyCount: Int = 0
    #endif
}

#if DEBUG
/// Periodic console summary of input-tap activity so we can verify the mic is delivering
/// audio. Logs once every ~2 seconds while the looper is in recording-related states.
final class TapDiagnostic {
    private var bufferCount: Int = 0
    private var peakSinceLastLog: Float = 0
    private var lastLog = Date.distantPast

    func observe(peak: Float, state: LooperState) {
        bufferCount += 1
        if peak > peakSinceLastLog { peakSinceLastLog = peak }
        if Date().timeIntervalSince(lastLog) > 2 {
            let isRec = state == .recording || state == .endArmed
            print("[Audio] input tap: \(bufferCount) buffers · peak=\(String(format: "%.4f", peakSinceLastLog)) · state=\(state)\(isRec ? " (RECORDING)" : "")")
            bufferCount = 0
            peakSinceLastLog = 0
            lastLog = Date()
        }
    }
}
#endif
