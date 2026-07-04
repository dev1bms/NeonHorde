// tools/sfxgen/main.swift — Neon Horde SFX synthesizer (GOAL §4 Audio & Haptics,
// AMENDMENT v3 / Phase 8C: realistic dark-fantasy-forest sound set).
//
// Synthesizes every gameplay sound as code — deterministic Float32 PCM
// computed sample-by-sample and written as mono 44.1 kHz .caf via AVAudioFile.
// v2 sound design replaces the sfxr-style zaps with layered, physically
// flavored sounds (sword slash, meaty creature impacts, treant roar, night
// forest ambience): multi-layer mixes, swept RBJ biquad bandpasses, FM bells,
// granular wood creaks, exponential decays everywhere (no linear fades), and
// a small Schroeder reverb (3 damped combs + 1 allpass) applied subtly to
// slash / fanfare / roar. Output filenames are unchanged from v1 so
// AudioManager needs no changes; ambience_forest.caf is new — a seamless
// ~24 s night-forest bed that loops under the music.
//
// Usage: swift tools/sfxgen/main.swift <outputDir>
//
// Machine-checkable gates (GOAL §4 — the builder cannot listen): every file
// must satisfy peak < 0.98 (no clipping) and a sane RMS (0.02–0.5 for
// one-shots; 0.04–0.12 for the ambience bed so it sits LOW under music).
// ambience_forest must additionally loop seamlessly — mean |first64 − last64|
// < 0.02 — achieved by crossfading the rendered tail back into the head and
// pinning the edges to zero (same treatment as tools/musicgen). One
// `GATE <name> peak=<v> rms=<v> loopDelta=<v> PASS|FAIL` line per file;
// exits non-zero if any gate fails.

import AVFoundation
import Foundation

let sampleRate = 44100.0

// MARK: - DSP primitives

/// Deterministic white noise source (SplitMix64 — same generator family as Core).
struct NoiseSource {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    /// Uniform white noise in [-1, 1].
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z >> 11) * (2.0 / 9007199254740992.0) - 1.0
    }
}

/// Simple one-pole lowpass: y += k * (x - y).
struct OnePoleLP {
    private var y = 0.0
    private var k: Double

    init(cutoff: Double) { k = OnePoleLP.coefficient(cutoff) }

    static func coefficient(_ cutoff: Double) -> Double {
        1.0 - exp(-2.0 * .pi * cutoff / sampleRate)
    }

    mutating func set(cutoff: Double) { k = OnePoleLP.coefficient(cutoff) }

    mutating func process(_ x: Double) -> Double {
        y += k * (x - y)
        return y
    }
}

/// RBJ biquad (Direct Form I) — the bandpass/resonant workhorse for swooshes,
/// wooden knocks, creaking grains, and debris. Coefficients may be re-set
/// per-sample for smooth sweeps; the filter state carries across.
struct Biquad {
    private var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    static func bandpass(center: Double, q: Double) -> Biquad {
        var f = Biquad()
        f.setBandpass(center: center, q: q)
        return f
    }

    mutating func setBandpass(center: Double, q: Double) {
        let w = 2.0 * .pi * min(max(center, 20), 18000) / sampleRate
        let alpha = sin(w) / (2.0 * max(q, 0.05))
        let a0 = 1.0 + alpha
        b0 = alpha / a0
        b1 = 0
        b2 = -alpha / a0
        a1 = -2.0 * cos(w) / a0
        a2 = (1.0 - alpha) / a0
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y
    }
}

/// Percussive exponential decay with a very short linear attack (click-free).
func percEnv(_ t: Double, attack: Double, tau: Double) -> Double {
    min(t / max(attack, 1e-6), 1.0) * exp(-t / tau)
}

/// Gaussian swell centered at `center` (smooth rise and fall, no linear fades).
func swell(_ t: Double, center: Double, width: Double) -> Double {
    let x = (t - center) / width
    return exp(-x * x)
}

func sine(_ phase: Double) -> Double { sin(2.0 * .pi * phase) }
func saw(_ phase: Double) -> Double { 2.0 * (phase - floor(phase)) - 1.0 }

func sampleCount(_ duration: Double) -> Int { Int(duration * sampleRate) }

