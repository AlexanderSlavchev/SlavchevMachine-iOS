import Foundation

/// 4-band multiband compressor. Linkwitz-Riley 24 dB/oct crossovers (two cascaded Butterworth low-passes), subtractive split.
final class MultibandCompressor {
    static let bandCount = 4
    static let crossoverCount = 3

    struct BandParams {
        var thresholdDb: Float = -24
        var rangeDb: Float = -6
        var attackMs: Float = 15
        var releaseMs: Float = 120
        var makeupDb: Float = 0
        var solo: Bool = false
        var bypass: Bool = false
    }

    private(set) var enabled: Bool = true
    private(set) var outputGainDb: Float = 0
    private(set) var crossoverHz: [Float] = [120, 800, 5000]
    private(set) var bands: [BandParams] = (0..<MultibandCompressor.bandCount).map { _ in BandParams() }

    private var sampleRate: Float = 48000

    private var lp1L = [BiquadState](repeating: BiquadState(), count: crossoverCount)
    private var lp1R = [BiquadState](repeating: BiquadState(), count: crossoverCount)
    private var lp2L = [BiquadState](repeating: BiquadState(), count: crossoverCount)
    private var lp2R = [BiquadState](repeating: BiquadState(), count: crossoverCount)
    private var lpCoeffs = [BiquadCoeffs](repeating: BiquadCoeffs(), count: crossoverCount)

    private var envelope: [Float] = Array(repeating: 0, count: bandCount)
    private var attackCoeff: [Float] = Array(repeating: 0, count: bandCount)
    private var releaseCoeff: [Float] = Array(repeating: 0, count: bandCount)
    private var makeupLin: [Float] = Array(repeating: 1, count: bandCount)
    private(set) var gainReductionDb: [Float] = Array(repeating: 0, count: bandCount)

    private var scratchLowL: [Float] = []
    private var scratchLowR: [Float] = []
    private var scratchHighL: [Float] = []
    private var scratchHighR: [Float] = []
    private var bandsL: [[Float]] = Array(repeating: [], count: bandCount)
    private var bandsR: [[Float]] = Array(repeating: [], count: bandCount)

    init() {
        recalcCrossovers()
        for i in 0..<Self.bandCount { recalcBand(i) }
    }

    func setEnabled(_ on: Bool) { enabled = on }
    func setOutputGain(db: Float) { outputGainDb = db }

    func setCrossover(_ index: Int, hz: Float) {
        crossoverHz[index] = hz
        recalcCrossovers()
    }

    func setBand(_ i: Int, threshold db: Float) { bands[i].thresholdDb = db }
    func setBand(_ i: Int, range db: Float) { bands[i].rangeDb = db }
    func setBand(_ i: Int, attack ms: Float) { bands[i].attackMs = ms; recalcBand(i) }
    func setBand(_ i: Int, release ms: Float) { bands[i].releaseMs = ms; recalcBand(i) }
    func setBand(_ i: Int, makeup db: Float) { bands[i].makeupDb = db; makeupLin[i] = powf(10, db / 20) }
    func setBand(_ i: Int, solo: Bool) { bands[i].solo = solo }
    func setBand(_ i: Int, bypass: Bool) { bands[i].bypass = bypass }

    func setSampleRate(_ sr: Float) {
        sampleRate = sr
        recalcCrossovers()
        for i in 0..<Self.bandCount { recalcBand(i) }
    }

    func reset() {
        for i in 0..<Self.crossoverCount {
            lp1L[i].reset(); lp1R[i].reset(); lp2L[i].reset(); lp2R[i].reset()
        }
        for i in 0..<Self.bandCount { envelope[i] = 0; gainReductionDb[i] = 0 }
    }

