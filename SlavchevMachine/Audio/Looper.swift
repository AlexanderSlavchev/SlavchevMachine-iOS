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

    let sampleRate: Float
    let eq = ParametricEqualizer()

    // Allocated once, never reallocated.
    private var buffer: [Float]
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
    private var inputPeakValue: Float = 0
    private var scratch: [Float] = []

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        self.bufferCapacity = Int(sampleRate) * Looper.maxSeconds
        self.buffer = Array(repeating: 0, count: bufferCapacity)
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
        if peak > inputPeakValue { inputPeakValue = peak }

        // Capture into the loop buffer only when in a recording state.
        let s = LooperState(rawValue: Int(stateRaw)) ?? .empty
        guard s == .recording || s == .endArmed else { return }
        var pos = recordLen
        for i in 0..<samples.count {
            if pos >= bufferCapacity { break }
            buffer[pos] = samples[i] * inputGainLin
            pos += 1
        }
        recordLen = pos
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
        var mixedPeak: Float = 0
        scratch.withUnsafeMutableBufferPointer { sp in
            for n in 0..<frameCount {
                let read = (playPos + lat) % loopFrames
                sp[n] = buffer[read]
                playPos += 1
                if playPos >= loopFrames { playPos = 0 }
            }
            eq.process(sp.baseAddress!, frameCount: frameCount)
            let gain = outputGainLin
            for n in 0..<frameCount {
                let v = sp[n] * gain
                left[n] += v
                right[n] += v
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

    /// Snapshot and reset peak for UI metering.
    func consumePeak() -> Float {
        let p = inputPeakValue
        inputPeakValue = 0
        return p
    }

    // MARK: - Gains, EQ, latency

    func setInputGain(db: Float) { inputGainLin = powf(10, db / 20) }
    func setOutputGain(db: Float) { outputGainLin = powf(10, db / 20) }
    func setEqBand(_ index: Int, _ config: EqBandConfig) { eq.setBand(index, config) }
    func setLatencyComp(frames: Int) {
        latencyCompFrames = max(0, min(frames, Int(sampleRate) / 2))
    }

    // MARK: - Scene import/export

    func exportPcm() -> [Float] {
        let n = loopFrames
        if n <= 0 { return [] }
        return Array(buffer[0..<n])
    }

    func importLoop(pcm: [Float], barOffsets: [Int], latencyComp: Int) {
        os_unfair_lock_lock(&transitionLock)
        defer { os_unfair_lock_unlock(&transitionLock) }
        let n = min(pcm.count, bufferCapacity)
        for i in 0..<n { buffer[i] = pcm[i] }
        for i in n..<bufferCapacity { buffer[i] = 0 }
        loopFrames = n
        recordLen = n
        self.barOffsets = barOffsets
        latencyCompFrames = max(0, min(latencyComp, Int(sampleRate) / 2))
        playPos = 0
        barsSincePlay = 0
        snapTarget = -1
        stateRaw = LooperState.stopped.rawValue
    }
}