/// Schroeder reverb — 3 parallel damped combs + 1 allpass, mixed into the dry
/// signal. Subtle "forest clearing" tail for slash / fanfare / roar.
func reverb(_ dry: [Double], wet: Double, feedback: Double = 0.76) -> [Double] {
    let n = dry.count
    var sum = [Double](repeating: 0, count: n)
    for delay in [1116, 1277, 1422] {
        var buf = [Double](repeating: 0, count: delay)
        var idx = 0
        var damp = 0.0
        for i in 0..<n {
            let y = buf[idx]
            damp += 0.34 * (y - damp)                // lowpass inside the loop
            buf[idx] = dry[i] + damp * feedback
            sum[i] += y
            idx = (idx + 1) % delay
        }
    }
    var ap = [Double](repeating: 0, count: 225)
    var idx = 0
    var out = dry
    for i in 0..<n {
        let x = sum[i] / 3.0
        let z = ap[idx]
        let y = z - 0.5 * x
        ap[idx] = x + 0.5 * y
        out[i] += wet * y
        idx = (idx + 1) % 225
    }
    return out
}

/// Single FM bell voice: carrier + exponentially-decaying-index modulator —
/// warm and crystalline, not beepy. Adds into `out` at `startTime`.
func fmBell(into out: inout [Double], at startTime: Double, freq: Double,
            dur: Double, ratio: Double, index: Double, tau: Double, gain: Double) {
    let start = Int(startTime * sampleRate)
    let len = sampleCount(dur)
    var carPhase = 0.0
    var modPhase = 0.0
    for j in 0..<len where start + j >= 0 && start + j < out.count {
        let t = Double(j) / sampleRate
        modPhase += freq * ratio / sampleRate
        let inst = index * exp(-t / (tau * 0.55)) * sin(2.0 * .pi * modPhase)
        carPhase += freq / sampleRate
        out[start + j] += sin(2.0 * .pi * carPhase + inst)
            * percEnv(t, attack: 0.003, tau: tau) * gain
    }
}

/// Peak-normalize in place (target < 0.98 clipping gate, with margin).
func normalize(_ samples: inout [Double], peak target: Double = 0.85) {
    var peak = 0.0
    for s in samples { peak = max(peak, abs(s)) }
    guard peak > 0 else { return }
    let g = target / peak
    for i in samples.indices { samples[i] *= g }
}

/// Scale to an exact RMS (ambience bed level), preserving relative dynamics.
func normalizeRMS(_ samples: inout [Double], target: Double) {
    var sum = 0.0
    for s in samples { sum += s * s }
    let rms = (sum / Double(samples.count)).squareRoot()
    guard rms > 0 else { return }
    let g = target / rms
    for i in samples.indices { samples[i] *= g }
}

/// Cosine fade over the last ~4 ms so every one-shot ends exactly at silence
/// (a non-zero final sample would click on playback cutoff).
func fadeTail(_ samples: inout [Double], length: Int = 176) {
    let n = samples.count
    guard n > length else { return }
    for i in 0..<length {
        let t = Double(i + 1) / Double(length)
        samples[n - length + i] *= 0.5 + 0.5 * cos(t * .pi)
    }
}

// MARK: - Sounds (forest-fantasy set — filenames unchanged from v1)

/// laser.caf — sword slash: a bandpassed noise swoosh whose center frequency
/// traces the swing arc (rises to ~3.4 kHz then falls) layered with a
/// metallic "shing" — detuned inharmonic sine partials with fast shimmer
/// decay that enter as the blade arrives. Subtle reverb tail.
func slash() -> [Double] {
    let dur = 0.35
    let n = sampleCount(dur)
    var out = [Double](repeating: 0, count: n)
    var noise = NoiseSource(seed: 0x51A5)
    var bp = Biquad.bandpass(center: 500, q: 1.3)
    for i in 0..<n {
        let t = Double(i) / sampleRate
        // Swing arc: center 500 -> 3400 Hz over 70 ms, then falls back.
        let arc = t < 0.07 ? t / 0.07 : max(0, 1.0 - (t - 0.07) / 0.14)
        bp.setBandpass(center: 500.0 * pow(3400.0 / 500.0, arc), q: 1.3)
        out[i] = bp.process(noise.next()) * percEnv(t, attack: 0.012, tau: 0.07) * 1.6
    }
    // Metallic shing: detuned inharmonic partials with per-partial shimmer AM.
    let partials: [(f: Double, g: Double)] = [
        (2354, 0.40), (2417, 0.34), (3151, 0.27), (3989, 0.21), (5273, 0.15),
    ]
    for (k, p) in partials.enumerated() {
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sampleRate
            guard t >= 0.02 else { continue }        // blade "arrives" at 20 ms
            let tt = t - 0.02
            phase += p.f / sampleRate
            let shimmer = 1.0 - 0.35 * (0.5 + 0.5 * sin(2.0 * .pi * (31.0 + 4.0 * Double(k)) * tt))
            out[i] += sin(2.0 * .pi * phase) * percEnv(tt, attack: 0.002, tau: 0.075) * shimmer * p.g
        }
    }
    return reverb(out, wet: 0.16)
}

