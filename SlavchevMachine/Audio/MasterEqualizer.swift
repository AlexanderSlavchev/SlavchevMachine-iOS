import Foundation

/// 8-band peaking EQ. Fixed frequencies, user adjusts gain only.
final class MasterEqualizer {
    static let bandFrequencies: [Float] = [60, 170, 310, 600, 1000, 3000, 6000, 12000]
    static let bandCount = bandFrequencies.count
    static let q: Float = 1.41

    private var sampleRate: Float = 48000
    private var gains: [Float] = Array(repeating: 0, count: bandCount)
    private var coeffs: [BiquadCoeffs] = Array(repeating: BiquadCoeffs(), count: bandCount)
    private var statesL: [BiquadState] = Array(repeating: BiquadState(), count: bandCount)
    private var statesR: [BiquadState] = Array(repeating: BiquadState(), count: bandCount)

    func setSampleRate(_ sr: Float) {
        sampleRate = sr
        recalcAll()
    }

    func gain(_ band: Int) -> Float { gains[band] }

    func setGain(_ band: Int, db: Float) {
        gains[band] = db
        coeffs[band] = BiquadDesign.peak(fs: sampleRate, freq: Self.bandFrequencies[band], gainDb: db, q: Self.q)
    }

    func reset() {
        for i in 0..<Self.bandCount {
            statesL[i].reset()
            statesR[i].reset()
        }
    }

    func processStereo(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frameCount: Int) {
        for i in 0..<Self.bandCount {
            let c = coeffs[i]
            for n in 0..<frameCount {
                left[n] = statesL[i].processSample(left[n], c)
                right[n] = statesR[i].processSample(right[n], c)
            }
        }
    }

    private func recalcAll() {
        for i in 0..<Self.bandCount {
            coeffs[i] = BiquadDesign.peak(fs: sampleRate, freq: Self.bandFrequencies[i], gainDb: gains[i], q: Self.q)
        }
    }
}
