import Foundation

enum SynthDSP {
    static let sampleRate: Double = 48_000

    static func dbToLin(_ db: Double) -> Double {
        pow(10, db / 20)
    }

    /// Milliseconds to a sample count at 48 kHz.
    static func ms(_ x: Double) -> Int {
        Int((x * sampleRate / 1000).rounded())
    }
}

/// RBJ cookbook biquad, Direct Form I, Float state.
struct Biquad {
    private var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    private var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

    /// Band-pass with constant 0 dB peak gain.
    static func bandpass(fc: Double, q: Double, sampleRate: Double) -> Biquad {
        var f = Biquad()
        f.setBandpass(fc: fc, q: q, sampleRate: sampleRate)
        return f
    }

    /// Low-pass; pass q 0.7071 for Butterworth.
    static func lowpass(fc: Double, q: Double, sampleRate: Double) -> Biquad {
        let (cosW, alpha) = terms(fc: fc, q: q, sampleRate: sampleRate)
        let a0 = 1 + alpha
        var f = Biquad()
        f.b0 = Float((1 - cosW) / 2 / a0)
        f.b1 = Float((1 - cosW) / a0)
        f.b2 = Float((1 - cosW) / 2 / a0)
        f.a1 = Float(-2 * cosW / a0)
        f.a2 = Float((1 - alpha) / a0)
        return f
    }

    /// Retunes a band-pass in place, keeping the filter state (used for sweeps).
    mutating func setBandpass(fc: Double, q: Double, sampleRate: Double) {
        let (cosW, alpha) = Biquad.terms(fc: fc, q: q, sampleRate: sampleRate)
        let a0 = 1 + alpha
        b0 = Float(alpha / a0)
        b1 = 0
        b2 = Float(-alpha / a0)
        a1 = Float(-2 * cosW / a0)
        a2 = Float((1 - alpha) / a0)
    }

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y
    }

    private static func terms(fc: Double, q: Double, sampleRate: Double) -> (cosW: Double, alpha: Double) {
        let f = min(max(fc, 10), sampleRate * 0.45)
        let w0 = 2 * Double.pi * f / sampleRate
        return (cos(w0), sin(w0) / (2 * max(q, 0.05)))
    }
}
