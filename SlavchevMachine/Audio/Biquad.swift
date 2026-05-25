import Foundation

struct BiquadCoeffs {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0
    var a1: Float = 0, a2: Float = 0
}

struct BiquadState {
    var z1: Float = 0
    var z2: Float = 0

    mutating func processSample(_ x: Float, _ c: BiquadCoeffs) -> Float {
        let y = c.b0 * x + z1
        z1 = c.b1 * x - c.a1 * y + z2
        z2 = c.b2 * x - c.a2 * y
        return y
    }

    mutating func reset() {
        z1 = 0
        z2 = 0
    }
}

enum BiquadDesign {
    /// RBJ peak (bell) — used by master EQ and parametric EQ.
    static func peak(fs: Float, freq: Float, gainDb: Float, q: Float) -> BiquadCoeffs {
        let A = powf(10, gainDb / 40)
        let w0 = 2 * Float.pi * max(min(freq, fs / 2 - 1), 1) / fs
        let cosw = cosf(w0)
        let sinw = sinf(w0)
        let alpha = sinw / (2 * max(q, 0.0001))

        let b0 = 1 + alpha * A
        let b1 = -2 * cosw
        let b2 = 1 - alpha * A
        let a0 = 1 + alpha / A
        let a1 = -2 * cosw
        let a2 = 1 - alpha / A
        return BiquadCoeffs(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    static func lowShelf(fs: Float, freq: Float, gainDb: Float, q: Float) -> BiquadCoeffs {
        let A = powf(10, gainDb / 40)
        let w0 = 2 * Float.pi * max(min(freq, fs / 2 - 1), 1) / fs
        let cosw = cosf(w0)
        let sinw = sinf(w0)
        let alpha = sinw / (2 * max(q, 0.0001))
        let sqrtA2alpha = 2 * sqrtf(A) * alpha

        let b0 = A * ((A + 1) - (A - 1) * cosw + sqrtA2alpha)
        let b1 = 2 * A * ((A - 1) - (A + 1) * cosw)
        let b2 = A * ((A + 1) - (A - 1) * cosw - sqrtA2alpha)
        let a0 = (A + 1) + (A - 1) * cosw + sqrtA2alpha
        let a1 = -2 * ((A - 1) + (A + 1) * cosw)
        let a2 = (A + 1) + (A - 1) * cosw - sqrtA2alpha
        return BiquadCoeffs(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    static func highShelf(fs: Float, freq: Float, gainDb: Float, q: Float) -> BiquadCoeffs {
        let A = powf(10, gainDb / 40)
        let w0 = 2 * Float.pi * max(min(freq, fs / 2 - 1), 1) / fs
        let cosw = cosf(w0)
        let sinw = sinf(w0)
        let alpha = sinw / (2 * max(q, 0.0001))
        let sqrtA2alpha = 2 * sqrtf(A) * alpha

        let b0 = A * ((A + 1) + (A - 1) * cosw + sqrtA2alpha)
        let b1 = -2 * A * ((A - 1) + (A + 1) * cosw)
        let b2 = A * ((A + 1) + (A - 1) * cosw - sqrtA2alpha)
        let a0 = (A + 1) - (A - 1) * cosw + sqrtA2alpha
        let a1 = 2 * ((A - 1) - (A + 1) * cosw)
        let a2 = (A + 1) - (A - 1) * cosw - sqrtA2alpha
        return BiquadCoeffs(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    static func highPass(fs: Float, freq: Float, q: Float) -> BiquadCoeffs {
        let w0 = 2 * Float.pi * max(min(freq, fs / 2 - 1), 1) / fs
        let cosw = cosf(w0)
        let sinw = sinf(w0)
        let alpha = sinw / (2 * max(q, 0.0001))

        let b0 = (1 + cosw) / 2
        let b1 = -(1 + cosw)
        let b2 = (1 + cosw) / 2
        let a0 = 1 + alpha
        let a1 = -2 * cosw
        let a2 = 1 - alpha
        return BiquadCoeffs(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    static func lowPass(fs: Float, freq: Float, q: Float) -> BiquadCoeffs {
        let w0 = 2 * Float.pi * max(min(freq, fs / 2 - 1), 1) / fs
        let cosw = cosf(w0)
        let sinw = sinf(w0)
        let alpha = sinw / (2 * max(q, 0.0001))

        let b0 = (1 - cosw) / 2
        let b1 = 1 - cosw
        let b2 = (1 - cosw) / 2
        let a0 = 1 + alpha
        let a1 = -2 * cosw
        let a2 = 1 - alpha
        return BiquadCoeffs(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    /// Magnitude response in dB at digital frequency w = 2π·f/fs.
    static func magnitudeDb(coeffs c: BiquadCoeffs, freq: Float, fs: Float) -> Float {
        let w = 2 * Float.pi * freq / fs
        let cosw = cosf(w), cos2w = cosf(2 * w)
        let sinw = sinf(w), sin2w = sinf(2 * w)
        let numRe = c.b0 + c.b1 * cosw + c.b2 * cos2w
        let numIm = -(c.b1 * sinw + c.b2 * sin2w)
        let denRe = 1 + c.a1 * cosw + c.a2 * cos2w
        let denIm = -(c.a1 * sinw + c.a2 * sin2w)
        let num2 = numRe * numRe + numIm * numIm
        let den2 = max(denRe * denRe + denIm * denIm, 1e-12)
        let mag2 = num2 / den2
        return 10 * log10f(max(mag2, 1e-9))
    }
}
