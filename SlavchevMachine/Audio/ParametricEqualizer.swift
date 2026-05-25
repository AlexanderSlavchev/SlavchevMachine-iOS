import Foundation

enum EqShape: Int, CaseIterable {
    case bell = 0
    case lowShelf = 1
    case highShelf = 2
    case lowCut = 3
    case highCut = 4

    var label: String {
        switch self {
        case .bell: return "BELL"
        case .lowShelf: return "LO SHELF"
        case .highShelf: return "HI SHELF"
        case .lowCut: return "LO CUT"
        case .highCut: return "HI CUT"
        }
    }
}

struct EqBandConfig {
    var shape: EqShape = .bell
    var freqHz: Float = 1000
    var gainDb: Float = 0
    var q: Float = 1
    var enabled: Bool = false
}

/// Up to 6 user-configurable bands. Used by the looper's output EQ.
final class ParametricEqualizer {
    static let maxBands = 6

    private var sampleRate: Float = 48000
    private(set) var bands: [EqBandConfig] = Array(repeating: EqBandConfig(), count: maxBands)
    private var coeffs: [BiquadCoeffs] = Array(repeating: BiquadCoeffs(), count: maxBands)
    private var states: [BiquadState] = Array(repeating: BiquadState(), count: maxBands)

    func setSampleRate(_ sr: Float) {
        sampleRate = sr
        for i in 0..<Self.maxBands { recalc(i) }
    }

    func setBand(_ index: Int, _ config: EqBandConfig) {
        bands[index] = config
        recalc(index)
    }

    func coefficients(_ index: Int) -> BiquadCoeffs { coeffs[index] }

    func reset() {
        for i in 0..<Self.maxBands { states[i].reset() }
    }

    func process(_ mono: UnsafeMutablePointer<Float>, frameCount: Int) {
        for i in 0..<Self.maxBands where bands[i].enabled {
            let c = coeffs[i]
            for n in 0..<frameCount {
                mono[n] = states[i].processSample(mono[n], c)
            }
        }
    }

    private func recalc(_ i: Int) {
        let b = bands[i]
        switch b.shape {
        case .bell:      coeffs[i] = BiquadDesign.peak(fs: sampleRate, freq: b.freqHz, gainDb: b.gainDb, q: b.q)
        case .lowShelf:  coeffs[i] = BiquadDesign.lowShelf(fs: sampleRate, freq: b.freqHz, gainDb: b.gainDb, q: b.q)
        case .highShelf: coeffs[i] = BiquadDesign.highShelf(fs: sampleRate, freq: b.freqHz, gainDb: b.gainDb, q: b.q)
        case .lowCut:    coeffs[i] = BiquadDesign.highPass(fs: sampleRate, freq: b.freqHz, q: b.q)
        case .highCut:   coeffs[i] = BiquadDesign.lowPass(fs: sampleRate, freq: b.freqHz, q: b.q)
        }
    }
}
