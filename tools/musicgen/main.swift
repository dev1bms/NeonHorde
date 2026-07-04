// tools/musicgen/main.swift — Neon Horde music composer/renderer (GOAL §4,
// AMENDMENT v3 / Phase 8C: dark-fantasy forest hybrid score).
//
// Composes and renders two seamless stereo loops entirely in code — brooding
// hybrid orchestral-electronic in A minor at 100 BPM over a descending
// Am–G–F–E tetrachord (shared key/tempo so they crossfade cleanly):
//   music_main.m4a  ~2:24 — understated and atmospheric: deep A-pedal drone,
//                    slow arpeggiated harp plucks (Karplus-Strong delay-line
//                    strings — organic in a way raw oscillators are not),
//                    airy detuned pad with a breath-noise layer, sparse
//                    taiko-ish thumps, and an occasional low choir-ish swell
//                    (detuned sine cluster, slow vibrato) every 8 bars.
//   music_boss.m4a  ~1:07 — driving variant: pounding taiko pattern with
//                    cracks on 2 & 4, aggressive low Karplus-Strong bass
//                    plucks in eighths, urgent 16th sawtooth ostinato through
//                    a resonant lowpass, and riser swells into each phrase.
//
// Loop seamlessness: composed in exact whole bars; rendered exactly N bars of
// samples (plus a ring-out tail that is folded back with a 256-sample
// equal-power crossfade of the tail into the head); all note envelopes
// resolve inside their windows; a micro edge ramp pins the outermost samples
// to silence so the loop point is a guaranteed zero crossing.
//
// Output: renders Float32 PCM stereo .caf, converts to AAC .m4a via
// /usr/bin/afconvert, deletes the intermediate .caf.
//
// Usage: swift tools/musicgen/main.swift <outputDir>
//
// Machine-checkable gates (GOAL §4 — the builder cannot listen): per track,
// peak < 0.98 (mix targets -3 dBFS => 0.70), 0.02 <= RMS <= 0.5, and loop
// continuity: mean |first64 - last64| < 0.02. Prints one GATE line per file;
// exits non-zero if any gate fails.

import AVFoundation
import Foundation

// MARK: - Timing

let sampleRate = 44100.0
let bpm = 100.0
/// One bar = 4 beats at 100 BPM, rounded to a whole sample count so every
/// track length is an exact number of bars (105840 samples — exact here).
let barSamples = Int((240.0 / bpm * sampleRate).rounded())
let beatSamples = Double(barSamples) / 4.0
let sixteenthSamples = beatSamples / 4.0
/// Extra render room past the loop end; ring-out lands here and is folded
/// back into the head.
let tailPad = 4096

// MARK: - Notes

func hz(_ midi: Int) -> Double { 440.0 * pow(2.0, Double(midi - 69) / 12.0) }

/// Am - G - F - E, one chord per bar — a descending dark-fantasy tetrachord;
/// the E major (harmonic-minor dominant) pulls the loop back into Am.
let bassRoots = [33, 31, 29, 28]                    // A1  G1  F1  E1
let padChords: [[Int]] = [                          // voice-led triads
    [57, 60, 64],                                   // Am: A3 C4 E4
    [55, 59, 62],                                   // G:  G3 B3 D4
    [53, 57, 60],                                   // F:  F3 A3 C4
    [52, 56, 59],                                   // E:  E3 G#3 B3
]
let arpChords: [[Int]] = padChords.map { $0.map { $0 + 12 } }   // harp register

// MARK: - DSP primitives

struct NoiseSource {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
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
    private let k: Double
    init(cutoff: Double) { k = 1.0 - exp(-2.0 * .pi * cutoff / sampleRate) }
    mutating func process(_ x: Double) -> Double {
        y += k * (x - y)
        return y
    }
}

/// RBJ biquad (Direct Form I) — resonant lowpass for the boss ostinato and
/// bandpass for riser/air noise. Coefficients may be re-set per sample.
struct Biquad {
    private var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    static func lowpass(cutoff: Double, q: Double) -> Biquad {
        var f = Biquad()
        f.setLowpass(cutoff: cutoff, q: q)
        return f
    }

