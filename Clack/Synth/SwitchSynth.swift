import Foundation

/// Renders one key event of a recipe to mono Float samples at 48 kHz.
/// Pure and deterministic: identical inputs always produce identical samples.
enum SwitchSynth {
    static func render(recipe: SwitchRecipe, group: KeyGroup, phase: KeyPhase, variant: Int, packID: String) -> [Float] {
        var rng = SeededRandom(seed: fnv1a64("\(packID)|\(group.rawValue)|\(phase)|\(variant)"))
        var event: EventRecipe
        if phase == .down, group == .enter, let carriage = recipe.enterPressOverride {
            event = carriage
        } else {
            event = shaped(phase == .down ? recipe.press : recipe.release, for: group)
        }
        jitter(&event, rng: &rng)
        return renderEvent(event, rng: &rng)
    }

    // MARK: - Per-group variation (stabilized keys sound deeper and longer)

    private struct GroupShape {
        var freq: Double
        var tau: Double
        var gainDb: Double
        var rattle: [(offsetMs: Double, fc: Double, db: Double)]
        var length: Double
    }

    private static func shape(for group: KeyGroup) -> GroupShape {
        switch group {
        case .letter: GroupShape(freq: 1.00, tau: 1.0, gainDb: 0, rattle: [], length: 1.0)
        case .modifier: GroupShape(freq: 0.95, tau: 1.1, gainDb: -1, rattle: [], length: 1.0)
        case .wide: GroupShape(freq: 0.75, tau: 1.6, gainDb: -2, rattle: [(12, 3000, -20)], length: 1.5)
        case .backspace: GroupShape(freq: 0.70, tau: 2.0, gainDb: -1.5, rattle: [(10, 3200, -20)], length: 1.5)
        case .enter: GroupShape(freq: 0.68, tau: 2.0, gainDb: -1, rattle: [(11, 2800, -18)], length: 1.5)
        case .space: GroupShape(freq: 0.60, tau: 2.5, gainDb: -2, rattle: [(9, 2500, -20), (14, 3500, -24)], length: 1.75)
        }
    }

    private static func shaped(_ base: EventRecipe, for group: KeyGroup) -> EventRecipe {
        let s = shape(for: group)
        var e = base
        let tickScale = s.freq.squareRoot()   // keeps noise ticks crisp
        e.ticks = e.ticks.map { t in
            var t = t
            t.fc *= tickScale
            t.tauMs *= s.tau
            return t
        }
        e.modes = e.modes.map { m in
            var m = m
            m.freq *= s.freq
            m.tauMs *= s.tau
            return m
        }
        if var b = e.body {
            b.freq *= s.freq
            b.tauMs *= s.tau
            e.body = b
        }
        for r in s.rattle {   // stabilizer rattle
            e.ticks.append(NoiseTick(offsetMs: r.offsetMs, fc: r.fc, q: 2.0, burstMs: 0.6, tauMs: 3, db: r.db))
        }
        e.gainDb += s.gainDb
        e.lengthMs *= s.length
        return e
    }

    // MARK: - Per-variant jitter

    private static func jitter(_ e: inout EventRecipe, rng: inout SeededRandom) {
        for i in e.ticks.indices {
            e.ticks[i].fc *= rng.uniform(0.92, 1.08)
            e.ticks[i].tauMs *= rng.uniform(0.9, 1.1)
            e.ticks[i].offsetMs = max(0, e.ticks[i].offsetMs + rng.uniform(-1, 1))
        }
        for i in e.modes.indices {
            e.modes[i].freq *= rng.uniform(0.96, 1.04)
            e.modes[i].tauMs *= rng.uniform(0.9, 1.1)
        }
        if var b = e.body {
            b.freq *= rng.uniform(0.96, 1.04)
            b.tauMs *= rng.uniform(0.9, 1.1)
            e.body = b
        }
        if var s = e.sweep {
            let k = rng.uniform(0.92, 1.08)
            s.fcStart *= k
            s.fcEnd *= k
            e.sweep = s
        }
        e.gainDb += rng.uniform(-1.5, 1.5)
    }

    // MARK: - Rendering

    private static let sr = SynthDSP.sampleRate
    private static let samplesPerMs = SynthDSP.sampleRate / 1000

    private static func renderEvent(_ e: EventRecipe, rng: inout SeededRandom) -> [Float] {
        let n = max(1, SynthDSP.ms(e.lengthMs))
        var out = [Float](repeating: 0, count: n)
        out.withUnsafeMutableBufferPointer { buf in
            for t in e.ticks { addTick(t, into: buf, rng: &rng) }
            for m in e.modes { addMode(m, startMs: e.modesOffsetMs + m.offsetMs, into: buf, rng: &rng) }
            if let b = e.body { addBody(b, into: buf) }
            if let s = e.sweep { addSweep(s, into: buf, rng: &rng) }

            let gain = Float(SynthDSP.dbToLin(e.gainDb))
            if let lp = e.lowpassHz {
                var f = Biquad.lowpass(fc: lp, q: 0.7071, sampleRate: sr)
                for i in 0..<n { buf[i] = f.process(buf[i] * gain) }
            } else {
                for i in 0..<n { buf[i] *= gain }
            }

            let fade = min(n, SynthDSP.ms(5))
            for k in 0..<fade {
                buf[n - 1 - k] *= Float(k) / Float(fade)
            }
        }
        return out
    }

