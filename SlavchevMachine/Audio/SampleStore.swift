import Foundation
import AVFoundation

/// Decoded sample. Mono — looper and voice mixer assume mono. Stereo samples are summed to mono on load.
final class AudioSample {
    let data: [Float]          // mono float32, length == frameCount
    let sampleRate: Double
    let frameCount: Int

    init(data: [Float], sampleRate: Double) {
        self.data = data
        self.sampleRate = sampleRate
        self.frameCount = data.count
    }
}

final class SampleStore {
    private let lock = NSLock()
    private var samples: [Int: AudioSample] = [:]
    private var nextId: Int = 1

    @discardableResult
    func insert(_ sample: AudioSample) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let id = nextId
        nextId += 1
        samples[id] = sample
        return id
    }

    /// Audio-thread safe: dictionary reads are read-only after publication.
    /// We hold a strong reference outside the audio thread so the sample can't be deallocated mid-callback.
    func get(_ id: Int) -> AudioSample? {
        lock.lock()
        defer { lock.unlock() }
        return samples[id]
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        samples.removeAll()
    }
}