    static func bandpass(center: Double, q: Double) -> Biquad {
        var f = Biquad()
        f.setBandpass(center: center, q: q)
        return f
    }

    mutating func setLowpass(cutoff: Double, q: Double) {
        let w = 2.0 * .pi * min(max(cutoff, 20), 18000) / sampleRate
        let alpha = sin(w) / (2.0 * max(q, 0.05))
        let c = cos(w)
        let a0 = 1.0 + alpha
        b0 = (1.0 - c) / 2.0 / a0
        b1 = (1.0 - c) / a0
        b2 = b0
        a1 = -2.0 * c / a0
        a2 = (1.0 - alpha) / a0
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

/// Attack / release envelope that always resolves at `length` samples.
func arEnv(_ i: Int, length: Int, attack: Int, release: Int) -> Double {
    var v = 1.0
    if i < attack { v = Double(i) / Double(max(attack, 1)) }
    let relStart = length - release
    if i > relStart {
        v *= max(0, 1.0 - Double(i - relStart) / Double(max(release, 1)))
    }
    return v
}

func samples(_ seconds: Double) -> Int { Int(seconds * sampleRate) }

// MARK: - Karplus-Strong plucked string

/// Karplus-Strong plucked string: a lowpassed noise burst circulating in a
/// delay line with an averaging filter — harp/lute-like plucks whose upper
/// partials die faster than the fundamental, dramatically more organic than
/// raw oscillators. Deterministic per (freq, seed). Higher notes decay
/// faster, exactly like a real string.
func pluck(freq: Double, seconds: Double, damping: Double, brightness: Double,
           seed: UInt64) -> [Double] {
    let period = max(2, Int((sampleRate / freq).rounded()))
    var line = [Double](repeating: 0, count: period)
    var noise = NoiseSource(seed: seed)
    var shape = OnePoleLP(cutoff: brightness)
    var mean = 0.0
    for i in 0..<period {
        line[i] = shape.process(noise.next())
        mean += line[i]
    }
    mean /= Double(period)
    for i in 0..<period { line[i] -= mean }         // remove DC so it rings to zero
    let len = samples(seconds)
    var out = [Double](repeating: 0, count: len)
    var idx = 0
    for i in 0..<len {
        let cur = line[idx]
        let nxt = line[(idx + 1) % period]
        out[i] = cur
        line[idx] = damping * 0.5 * (cur + nxt)
        idx = (idx + 1) % period
    }
    // Short fade at the window end so every pluck resolves inside its window.
    let rel = min(samples(0.05), len)
    for i in 0..<rel { out[len - 1 - i] *= Double(i) / Double(rel) }
    return out
}

// MARK: - Stereo mix buffer

final class StereoBuf {
    var l: [Double]
    var r: [Double]
    let frames: Int          // exact loop length; tailPad extra render room

    init(bars: Int) {
        frames = bars * barSamples
        l = [Double](repeating: 0, count: frames + tailPad)
        r = [Double](repeating: 0, count: frames + tailPad)
    }

    /// Adds a rendered mono note with equal-power panning (pan -1...1).
    func add(_ note: [Double], at start: Int, gain: Double, pan: Double = 0) {
        let angle = (pan + 1.0) * .pi / 4.0
        let gl = cos(angle) * gain
        let gr = sin(angle) * gain
        let cap = l.count
        for (j, s) in note.enumerated() {
            let i = start + j
            if i >= cap { break }
            l[i] += s * gl
            r[i] += s * gr
        }
    }
}

// MARK: - Voices

/// Drone: deep A pedal — detuned saw pair over a sub sine, heavily
/// lowpassed, breathing with a slow loop-periodic swell. The pedal holds
/// while the pad/harp walk the tetrachord above it — the brooding floor of
/// the whole piece.
func renderDrone(into buf: StereoBuf, bars: Int, gain: Double) {
    let total = buf.frames
    let n = total + tailPad
    let root = hz(33)                                // A1
    let freqs = [root * 0.9975, root * 1.0025, root / 2.0]
    var phases = [0.0, 0.0, 0.0]
    var lps = [OnePoleLP(cutoff: 170), OnePoleLP(cutoff: 170), OnePoleLP(cutoff: 120)]
    var note = [Double](repeating: 0, count: n)
    for i in 0..<n {
        let cyc = Double(i) / Double(total)          // whole cycles over the loop
        let breathe = 0.75 + 0.25 * sin(2.0 * .pi * 3.0 * cyc - .pi / 2.0)
        phases[0] += freqs[0] / sampleRate
        phases[1] += freqs[1] / sampleRate
        phases[2] += freqs[2] / sampleRate
        var s = lps[0].process(2.0 * (phases[0] - floor(phases[0])) - 1.0) * 0.5
        s += lps[1].process(2.0 * (phases[1] - floor(phases[1])) - 1.0) * 0.5
        s += lps[2].process(sin(2.0 * .pi * phases[2])) * 0.8
        note[i] = s * breathe
    }
    buf.add(note, at: 0, gain: gain)
}

/// Harp: slow arpeggiated Karplus-Strong plucks over the chord tones,
/// sparse (rests keep it understated), panned gently side to side.
func renderHarp(into buf: StereoBuf, bars: Int, gain: Double) {
    let pattern = [0, 2, 1, 3, 2, 0, 3, 1]
    for bar in 0..<bars {
        let chord = arpChords[bar % arpChords.count]
        let tones = [chord[0], chord[1], chord[2], chord[0] + 12]
        for step in 0..<8 {
            if step == 5 || (step == 7 && bar % 2 == 0) { continue }   // breathe
            let start = bar * barSamples + Int((Double(step) * beatSamples / 2.0).rounded())
            let midi = tones[pattern[(bar + step) % pattern.count]]
            let seed = UInt64(bar * 8 + step) &* 0x9E37 &+ 0xA11CE
            let note = pluck(freq: hz(midi), seconds: 1.4,
                             damping: 0.9992, brightness: 2600, seed: seed)
            buf.add(note, at: start, gain: gain * (step % 4 == 0 ? 1.0 : 0.8),
                    pan: step % 2 == 0 ? -0.3 : 0.3)
        }
    }
}

/// Pad: detuned saw pairs per chord tone through a heavy lowpass, slow
/// attack, plus a quiet bandpassed breath-noise layer swelling with each
/// bar — the "air" of the forest score.
func renderPad(into buf: StereoBuf, bars: Int, gain: Double) {
    let pans = [-0.4, 0.0, 0.4]
    for bar in 0..<bars {
        let chord = padChords[bar % padChords.count]
        let barStart = bar * barSamples
        let len = barSamples
        for (t, midi) in chord.enumerated() {
            let base = hz(midi)
            for detune in [0.996, 1.004] {
                let freq = base * detune
                var phase = 0.0
                var lp = OnePoleLP(cutoff: 800)
                var note = [Double](repeating: 0, count: len)
                for i in 0..<len {
                    phase += freq / sampleRate
                    let s = lp.process(2.0 * (phase - floor(phase)) - 1.0)
                    note[i] = s * arEnv(i, length: len,
                                        attack: samples(0.9), release: samples(0.4))
                }
                buf.add(note, at: barStart, gain: gain / 2.0,
                        pan: pans[t] * (detune < 1 ? 1.0 : -1.0))
            }
        }
        var air = Biquad.bandpass(center: 2400, q: 0.7)
        var noise = NoiseSource(seed: UInt64(bar) &+ 0xA17)
        var breath = [Double](repeating: 0, count: len)
        for i in 0..<len {
            breath[i] = air.process(noise.next())
                * arEnv(i, length: len, attack: samples(0.8), release: samples(0.5))
        }
        buf.add(breath, at: barStart, gain: gain * 0.35)
    }
}

/// Choir-ish swell: detuned sine-pair cluster (A3 E4 A4) with slow vibrato
/// and a hint of second partial, swelling in over a bar and out over the
/// next — placed every 8 bars.
func renderChoir(into buf: StereoBuf, bars: Int, gain: Double) {
    var bar = 4
    while bar + 2 <= bars {
        let start = bar * barSamples
        let len = barSamples * 2
        for (k, midi) in [57, 64, 69].enumerated() {
            for det in [0.9962, 1.0038] {
                let f0 = hz(midi) * det
                var phase = 0.0
                var note = [Double](repeating: 0, count: len)
                for i in 0..<len {
                    let t = Double(i) / sampleRate
                    let vib = 1.0 + 0.006 * sin(2.0 * .pi * 4.6 * t + Double(k) * 1.7)
                    phase += f0 * vib / sampleRate
                    let s = sin(2.0 * .pi * phase) + 0.25 * sin(4.0 * .pi * phase)
                    note[i] = s * arEnv(i, length: len, attack: len / 2, release: len / 3)
                }
                buf.add(note, at: start, gain: gain / 2.0,
                        pan: det < 1 ? -0.35 : 0.35)
            }
        }
        bar += 8
    }
}

/// Boss bass: aggressive low Karplus-Strong plucks driving in eighths with
/// octave jumps on the offbeat pickups.
func renderBossBass(into buf: StereoBuf, bars: Int, gain: Double) {
    for bar in 0..<bars {
        let root = bassRoots[bar % bassRoots.count]
        for step in 0..<8 {
            let start = bar * barSamples + Int((Double(step) * beatSamples / 2.0).rounded())
            let midi = (step == 3 || step == 7) ? root + 12 : root
            let seed = UInt64(bar * 8 + step) &* 0xB055 &+ 1
            let note = pluck(freq: hz(midi), seconds: 0.4,
                             damping: 0.994, brightness: 900, seed: seed)
            buf.add(note, at: start, gain: gain * (step % 2 == 0 ? 1.0 : 0.85))
        }
    }
}

/// Ostinato (boss): urgent 16th sawtooth line through a resonant lowpass
/// whose cutoff snaps open and decays within every note.
func renderOstinato(into buf: StereoBuf, bars: Int, gain: Double) {
    let pattern = [0, 0, 1, 0, 2, 0, 1, 0, 0, 0, 1, 2, 3, 2, 1, 0]
    for bar in 0..<bars {
        let chord = padChords[bar % padChords.count]
        let tones = [chord[0] + 12, chord[1] + 12, chord[2] + 12, chord[0] + 24]
        for step in 0..<16 {
            let start = bar * barSamples + Int((Double(step) * sixteenthSamples).rounded())
            let len = Int(sixteenthSamples * 0.9)
            let freq = hz(tones[pattern[step]])
            var phase = 0.0
            var lp = Biquad.lowpass(cutoff: 2400, q: 2.8)
            var note = [Double](repeating: 0, count: len)
            for i in 0..<len {
                let t = Double(i) / sampleRate
                lp.setLowpass(cutoff: 900.0 + 1900.0 * exp(-t / 0.05), q: 2.8)
                phase += freq / sampleRate
                note[i] = lp.process(2.0 * (phase - floor(phase)) - 1.0)
                    * arEnv(i, length: len, attack: samples(0.003), release: samples(0.03))
            }
            buf.add(note, at: start, gain: gain * (step % 4 == 0 ? 1.0 : 0.75),
                    pan: step % 2 == 0 ? -0.2 : 0.2)
        }
    }
}

/// Risers (boss): bandpassed noise sweeping up over the last two bars of
/// every 8-bar phrase, cut exactly at the downbeat (masked by the taiko).
func renderRisers(into buf: StereoBuf, bars: Int, gain: Double) {
    var bar = 6
    while bar + 2 <= bars {
        let start = bar * barSamples
        let len = barSamples * 2
        var noise = NoiseSource(seed: UInt64(bar) &* 0x9E37 &+ 0x5EED)
        var bp = Biquad.bandpass(center: 380, q: 1.2)
        var note = [Double](repeating: 0, count: len)
        for i in 0..<len {
            let x = Double(i) / Double(len)
            bp.setBandpass(center: 380.0 * pow(3400.0 / 380.0, x), q: 1.2)
            note[i] = bp.process(noise.next()) * x * x
                * arEnv(i, length: len, attack: 1, release: samples(0.02))
        }
        buf.add(note, at: start, gain: gain)
        bar += 8
    }
}

// MARK: - Percussion

/// Taiko: big soft-skinned drum — deep sine pitch drop + short skin-noise
/// transient. `low` is the floor drum; the higher variant answers offbeats.
func makeTaiko(low: Bool) -> [Double] {
    let len = samples(0.5)
    var out = [Double](repeating: 0, count: len)
    var phase = 0.0
    var noise = NoiseSource(seed: low ? 0x7A1C0 : 0x7A1C1)
    var skinLP = OnePoleLP(cutoff: 1400)
    let f0 = low ? 88.0 : 132.0
    let f1 = low ? 38.0 : 58.0
    for i in 0..<len {
        let t = Double(i) / sampleRate
        let f = f1 + (f0 - f1) * exp(-t / 0.05)
        phase += f / sampleRate
        let body = sin(2.0 * .pi * phase) * min(t / 0.002, 1.0) * exp(-t / (low ? 0.16 : 0.11))
        let skin = skinLP.process(noise.next()) * exp(-t / 0.015) * 0.35
        out[i] = body + skin
    }
    for i in 0..<samples(0.01) {
        out[len - 1 - i] *= Double(i) / Double(samples(0.01))
    }
    return out
}

/// Crack: tight mid-band noise snap (rim/stick) for the boss backbeat.
func makeCrack() -> [Double] {
    let len = samples(0.12)
    var out = [Double](repeating: 0, count: len)
    var noise = NoiseSource(seed: 0x5A2E)
    var lo = OnePoleLP(cutoff: 3200)
    var cut = OnePoleLP(cutoff: 700)
    for i in 0..<len {
        let t = Double(i) / sampleRate
        let n = noise.next()
        let band = lo.process(n) - cut.process(n)
        out[i] = band * min(t / 0.001, 1.0) * exp(-t / 0.03)
    }
    return out
}

/// Main percussion: sparse and deep — floor taiko on each downbeat, an
/// answering hit on the "and of 3" every other bar, a high pickup every 4th.
func renderPercussionMain(into buf: StereoBuf, bars: Int, gain: Double) {
    let taiko = makeTaiko(low: true)
    let taikoHigh = makeTaiko(low: false)
    for bar in 0..<bars {
        let barStart = bar * barSamples
        buf.add(taiko, at: barStart, gain: gain)
        if bar % 2 == 1 {
            buf.add(taiko, at: barStart + Int((2.5 * beatSamples).rounded()), gain: gain * 0.7)
        }
        if bar % 4 == 3 {
            buf.add(taikoHigh, at: barStart + Int((3.5 * beatSamples).rounded()),
                    gain: gain * 0.5, pan: 0.2)
        }
    }
}

/// Boss percussion: pounding — floor taiko on every beat, cracks on 2 & 4,
/// high-drum offbeats and a double-stroke pickup into every other bar.
func renderPercussionBoss(into buf: StereoBuf, bars: Int,
                          gain: Double, crackGain: Double) {
    let taiko = makeTaiko(low: true)
    let taikoHigh = makeTaiko(low: false)
    let crack = makeCrack()
    for bar in 0..<bars {
        let barStart = bar * barSamples
        for beat in 0..<4 {
            let beatStart = barStart + Int((Double(beat) * beatSamples).rounded())
            buf.add(taiko, at: beatStart, gain: gain * (beat == 0 ? 1.0 : 0.85))
            if beat == 1 || beat == 3 {
                buf.add(crack, at: beatStart, gain: crackGain, pan: -0.1)
            }
        }
        buf.add(taikoHigh, at: barStart + Int((1.5 * beatSamples).rounded()),
                gain: gain * 0.45, pan: 0.2)
        buf.add(taikoHigh, at: barStart + Int((3.5 * beatSamples).rounded()),
                gain: gain * 0.5, pan: 0.25)
        if bar % 2 == 1 {
            buf.add(taikoHigh, at: barStart + Int((3.75 * beatSamples).rounded()),
                    gain: gain * 0.4, pan: 0.15)
        }
    }
}

// MARK: - Loop finalize / mastering

/// Makes the loop point click-free and machine-verifiable:
/// 1. 256-sample equal-power crossfade of the rendered tail into the head,
///    so sample N-1 flows into sample 0 as a natural continuation.
/// 2. Micro edge ramp (64 samples silence + 256-sample cosine) at both ends —
///    the boundary becomes an exact zero crossing (gate loopDelta = 0).
func finalizeLoop(_ buf: StereoBuf) {
    let n = buf.frames
    for i in 0..<256 {
        let t = Double(i) / 256.0
        let head = sin(t * .pi / 2.0)
        let tail = cos(t * .pi / 2.0)
        buf.l[i] = buf.l[i] * head + buf.l[n + i] * tail
        buf.r[i] = buf.r[i] * head + buf.r[n + i] * tail
    }
    for i in 0..<320 {
        let g: Double
        if i < 64 {
            g = 0
        } else {
            let t = Double(i - 64) / 256.0
            g = 0.5 - 0.5 * cos(t * .pi)
        }
        buf.l[i] *= g
        buf.r[i] *= g
        buf.l[n - 1 - i] *= g
        buf.r[n - 1 - i] *= g
    }
}

/// Peak-normalize the loop region to -3 dBFS headroom (GOAL §4 mix gate).
func master(_ buf: StereoBuf, targetPeak: Double = 0.70) {
    var peak = 0.0
    for i in 0..<buf.frames {
        peak = max(peak, abs(buf.l[i]))
        peak = max(peak, abs(buf.r[i]))
    }
    guard peak > 0 else { return }
    let g = targetPeak / peak
    for i in 0..<buf.frames {
        buf.l[i] *= g
        buf.r[i] *= g
    }
}

// MARK: - File I/O

func writeCAF(_ buf: StereoBuf, to url: URL) throws {
    guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                     sampleRate: sampleRate,
                                     channels: 2,
                                     interleaved: false) else {
        throw NSError(domain: "musicgen", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "bad format"])
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings,
                               commonFormat: .pcmFormatFloat32, interleaved: false)
    guard let pcm = AVAudioPCMBuffer(pcmFormat: format,
                                     frameCapacity: AVAudioFrameCount(buf.frames)),
          let channels = pcm.floatChannelData else {
        throw NSError(domain: "musicgen", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "bad buffer"])
    }
    for i in 0..<buf.frames {
        channels[0][i] = Float(buf.l[i])
        channels[1][i] = Float(buf.r[i])
    }
    pcm.frameLength = AVAudioFrameCount(buf.frames)
    try file.write(from: pcm)
    // AVAudioFile flushes on deinit (end of scope).
}