/// hit.caf — meaty creature impact: low pitch-dropping thump + short
/// bandpassed noise crunch + a tiny growl grunt (pitch-modulated saw burst
/// with amplitude roughness).
func hit() -> [Double] {
    let dur = 0.3
    let n = sampleCount(dur)
    var out = [Double](repeating: 0, count: n)
    var noise = NoiseSource(seed: 0xDEAD)
    var crunch = Biquad.bandpass(center: 1500, q: 0.8)
    var gruntLP = OnePoleLP(cutoff: 760)
    var thumpPhase = 0.0
    var gruntPhase = 0.0
    for i in 0..<n {
        let t = Double(i) / sampleRate
        // Thump: 130 -> 46 Hz.
        let ft = 130.0 * pow(46.0 / 130.0, min(t / 0.14, 1.0))
        thumpPhase += ft / sampleRate
        let thump = sine(thumpPhase) * percEnv(t, attack: 0.002, tau: 0.065)
        // Crunch: fast filtered-noise snap.
        let crunchS = crunch.process(noise.next()) * percEnv(t, attack: 0.001, tau: 0.026) * 1.6
        // Grunt: saw glissing 115 -> 70 Hz with a wobble, 12 ms behind the hit.
        var grunt = 0.0
        if t > 0.012 {
            let tg = t - 0.012
            let fg = 115.0 * pow(70.0 / 115.0, min(tg / 0.16, 1.0))
                * (1.0 + 0.05 * sin(2.0 * .pi * 11.0 * tg))
            gruntPhase += fg / sampleRate
            let rough = 1.0 - 0.4 * (0.5 + 0.5 * sin(2.0 * .pi * 29.0 * tg))
            grunt = gruntLP.process(saw(gruntPhase))
                * percEnv(tg, attack: 0.008, tau: 0.07) * rough * 0.8
        }
        out[i] = thump + 0.55 * crunchS + grunt
    }
    return out
}

/// explosion.caf — deep forest impact: sub thump (90 -> 33 Hz) + debris noise
/// tail whose lowpass sweeps down across the whole sound + seeded scatter of
/// tiny bandpassed debris crackles (twigs/soil), later ones quieter.
func explosion() -> [Double] {
    let dur = 0.6
    let n = sampleCount(dur)
    var out = [Double](repeating: 0, count: n)
    var noise = NoiseSource(seed: 0xB00B)
    var lp = OnePoleLP(cutoff: 3800)
    var phase = 0.0
    for i in 0..<n {
        let t = Double(i) / sampleRate
        lp.set(cutoff: 3800.0 * pow(200.0 / 3800.0, t / dur))
        let debris = lp.process(noise.next()) * percEnv(t, attack: 0.004, tau: 0.19)
        let f = 90.0 * pow(33.0 / 90.0, min(t / 0.3, 1.0))
        phase += f / sampleRate
        let sub = sine(phase) * percEnv(t, attack: 0.002, tau: 0.16) * 1.1
        out[i] = debris + sub
    }
    var rng = NoiseSource(seed: 0xC4AC)
    for _ in 0..<9 {
        let start = 0.05 + 0.4 * abs(rng.next())
        var crack = Biquad.bandpass(center: 1400.0 + 1900.0 * abs(rng.next()), q: 2.2)
        let s = Int(start * sampleRate)
        for j in 0..<sampleCount(0.03) where s + j < n {
            let tt = Double(j) / sampleRate
            out[s + j] += crack.process(rng.next())
                * percEnv(tt, attack: 0.001, tau: 0.007) * 0.5 * exp(-start * 2.2)
        }
    }
    return out
}