    /// Process stereo in place.
    func processStereo(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frameCount: Int) {
        if !enabled { return }
        ensureScratch(frameCount)

        // Split into 4 bands via subtractive cascaded low-pass.
        // band[0] = LP(x0, f0)
        // rem1 = x0 - band[0]
        // band[1] = LP(rem1, f1)
        // rem2 = rem1 - band[1]
        // band[2] = LP(rem2, f2)
        // band[3] = rem2 - band[2]
        let frames = frameCount
        // Copy input into rem (start with full signal)
        scratchHighL.withUnsafeMutableBufferPointer { hl in
            scratchHighR.withUnsafeMutableBufferPointer { hr in
                for n in 0..<frames { hl[n] = left[n]; hr[n] = right[n] }
            }
        }

        for ci in 0..<Self.crossoverCount {
            // LP twice (Linkwitz-Riley 4th order) on remainder → band[ci]
            scratchLowL.withUnsafeMutableBufferPointer { ll in
                scratchLowR.withUnsafeMutableBufferPointer { lr in
                    scratchHighL.withUnsafeMutableBufferPointer { hl in
                        scratchHighR.withUnsafeMutableBufferPointer { hr in
                            let c = lpCoeffs[ci]
                            for n in 0..<frames {
                                let l1 = lp1L[ci].processSample(hl[n], c)
                                let r1 = lp1R[ci].processSample(hr[n], c)
                                ll[n] = lp2L[ci].processSample(l1, c)
                                lr[n] = lp2R[ci].processSample(r1, c)
                            }
                        }
                    }
                }
            }
            // band[ci] = low, rem = high - low
            bandsL[ci].withUnsafeMutableBufferPointer { bl in
                bandsR[ci].withUnsafeMutableBufferPointer { br in
                    scratchLowL.withUnsafeMutableBufferPointer { ll in
                        scratchLowR.withUnsafeMutableBufferPointer { lr in
                            scratchHighL.withUnsafeMutableBufferPointer { hl in
                                scratchHighR.withUnsafeMutableBufferPointer { hr in
                                    for n in 0..<frames {
                                        bl[n] = ll[n]
                                        br[n] = lr[n]
                                        hl[n] = hl[n] - ll[n]
                                        hr[n] = hr[n] - lr[n]
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        // Last band = remainder.
        bandsL[Self.bandCount - 1].withUnsafeMutableBufferPointer { bl in
            bandsR[Self.bandCount - 1].withUnsafeMutableBufferPointer { br in
                scratchHighL.withUnsafeMutableBufferPointer { hl in
                    scratchHighR.withUnsafeMutableBufferPointer { hr in
                        for n in 0..<frames { bl[n] = hl[n]; br[n] = hr[n] }
                    }
                }
            }
        }

        // Compress each band.
        let anySolo = bands.contains { $0.solo }
        for bi in 0..<Self.bandCount {
            let p = bands[bi]
            let active = !p.bypass && (!anySolo || p.solo)
            let thresholdLin = powf(10, p.thresholdDb / 20)
            let rangeDb = p.rangeDb
            let attackCo = attackCoeff[bi]
            let releaseCo = releaseCoeff[bi]
            let makeup = makeupLin[bi]

            bandsL[bi].withUnsafeMutableBufferPointer { bl in
                bandsR[bi].withUnsafeMutableBufferPointer { br in
                    var env = envelope[bi]
                    var lastGainDb: Float = 0
                    for n in 0..<frames {
                        let absX = max(abs(bl[n]), abs(br[n]))
                        let delta = absX - env
                        if delta > 0 {
                            env += delta * attackCo
                        } else {
                            env += delta * releaseCo
                        }
                        let envDb = 20 * log10f(max(env, 1e-9))
                        let thrDb = 20 * log10f(max(thresholdLin, 1e-9))
                        var overDb = envDb - thrDb
                        if overDb < 0 { overDb = 0 }
                        // Range model: -overDb clamped to [rangeDb, 0] when rangeDb<0 (compress)
                        // or to [0, rangeDb] when rangeDb>0 (expand on the positive direction — rarely used)
                        var gainDb: Float = 0
                        if rangeDb < 0 {
                            gainDb = max(-overDb, rangeDb)
                        } else if rangeDb > 0 {
                            gainDb = min(overDb, rangeDb)
                        }
                        let mul = powf(10, (gainDb + p.makeupDb) / 20)
                        if active {
                            bl[n] *= mul
                            br[n] *= mul
                        }
                        lastGainDb = gainDb
                    }
                    envelope[bi] = env
                    gainReductionDb[bi] = lastGainDb
                    _ = makeup
                }
            }
        }

        // Sum bands back into output, apply output gain.
        let outGainLin = powf(10, outputGainDb / 20)
        for n in 0..<frameCount {
            var l: Float = 0, r: Float = 0
            for bi in 0..<Self.bandCount {
                if bands[bi].bypass { continue }
                if anySolo && !bands[bi].solo { continue }
                l += bandsL[bi][n]
                r += bandsR[bi][n]
            }
            left[n] = l * outGainLin
            right[n] = r * outGainLin
        }
    }

    private func ensureScratch(_ frames: Int) {
        if scratchLowL.count >= frames { return }
        scratchLowL = Array(repeating: 0, count: frames)
        scratchLowR = Array(repeating: 0, count: frames)
        scratchHighL = Array(repeating: 0, count: frames)
        scratchHighR = Array(repeating: 0, count: frames)
        for i in 0..<Self.bandCount {
            bandsL[i] = Array(repeating: 0, count: frames)
            bandsR[i] = Array(repeating: 0, count: frames)
        }
    }

    private func recalcCrossovers() {
        for i in 0..<Self.crossoverCount {
            lpCoeffs[i] = BiquadDesign.lowPass(fs: sampleRate, freq: crossoverHz[i], q: 0.70710678)
        }
    }

    private func recalcBand(_ i: Int) {
        // env_n = env_{n-1} + delta * coeff; coeff = 1 - exp(-1 / (ms/1000 * sr))
        attackCoeff[i] = 1 - expf(-1 / max(bands[i].attackMs / 1000 * sampleRate, 1))
        releaseCoeff[i] = 1 - expf(-1 / max(bands[i].releaseMs / 1000 * sampleRate, 1))
        makeupLin[i] = powf(10, bands[i].makeupDb / 20)
    }
}