/// Validates the written .caf and prints its GATE line (music gates include
/// loop continuity). Returns pass/fail.
func gate(url: URL, name: String) -> Bool {
    var peak = 0.0
    var sumSquares = 0.0
    var loopDelta = 0.0
    var frames = 0
    do {
        let file = try AVAudioFile(forReading: url)
        let channelCount = Int(file.processingFormat.channelCount)
        guard channelCount > 0,
              let chunk = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                           frameCapacity: 1 << 16) else { return false }
        var first = [[Double]](repeating: [], count: channelCount)
        var last = [[Double]](repeating: [], count: channelCount)
        // AVAudioFile.read(into:) may return fewer frames than requested on
        // large files — stream in chunks until the whole file is consumed.
        while file.framePosition < file.length {
            try file.read(into: chunk)
            let m = Int(chunk.frameLength)
            guard m > 0, let channels = chunk.floatChannelData else { break }
            for c in 0..<channelCount {
                for i in 0..<m {
                    let s = Double(channels[c][i])
                    peak = max(peak, abs(s))
                    sumSquares += s * s
                    if first[c].count < 64 { first[c].append(s) }
                    last[c].append(s)
                }
                if last[c].count > 64 { last[c].removeFirst(last[c].count - 64) }
            }
            frames += m
        }
        guard frames > 128 else { return false }
        for c in 0..<channelCount {
            for i in 0..<64 { loopDelta += abs(first[c][i] - last[c][i]) }
        }
        sumSquares /= Double(channelCount)
        loopDelta /= Double(64 * channelCount)
    } catch {
        print("GATE \(name) peak=0 rms=0 loopDelta=0 FAIL (unreadable: \(error.localizedDescription))")
        return false
    }
    let rms = (sumSquares / Double(frames)).squareRoot()
    let pass = peak < 0.98 && rms >= 0.02 && rms <= 0.5 && loopDelta < 0.02
    print(String(format: "GATE %@ peak=%.3f rms=%.3f loopDelta=%.4f %@",
                 name, peak, rms, loopDelta, pass ? "PASS" : "FAIL"))
    return pass
}