/// pickup.caf — warm crystalline chime: two soft FM bells a fifth apart
/// (A5 then E6) over a quiet warm fundamental. Nothing beepy.
func pickup() -> [Double] {
    let dur = 0.25
    var out = [Double](repeating: 0, count: sampleCount(dur))
    fmBell(into: &out, at: 0.00, freq: 880.00, dur: 0.24, ratio: 2.756, index: 1.7, tau: 0.075, gain: 0.9)
    fmBell(into: &out, at: 0.07, freq: 1318.51, dur: 0.17, ratio: 2.756, index: 1.4, tau: 0.060, gain: 0.6)
    fmBell(into: &out, at: 0.00, freq: 440.00, dur: 0.24, ratio: 2.0, index: 0.8, tau: 0.090, gain: 0.35)
    return out
}

/// levelup.caf — short magical fanfare: three rising FM bells (A4 C5 E5, the
/// last ringing out with an octave sparkle) + a bandpassed shimmer-noise
/// swell peaking mid-phrase. Subtle reverb.
func levelup() -> [Double] {
    let dur = 0.7
    let n = sampleCount(dur)
    var out = [Double](repeating: 0, count: n)
    fmBell(into: &out, at: 0.00, freq: 440.00, dur: 0.50, ratio: 2.402, index: 1.9, tau: 0.14, gain: 0.75)
    fmBell(into: &out, at: 0.13, freq: 523.25, dur: 0.50, ratio: 2.402, index: 1.9, tau: 0.14, gain: 0.80)
    fmBell(into: &out, at: 0.26, freq: 659.26, dur: 0.44, ratio: 2.402, index: 1.7, tau: 0.22, gain: 0.90)
    fmBell(into: &out, at: 0.26, freq: 1318.51, dur: 0.40, ratio: 2.756, index: 1.2, tau: 0.18, gain: 0.30)
    var noise = NoiseSource(seed: 0xFAFA)
    var shimmer = Biquad.bandpass(center: 5800, q: 0.9)
    for i in 0..<n {
        let t = Double(i) / sampleRate
        out[i] += shimmer.process(noise.next()) * swell(t, center: 0.42, width: 0.16) * 0.10
    }
    return reverb(out, wet: 0.2)
}

/// uitick.caf — soft wooden tick: a 2 ms noise knock excites two resonant
/// bandpasses (woodblock body modes) over a tiny low thock.
func uitick() -> [Double] {
    let dur = 0.06
    let n = sampleCount(dur)
    var out = [Double](repeating: 0, count: n)
    var noise = NoiseSource(seed: 0x71C4)
    var body = Biquad.bandpass(center: 1180, q: 5.5)
    var body2 = Biquad.bandpass(center: 2140, q: 6.5)
    var phase = 0.0
    for i in 0..<n {
        let t = Double(i) / sampleRate
        let excite = noise.next() * percEnv(t, attack: 0.0004, tau: 0.0016)
        let knock = body.process(excite) + body2.process(excite) * 0.45
        phase += 340.0 / sampleRate
        let thock = sine(phase) * percEnv(t, attack: 0.0006, tau: 0.008) * 0.5
        out[i] = knock * 2.2 + thock
    }
    return out
}