    /// White noise for `burstMs` through a band-pass that keeps ringing on zeros;
    /// envelope is a 0.3 ms linear attack then exp decay, for 7 tau.
    private static func addTick(_ t: NoiseTick, into buf: UnsafeMutableBufferPointer<Float>, rng: inout SeededRandom) {
        let start = SynthDSP.ms(t.offsetMs)
        let burst = max(1, SynthDSP.ms(t.burstMs))
        let attack = 0.3 * samplesPerMs
        let tau = max(t.tauMs, 0.01) * samplesPerMs
        let total = Int(attack + 7 * tau)
        let amp = Float(SynthDSP.dbToLin(t.db))
        let decay = Float(exp(-1 / tau))
        var f = Biquad.bandpass(fc: t.fc, q: t.q, sampleRate: sr)
        var env: Float = 1
        for i in 0..<total {
            let idx = start + i
            guard idx < buf.count else { break }
            let x: Float = i < burst ? Float(rng.uniform(-1, 1)) : 0
            let y = f.process(x)
            let e: Float
            if Double(i) < attack {
                e = Float(Double(i) / attack)
            } else {
                e = env
                env *= decay
            }
            buf[idx] += y * e * amp
        }
    }

    /// Decaying sine with random phase, 0.5 ms linear attack, for 7 tau.
    private static func addMode(_ m: ToneMode, startMs: Double, into buf: UnsafeMutableBufferPointer<Float>, rng: inout SeededRandom) {
        let phase = rng.uniform(0, 2 * Double.pi)
        let start = SynthDSP.ms(startMs)
        let attack = 0.5 * samplesPerMs
        let tau = max(m.tauMs, 0.01) * samplesPerMs
        let total = Int(attack + 7 * tau)
        let amp = SynthDSP.dbToLin(m.db)
        let w = 2 * Double.pi * min(m.freq, sr * 0.45) / sr
        let decay = exp(-1 / tau)
        var env = 1.0
        for i in 0..<total {
            let idx = start + i
            guard idx < buf.count else { break }
            let e: Double
            if Double(i) < attack {
                e = Double(i) / attack
            } else {
                e = env
                env *= decay
            }
            buf[idx] += Float(amp * sin(w * Double(i) + phase) * e)
        }
    }

    /// Low thump whose pitch drops from 1.3x to `freq` over the first 2 ms.
    private static func addBody(_ b: BodyThump, into buf: UnsafeMutableBufferPointer<Float>) {
        let start = SynthDSP.ms(b.offsetMs)
        let attack = 0.5 * samplesPerMs
        let drop = 2 * samplesPerMs
        let tau = max(b.tauMs, 0.01) * samplesPerMs
        let total = Int(attack + 7 * tau)
        let amp = SynthDSP.dbToLin(b.db)
        var phase = 0.0
        for i in 0..<total {
            let idx = start + i
            guard idx < buf.count else { break }
            let t = Double(i)
            let f = b.freq * (1 + 0.3 * max(0, 1 - t / drop))
            let e = t < attack ? t / attack : exp(-(t - attack) / tau)
            buf[idx] += Float(amp * sin(phase) * e)
            phase += 2 * Double.pi * f / sr
        }
    }

    /// Noise through a band-pass whose center sweeps linearly; coefficients update every 64 samples.
    private static func addSweep(_ s: NoiseSweep, into buf: UnsafeMutableBufferPointer<Float>, rng: inout SeededRandom) {
        let start = SynthDSP.ms(s.startMs)
        let total = max(1, SynthDSP.ms(s.endMs - s.startMs))
        let attack = max(1, SynthDSP.ms(s.attackMs))
        let amp = SynthDSP.dbToLin(s.db)
        var f = Biquad.bandpass(fc: s.fcStart, q: s.q, sampleRate: sr)
        for i in 0..<total {
            let idx = start + i
            guard idx < buf.count else { break }
            if i % 64 == 0 {
                let p = Double(i) / Double(total)
                f.setBandpass(fc: s.fcStart + (s.fcEnd - s.fcStart) * p, q: s.q, sampleRate: sr)
            }
            let e = i < attack
                ? Double(i) / Double(attack)
                : Double(total - i) / Double(max(1, total - attack))
            let y = f.process(Float(rng.uniform(-1, 1)))
            buf[idx] += y * Float(amp * e)
        }
    }
}