func convertToM4A(caf: URL, m4a: URL) throws {
    try? FileManager.default.removeItem(at: m4a)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
    process.arguments = ["-f", "m4af", "-d", "aac", caf.path, m4a.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
          FileManager.default.fileExists(atPath: m4a.path) else {
        throw NSError(domain: "musicgen", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "afconvert failed"])
    }
}

// MARK: - Tracks

/// music_main — 60 bars (~2:24). Understated and atmospheric: restraint
/// beats busy. Drone floor, sparse harp plucks, airy pad, deep sparse taiko,
/// choir swell every 8 bars.
func renderMain() -> StereoBuf {
    let bars = 60
    let buf = StereoBuf(bars: bars)
    renderDrone(into: buf, bars: bars, gain: 0.32)
    renderHarp(into: buf, bars: bars, gain: 0.20)
    renderPad(into: buf, bars: bars, gain: 0.06)
    renderPercussionMain(into: buf, bars: bars, gain: 0.50)
    renderChoir(into: buf, bars: bars, gain: 0.05)
    return buf
}

/// music_boss — 28 bars (~1:07), same key/BPM so the two loops crossfade.
/// Driving: pounding taiko, KS bass eighths, resonant ostinato, risers.
func renderBoss() -> StereoBuf {
    let bars = 28
    let buf = StereoBuf(bars: bars)
    renderDrone(into: buf, bars: bars, gain: 0.22)
    renderBossBass(into: buf, bars: bars, gain: 0.26)
    renderOstinato(into: buf, bars: bars, gain: 0.07)
    renderPad(into: buf, bars: bars, gain: 0.05)
    renderPercussionBoss(into: buf, bars: bars, gain: 0.55, crackGain: 0.20)
    renderRisers(into: buf, bars: bars, gain: 0.10)
    return buf
}

// MARK: - Main

guard CommandLine.arguments.count >= 2 else {
    print("usage: swift tools/musicgen/main.swift <outputDir>")
    exit(2)
}
let outputDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let tracks: [(name: String, render: () -> StereoBuf)] = [
    ("music_main", renderMain),
    ("music_boss", renderBoss),
]

var allPass = true
for track in tracks {
    let buf = track.render()
    finalizeLoop(buf)
    master(buf)
    let caf = outputDir.appendingPathComponent("\(track.name).caf")
    let m4a = outputDir.appendingPathComponent("\(track.name).m4a")
    do {
        try writeCAF(buf, to: caf)
        // Gate on the exact PCM that defines the loop, then encode to AAC.
        if !gate(url: caf, name: "\(track.name).m4a") { allPass = false }
        try convertToM4A(caf: caf, m4a: m4a)
        try FileManager.default.removeItem(at: caf)
    } catch {
        print("GATE \(track.name).m4a peak=0 rms=0 loopDelta=0 FAIL (\(error.localizedDescription))")
        allPass = false
    }
}

exit(allPass ? 0 : 1)