/// bossroar.caf — ancient treant roar: low detuned saw "trunk" cluster with
/// slow AM + a rough beast-growl layer (pitch-falling saw with 26 Hz
/// amplitude roughness) + creaking-wood granular bursts (short pitch-swept
/// bandpassed noise grains) + breath noise. Reverb tail.
func bossroar() -> [Double] {
    let dur = 1.6
    let n = sampleCount(dur)
    var out = [Double](repeating: 0, count: n)
    // Master envelope: exponential attack, exponential release from 1.0 s.
    func env(_ t: Double) -> Double {
        (1.0 - exp(-t / 0.07)) * (t > 1.0 ? exp(-(t - 1.0) / 0.17) : 1.0)
    }
    let freqs = [46.0, 49.5, 55.0, 61.8]
    var phases = [Double](repeating: 0, count: freqs.count)
    var trunkLP = OnePoleLP(cutoff: 420)
    var growlPhase = 0.0
    var growlLP = OnePoleLP(cutoff: 950)
    var noise = NoiseSource(seed: 0x50A2)
    var breathLP = OnePoleLP(cutoff: 600)
    for i in 0..<n {
        let t = Double(i) / sampleRate
        var cluster = 0.0
        for (k, f) in freqs.enumerated() {
            phases[k] += f * (1.0 + 0.01 * sin(2.0 * .pi * 0.7 * t + Double(k))) / sampleRate
            cluster += saw(phases[k])
        }
        cluster = trunkLP.process(cluster / Double(freqs.count))
            * (0.62 + 0.38 * sin(2.0 * .pi * 2.6 * t - .pi / 2))
        let fg = 120.0 * pow(78.0 / 120.0, min(t / 0.5, 1.0)) * (1.0 + 0.04 * sin(2.0 * .pi * 5.2 * t))
        growlPhase += fg / sampleRate
        let rough = 1.0 - 0.5 * (0.5 + 0.5 * sin(2.0 * .pi * 26.0 * t))
        let growl = growlLP.process(saw(growlPhase)) * rough * 0.55 * min(t / 0.15, 1.0)
        let breath = breathLP.process(noise.next()) * swell(t, center: 0.7, width: 0.45) * 0.3
        out[i] = (cluster + growl + breath) * env(t)
    }
    // Creaks: pitch-swept bandpassed noise grains (bending, splitting wood).
    var rng = NoiseSource(seed: 0xC2EA)
    for g in 0..<16 {
        let start = 0.08 + 1.05 * Double(g) / 16.0 + 0.03 * rng.next()
        let glen = 0.05 + 0.05 * abs(rng.next())
        let f0 = 260.0 + 320.0 * abs(rng.next())
        let sweep = g % 2 == 0 ? 1.9 : 0.55          // alternate up/down creaks
        var bp = Biquad.bandpass(center: f0, q: 3.4)
        let s = Int(start * sampleRate)
        for j in 0..<sampleCount(glen) where s + j < n {
            let tt = Double(j) / sampleRate
            bp.setBandpass(center: f0 * pow(sweep, tt / glen), q: 3.4)
            out[s + j] += bp.process(rng.next())
                * percEnv(tt, attack: 0.004, tau: glen / 3.0) * 0.5 * env(start)
        }
    }
    return reverb(out, wet: 0.22, feedback: 0.8)
}

/// revive.caf — rising ethereal shimmer (600 -> 2600 Hz gliss with a detuned
/// octave partner) over a soft choir-ish swell of detuned sine pairs
/// (Am cluster, slow vibrato) plus rising sparkle grains.
func revive() -> [Double] {
    let dur = 0.7
    let n = sampleCount(dur)
    var out = [Double](repeating: 0, count: n)
    // Choir: A3 E4 A4 C5, ±0.45% detuned pairs, slow vibrato, smooth swell.
    let notes = [220.0, 329.63, 440.0, 523.25]
    for (k, f0) in notes.enumerated() {
        for det in [0.9955, 1.0045] {
            var phase = 0.0
            for i in 0..<n {
                let t = Double(i) / sampleRate
                let vib = 1.0 + 0.008 * sin(2.0 * .pi * 5.1 * t + Double(k) * 1.3)
                phase += f0 * det * vib / sampleRate
                let rise = min(t / 0.28, 1.0)
                let e = rise * rise * (t > 0.48 ? exp(-(t - 0.48) / 0.09) : 1.0)
                out[i] += sine(phase) * e * (0.22 - 0.03 * Double(k))
            }
        }
    }
    // Rising shimmer: gliss with a slightly-sharp octave partner.
    var phase = 0.0
    var octPhase = 0.0
    for i in 0..<n {
        let t = Double(i) / sampleRate
        let f = 600.0 * pow(2600.0 / 600.0, min(t / 0.55, 1.0))
        phase += f / sampleRate
        octPhase += f * 2.003 / sampleRate
        let shim = sine(phase) + 0.4 * sine(octPhase)
        out[i] += shim * min(t / 0.1, 1.0) * (t > 0.5 ? exp(-(t - 0.5) / 0.08) : 1.0) * 0.28
    }
    // Sparkles: seeded rising pings.
    var rng = NoiseSource(seed: 0x5EED)
    for p in 0..<8 {
        let start = 0.08 + 0.45 * Double(p) / 8.0 + 0.02 * rng.next()
        let freq = 2200.0 + 3000.0 * Double(p) / 8.0 + 250.0 * rng.next()
        var pingPhase = 0.0
        let s = Int(start * sampleRate)
        for j in 0..<sampleCount(0.05) where s + j < n {
            let t = Double(j) / sampleRate
            pingPhase += freq / sampleRate
            out[s + j] += sine(pingPhase) * percEnv(t, attack: 0.001, tau: 0.02) * 0.16
        }
    }
    return out
}

