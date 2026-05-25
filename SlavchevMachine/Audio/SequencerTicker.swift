import Foundation

/// Drives the step sequencer. Uses an absolute-time scheduling loop on a dedicated thread to avoid `delay()`-style drift.
final class SequencerTicker {
    var bpm: Float = 120
    var stepCount: Int = 16
    var humanize: Bool = false

    var onStep: ((Int) -> Void)?
    var onBar: (() -> Void)?

    private(set) var isRunning = false
    private(set) var currentStep: Int = -1
    private var thread: Thread?
    private var stopFlag = false
    private var lock = NSLock()

    func start() {
        lock.lock(); defer { lock.unlock() }
        if isRunning { return }
        isRunning = true
        stopFlag = false
        currentStep = -1
        let t = Thread { [weak self] in self?.run() }
        t.name = "sm.ticker"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        stopFlag = true
        isRunning = false
    }

    private func run() {
        // Absolute-time loop. Each step targets a future host time.
        let mach = MachTimebase()
        var nextNs: UInt64 = mach.nowNanos()
        while !stopFlag {
            let stepNs = UInt64(60_000_000_000.0 / Double(max(bpm, 1)) / 4.0)
            nextNs &+= stepNs
            var sleepNs = Int64(nextNs) - Int64(mach.nowNanos())
            if sleepNs < 0 { sleepNs = 0; nextNs = mach.nowNanos() }
            if humanize {
                let jitter = UInt64.random(in: 0..<12_000_000) // 0–12 ms
                Thread.sleep(forTimeInterval: TimeInterval(sleepNs) / 1_000_000_000.0 + TimeInterval(jitter) / 1_000_000_000.0)
            } else {
                Thread.sleep(forTimeInterval: TimeInterval(sleepNs) / 1_000_000_000.0)
            }
            if stopFlag { break }
            let next = (currentStep + 1) % max(stepCount, 1)
            currentStep = next
            onStep?(next)
            if next == 0 { onBar?() }
        }
    }
}

private struct MachTimebase {
    let numer: UInt64
    let denom: UInt64
    init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        numer = UInt64(info.numer)
        denom = UInt64(info.denom)
    }
    func nowNanos() -> UInt64 {
        mach_absolute_time() &* numer / denom
    }
}
