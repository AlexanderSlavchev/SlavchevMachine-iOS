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

    private init() {}

    // MARK: - Lifecycle

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord,
                                mode: .measurement,
                                options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
        try session.setPreferredSampleRate(48000)
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true, options: [])

        sampleRate = Float(session.sampleRate)
        masterEq.setSampleRate(sampleRate)
        compressor.setSampleRate(sampleRate)
        looper = Looper(sampleRate: sampleRate)

        let outFormat = avEngine.outputNode.inputFormat(forBus: 0)
        inputBusFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                       sampleRate: outFormat.sampleRate,
                                       channels: 2,
                                       interleaved: false)

        sourceNode = AVAudioSourceNode(format: inputBusFormat) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            self.render(frameCount: Int(frameCount), bufferList: audioBufferList)
            return noErr
        }
        avEngine.attach(sourceNode)
        avEngine.connect(sourceNode, to: avEngine.mainMixerNode, format: inputBusFormat)
        try avEngine.start()
    }

    func stop() {
        avEngine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
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

    func looperStartInput() throws {
        guard !inputTapInstalled else { return }
        let inputNode = avEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let hwSampleRate = inputFormat.sampleRate

        guard let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: hwSampleRate,
                                             channels: 1,
                                             interleaved: false) else { return }
        let needConverter = inputFormat.channelCount > 1
        let converter = needConverter ? AVAudioConverter(from: inputFormat, to: monoFormat) : nil

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, let lp = self.looper else { return }
            if let converter = converter {
                guard let outBuf = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: buffer.frameCapacity) else { return }
                var err: NSError?
                var supplied = false
                converter.convert(to: outBuf, error: &err) { _, status in
                    if supplied { status.pointee = .endOfStream; return nil }
                    supplied = true
                    status.pointee = .haveData
                    return buffer
                }
                if err == nil, let ptr = outBuf.floatChannelData?[0] {
                    let bp = UnsafeBufferPointer(start: ptr, count: Int(outBuf.frameLength))
                    lp.appendInput(bp)
                }
            } else if let ptr = buffer.floatChannelData?[0] {
                let bp = UnsafeBufferPointer(start: ptr, count: Int(buffer.frameLength))
                lp.appendInput(bp)
            }
        }
        inputTapInstalled = true
        // Latency comp = round-trip in frames.
        let lat = AVAudioSession.sharedInstance().outputLatency + AVAudioSession.sharedInstance().inputLatency
        looper.setLatencyComp(frames: Int(lat * Double(sampleRate)))
    }
}