// MARK: - Ambience (seamless loop)

let ambienceDur = 24.0

/// ambience_forest.caf — ~24 s seamless night-forest bed: slow-gusting wind
/// (filtered brown noise; the gust LFOs complete whole cycles over the loop
/// so the dynamics are loop-periodic), sparse seeded cricket trills, and one
/// distant two-note owl hoot. The rendered tail is crossfaded back into the
/// head and the edges pinned to zero (same treatment as tools/musicgen), then
/// the whole bed is normalized to a low RMS (~0.07) so it sits under music.
func ambienceForest() -> [Double] {
    let loopFrames = sampleCount(ambienceDur)
    let pad = 4096
    let n = loopFrames + pad
    let T = Double(loopFrames) / sampleRate          // exact loop seconds
    var out = [Double](repeating: 0, count: n)

    // Wind: brown noise through a gust-modulated lowpass.
    var noise = NoiseSource(seed: 0xF03E57)
    var brown = 0.0
    var windLP = OnePoleLP(cutoff: 400)
    for i in 0..<n {
        let t = Double(i) / sampleRate
        brown = (brown + 0.023 * noise.next()) * 0.9992
        let g1 = sin(2.0 * .pi * 3.0 * t / T + 0.7)
        let g2 = sin(2.0 * .pi * 7.0 * t / T + 2.1)
        let gust = 0.55 + 0.45 * (0.6 * g1 + 0.4 * g2)
        windLP.set(cutoff: 260.0 + 340.0 * gust * gust)
        out[i] = windLP.process(brown) * (0.4 + 0.6 * gust)
    }
    normalizeRMS(&out, target: 0.12)                 // wind bed reference level

    // Crickets: sparse seeded trills (5–8 pulses of a high sine), kept clear
    // of the loop edges so no event straddles the fold.
    var rng = NoiseSource(seed: 0xC81C)
    for _ in 0..<13 {
        let start = 1.0 + (T - 3.0) * abs(rng.next())
        let f = 4100.0 + 700.0 * rng.next()
        let pulses = 5 + Int(abs(rng.next()) * 4.0)
        let rate = 32.0 + 10.0 * abs(rng.next())
        let gain = 0.05 + 0.05 * abs(rng.next())
        for p in 0..<pulses {
            let s = Int((start + Double(p) / rate) * sampleRate)
            var phase = 0.0
            for j in 0..<sampleCount(0.014) where s + j < loopFrames {
                let tt = Double(j) / sampleRate
                phase += f / sampleRate
                out[s + j] += sine(phase) * percEnv(tt, attack: 0.002, tau: 0.004) * gain
            }
        }
    }

    // One distant owl: two soft "hoo"s glissing gently down, lowpassed.
    var owlLP = OnePoleLP(cutoff: 900)
    for (hootIdx, hootStart) in [11.2, 11.85].enumerated() {
        let s = Int(hootStart * sampleRate)
        let hootDur = hootIdx == 0 ? 0.38 : 0.5
        var phase = 0.0
        for j in 0..<sampleCount(hootDur) where s + j < loopFrames {
            let tt = Double(j) / sampleRate
            let f = 345.0 * pow(0.86, tt / hootDur)
            phase += f / sampleRate
            let e = sin(min(tt / hootDur, 1.0) * .pi)
            out[s + j] += owlLP.process(sine(phase)) * e * e * 0.14
        }
    }

    // Fold the tail into the head (equal-power) and pin the edges to zero —
    // the loop boundary becomes an exact zero crossing (gate loopDelta = 0).
    for i in 0..<256 {
        let x = Double(i) / 256.0
        out[i] = out[i] * sin(x * .pi / 2.0) + out[loopFrames + i] * cos(x * .pi / 2.0)
    }
    for i in 0..<320 {
        let g: Double = i < 64 ? 0 : 0.5 - 0.5 * cos(Double(i - 64) / 256.0 * .pi)
        out[i] *= g
        out[loopFrames - 1 - i] *= g
    }
    out.removeLast(pad)
    normalizeRMS(&out, target: 0.07)                 // LOW bed level under music
    return out
}

