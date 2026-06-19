import Foundation
import os.lock

enum LooperState: Int {
    case empty = 0
    case armed = 1
    case recording = 2
    case endArmed = 3
    case playing = 4
    case stopped = 5
    case playArmed = 6

    var label: String {
        switch self {
        case .empty: return "LOOP"
        case .armed: return "ARM"
        case .recording: return "REC"
        case .endArmed: return "END"
        case .playing: return "LOOP"
        case .stopped: return "STOP"
        case .playArmed: return "CUE"
        }
    }
}

final class Looper {
    static let maxSeconds = 60
    /// Max simultaneously-recorded input tracks. Buffers are pre-allocated for all of them
    /// (RT-safe — never reallocated on the audio path).
    static let maxTracks = 4

    let sampleRate: Float
    let eq = ParametricEqualizer()

    // Allocated once, never reallocated. One buffer per track; all tracks share the timeline.
    private var buffers: [[Float]]
    private var bufferCapacity: Int

    // Mutated by ticker / UI thread under transitionLock; read on audio thread.
    private var transitionLock = os_unfair_lock_s()

    // Atomics-ish; we treat them as plain `var`s and pair with transitionLock for non-audio reads/writes.
    // Audio thread reads stateRaw, recordLen, playPos, loopFrames, snapTarget directly.
    private var stateRaw: Int = LooperState.empty.rawValue
    private var recordLen: Int = 0
    private var loopFrames: Int = 0
    private var playPos: Int = 0
    private var barsSincePlay: Int = 0
    private var snapTarget: Int = -1
    private var endIntoStopped: Bool = false
    private(set) var barOffsets: [Int] = []
    private(set) var latencyCompFrames: Int = 0
    private var inputGainLin: Float = 1
    private var outputGainLin: Float = 1
    // Per-track input peak meters. Read/reset by the UI poll.
    private var inputPeaks: [Float]
    // How many tracks are in use (routing). Read lock-free on the audio thread.
    private var activeTracks: Int = 1
    // Per-track mute. Read lock-free on the audio thread; affects an already-recorded loop live.
    private var trackMuted: [Bool]
    private var scratch: [Float] = []

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        let capacity = Int(sampleRate) * Looper.maxSeconds
        self.bufferCapacity = capacity
        self.buffers = (0..<Looper.maxTracks).map { _ in Array(repeating: 0, count: capacity) }
        self.inputPeaks = Array(repeating: 0, count: Looper.maxTracks)
        self.trackMuted = Array(repeating: false, count: Looper.maxTracks)
        eq.setSampleRate(sampleRate)
    }

    var state: LooperState { LooperState(rawValue: Int(stateRaw)) ?? .empty }

    /// User-thread tap. Advances the state machine.
    func tap() {
        os_unfair_lock_lock(&transitionLock)
        defer { os_unfair_lock_unlock(&transitionLock) }
        let s = LooperState(rawValue: Int(stateRaw)) ?? .empty
        switch s {
        case .empty:      stateRaw = LooperState.armed.rawValue
        case .armed:      stateRaw = LooperState.empty.rawValue
        case .recording:  endIntoStopped = false; stateRaw = LooperState.endArmed.rawValue
        case .endArmed:   stateRaw = LooperState.recording.rawValue
        case .playing:    stateRaw = LooperState.stopped.rawValue
        case .stopped:    stateRaw = LooperState.playArmed.rawValue
        case .playArmed:  stateRaw = LooperState.stopped.rawValue
        }
    }

    /// Dedicated STOP — see spec §11.2.
    func stopAction() {
        os_unfair_lock_lock(&transitionLock)
        defer { os_unfair_lock_unlock(&transitionLock) }
        let s = LooperState(rawValue: Int(stateRaw)) ?? .empty
        switch s {
        case .playing, .playArmed:
            stateRaw = LooperState.stopped.rawValue
        case .recording:
            endIntoStopped = true
            stateRaw = LooperState.endArmed.rawValue
        case .endArmed:
            endIntoStopped = true
        default: break
        }
    }

    /// User-thread CLEAR.
    func clear() {
        os_unfair_lock_lock(&transitionLock)
        defer { os_unfair_lock_unlock(&transitionLock) }
        stateRaw = LooperState.empty.rawValue
        recordLen = 0
        loopFrames = 0
        playPos = 0
        barsSincePlay = 0
        snapTarget = -1
        endIntoStopped = false
        barOffsets.removeAll()
    }

    /// Ticker callback — called at bar boundaries.
    func onBar() {
        os_unfair_lock_lock(&transitionLock)
        defer { os_unfair_lock_unlock(&transitionLock) }
        let s = LooperState(rawValue: Int(stateRaw)) ?? .empty
        switch s {
        case .armed:
            recordLen = 0
            barOffsets = [0]
            stateRaw = LooperState.recording.rawValue
        case .recording:
            barOffsets.append(recordLen)
        case .endArmed:
            finalizeLoop()
        case .playArmed:
            playPos = 0
            barsSincePlay = 0
            snapTarget = -1
            stateRaw = LooperState.playing.rawValue
        case .playing:
            barsSincePlay += 1
            if !barOffsets.isEmpty {
                let b = barsSincePlay % barOffsets.count
                snapTarget = barOffsets[b]
            }
        default: break
        }
    }

    private func finalizeLoop() {
        loopFrames = recordLen
        if loopFrames > bufferCapacity { loopFrames = bufferCapacity }
        playPos = 0
        barsSincePlay = 0
        snapTarget = -1
        stateRaw = endIntoStopped ? LooperState.stopped.rawValue : LooperState.playing.rawValue
        endIntoStopped = false
    }

    // MARK: - Audio I/O

    /// Called by the input tap with float mono frames. Always updates input peak meter (so
    /// the user can see signal level even before pressing record). Writes to the buffer only
    /// when in recording / endArmed state. Publishes the buffer for live monitoring if enabled.
    func appendInput(_ samples: UnsafeBufferPointer<Float>) {
        // Always update the peak meter so user can verify input is alive.
        var peak: Float = 0
        for i in 0..<samples.count {
            let a = abs(samples[i] * inputGainLin)
            if a > peak { peak = a }
        }
        if peak > inputPeaks[0] { inputPeaks[0] = peak }

        // Capture into the loop buffer only when in a recording state.
        let s = LooperState(rawValue: Int(stateRaw)) ?? .empty
        guard s == .recording || s == .endArmed else { return }
        var pos = recordLen
        for i in 0..<samples.count {
            if pos >= bufferCapacity { break }
            buffers[0][pos] = samples[i] * inputGainLin
            pos += 1
        }
        recordLen = pos
    }

    /// Multi-track input: `tracks[i]` is the already-mapped channel for track i. All tracks share
    /// one timeline so `recordLen` advances once. Lengths are assumed equal (same tap buffer).
    func appendInput(tracks: [UnsafeBufferPointer<Float>]) {
        let count = min(tracks.count, activeTracks)
        guard count > 0 else { return }
        let g = inputGainLin
        for t in 0..<count {
            let src = tracks[t]
            var peak: Float = 0
            for i in 0..<src.count {
                let a = abs(src[i] * g)
                if a > peak { peak = a }
            }
            if peak > inputPeaks[t] { inputPeaks[t] = peak }
        }
        let s = LooperState(rawValue: Int(stateRaw)) ?? .empty
        guard s == .recording || s == .endArmed else { return }
        let frames = tracks[0].count
        let start = recordLen
        for t in 0..<count {
            let src = tracks[t]
            let m = min(src.count, frames)
            var pos = start
            var i = 0
            while i < m && pos < bufferCapacity {
                buffers[t][pos] = src[i] * g
                pos += 1
                i += 1
            }
        }
        recordLen = min(start + frames, bufferCapacity)
    }

    /// Called by the audio render callback. Mixes mono loop into stereo `out`, applies output gain and EQ.
    /// Also (when DEBUG) tracks the mixed peak so a separate diagnostic can confirm playback audibility.
    /// Note: live monitoring is NOT done here — it's routed through the engine's input → mixer → main
    /// path with volume control (see AudioEngine.setMonitorEnabled). That keeps the monitor in the
    /// engine's optimised render pipeline (no cross-thread copies → much lower latency).
    func mixInto(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frameCount: Int) {
        let s = LooperState(rawValue: Int(stateRaw)) ?? .empty
        guard s == .playing, loopFrames > 0 else { return }
        if scratch.count < frameCount {
            scratch = Array(repeating: 0, count: frameCount)
        }
        // Consume snap target.
        let snap = snapTarget
        if snap >= 0 {
            playPos = snap
            snapTarget = -1
        }
        let lat = latencyCompFrames
        let n = activeTracks
        var mixedPeak: Float = 0
        scratch.withUnsafeMutableBufferPointer { sp in
            for k in 0..<frameCount {
                let read = (playPos + lat) % loopFrames
                var acc: Float = 0
                for t in 0..<n where !trackMuted[t] {
                    acc += buffers[t][read]
                }
                sp[k] = acc
                playPos += 1
                if playPos >= loopFrames { playPos = 0 }
            }
            eq.process(sp.baseAddress!, frameCount: frameCount)
            let gain = outputGainLin
            for k in 0..<frameCount {
                let v = sp[k] * gain
                left[k] += v
                right[k] += v
                if abs(v) > mixedPeak { mixedPeak = abs(v) }
            }
        }
        #if DEBUG
        playbackPeakValue = max(playbackPeakValue, mixedPeak)
        #endif
    }

    #if DEBUG
    /// Atomic-ish read for the playback diagnostic (UI poll).
    func consumePlaybackPeak() -> Float {
        let p = playbackPeakValue
        playbackPeakValue = 0
        return p
    }
    private var playbackPeakValue: Float = 0
    #endif

    // Live monitoring is handled by AudioEngine via the input → mixer → main-mixer path —
    // not by Looper. (See AudioEngine.setMonitorEnabled.)

    /// Snapshot and reset peak for UI metering — max across active tracks.
    func consumePeak() -> Float {
        var p: Float = 0
        for t in 0..<activeTracks {
            if inputPeaks[t] > p { p = inputPeaks[t] }
            inputPeaks[t] = 0
        }
        return p
    }

    /// Per-track peak snapshot (for per-input meters).
    func consumePeak(track: Int) -> Float {
        guard track >= 0 && track < Looper.maxTracks else { return 0 }
        let p = inputPeaks[track]
        inputPeaks[track] = 0
        return p
    }

    // MARK: - Tracks & mute

    var trackCount: Int { activeTracks }

    /// Number of input tracks recorded simultaneously (routing). Clamped to 1...maxTracks.
    func setActiveTracks(_ n: Int) {
        os_unfair_lock_lock(&transitionLock)
        activeTracks = max(1, min(Looper.maxTracks, n))
        os_unfair_lock_unlock(&transitionLock)
    }

    /// Mute affects an already-recorded loop in real time (skipped at mix).
    func setMuted(track: Int, _ on: Bool) {
        guard track >= 0 && track < Looper.maxTracks else { return }
        trackMuted[track] = on
    }

    func isMuted(track: Int) -> Bool {
        guard track >= 0 && track < Looper.maxTracks else { return false }
        return trackMuted[track]
    }

    // MARK: - Gains, EQ, latency

    func setInputGain(db: Float) { inputGainLin = powf(10, db / 20) }
    func setOutputGain(db: Float) { outputGainLin = powf(10, db / 20) }
    func setEqBand(_ index: Int, _ config: EqBandConfig) { eq.setBand(index, config) }
    func setLatencyComp(frames: Int) {
        latencyCompFrames = max(0, min(frames, Int(sampleRate) / 2))
    }

    // MARK: - Scene import/export

    /// Export each active track's PCM (length = loopFrames). Empty if nothing recorded.
    func exportTracks() -> [[Float]] {
        let n = loopFrames
        if n <= 0 { return [] }
        var out: [[Float]] = []
        out.reserveCapacity(activeTracks)
        for t in 0..<activeTracks {
            out.append(Array(buffers[t][0..<n]))
        }
        return out
    }

    /// Restore a multi-track loop. `pcms` holds one array per track; `muted` restores mute state.
    func importTracks(pcms: [[Float]], barOffsets: [Int], latencyComp: Int, muted: [Bool]) {
        os_unfair_lock_lock(&transitionLock)
        defer { os_unfair_lock_unlock(&transitionLock) }
        let count = max(1, min(Looper.maxTracks, pcms.count))
        var maxLen = 0
        for t in 0..<count {
            let pcm = pcms[t]
            let n = min(pcm.count, bufferCapacity)
            for i in 0..<n { buffers[t][i] = pcm[i] }
            for i in n..<bufferCapacity { buffers[t][i] = 0 }
            if n > maxLen { maxLen = n }
        }
        activeTracks = count
        for t in 0..<Looper.maxTracks {
            trackMuted[t] = t < muted.count ? muted[t] : false
        }
        loopFrames = maxLen
        recordLen = maxLen
        self.barOffsets = barOffsets
        latencyCompFrames = max(0, min(latencyComp, Int(sampleRate) / 2))
        playPos = 0
        barsSincePlay = 0
        snapTarget = -1
        stateRaw = LooperState.stopped.rawValue
    }
}