// MARK: - File I/O

func writeCAF(_ samples: [Double], to url: URL) throws {
    guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                     sampleRate: sampleRate,
                                     channels: 1,
                                     interleaved: false) else {
        throw NSError(domain: "sfxgen", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "bad format"])
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings,
                               commonFormat: .pcmFormatFloat32, interleaved: false)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                        frameCapacity: AVAudioFrameCount(samples.count)),
          let channel = buffer.floatChannelData?[0] else {
        throw NSError(domain: "sfxgen", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "bad buffer"])
    }
    for (i, s) in samples.enumerated() { channel[i] = Float(s) }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    try file.write(from: buffer)
    // AVAudioFile flushes on deinit (end of scope).
}

/// Reads a written file back and prints its GATE line. Returns pass/fail.
/// One-shots gate on peak + RMS (loopDelta informational); the ambience loop
/// additionally gates on loopDelta < 0.02 and a low RMS band (0.04–0.12).
func gate(url: URL, name: String, isLoop: Bool) -> Bool {
    var peak = 0.0
    var sumSquares = 0.0
    var frames = 0
    var first = [Double]()
    var last = [Double]()
    do {
        let file = try AVAudioFile(forReading: url)
        guard let chunk = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                           frameCapacity: 1 << 16) else { return false }
        // AVAudioFile.read(into:) may return fewer frames than requested on
        // large files — stream in chunks until the whole file is consumed.
        while file.framePosition < file.length {
            try file.read(into: chunk)
            let m = Int(chunk.frameLength)
            guard m > 0, let channel = chunk.floatChannelData?[0] else { break }
            for i in 0..<m {
                let s = Double(channel[i])
                peak = max(peak, abs(s))
                sumSquares += s * s
                if first.count < 64 { first.append(s) }
                last.append(s)
            }
            if last.count > 64 { last.removeFirst(last.count - 64) }
            frames += m
        }
        guard frames > 128 else { return false }
    } catch {
        print("GATE \(name) peak=0 rms=0 loopDelta=0 FAIL (unreadable: \(error.localizedDescription))")
        return false
    }
    let rms = (sumSquares / Double(frames)).squareRoot()
    var loopDelta = 0.0
    for i in 0..<64 { loopDelta += abs(first[i] - last[i]) }
    loopDelta /= 64.0
    let rmsOK = isLoop ? (rms >= 0.04 && rms <= 0.12) : (rms >= 0.02 && rms <= 0.5)
    let pass = peak < 0.98 && rmsOK && (!isLoop || loopDelta < 0.02)
    print(String(format: "GATE %@ peak=%.3f rms=%.3f loopDelta=%.4f %@",
                 name, peak, rms, loopDelta, pass ? "PASS" : "FAIL"))
    return pass
}

// MARK: - Main

guard CommandLine.arguments.count >= 2 else {
    print("usage: swift tools/sfxgen/main.swift <outputDir>")
    exit(2)
}
let outputDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let sounds: [(name: String, render: () -> [Double], isLoop: Bool)] = [
    ("laser", slash, false),
    ("hit", hit, false),
    ("explosion", explosion, false),
    ("pickup", pickup, false),
    ("levelup", levelup, false),
    ("uitick", uitick, false),
    ("bossroar", bossroar, false),
    ("revive", revive, false),
    ("ambience_forest", ambienceForest, true),
]

var allPass = true
for sound in sounds {
    var samples = sound.render()
    if !sound.isLoop {
        normalize(&samples)          // one-shots peak-normalize to 0.85
        fadeTail(&samples)           // loop edges are already pinned to zero
    }
    let url = outputDir.appendingPathComponent("\(sound.name).caf")
    do {
        try writeCAF(samples, to: url)
    } catch {
        print("GATE \(sound.name).caf peak=0 rms=0 loopDelta=0 FAIL (write: \(error.localizedDescription))")
        allPass = false
        continue
    }
    if !gate(url: url, name: "\(sound.name).caf", isLoop: sound.isLoop) { allPass = false }
}

exit(allPass ? 0 : 1)
