// tools/sfxgen/main.swift — Neon Horde SFX synthesizer (GOAL §4 Audio & Haptics).
//
// Synthesizes every gameplay sound effect as code — sfxr-style Float32 PCM
// computed sample-by-sample (sine/square/saw/noise oscillators, ADSR
// envelopes, one-pole lowpass) and written as mono 44.1 kHz .caf files via
// AVAudioFile. No downloaded assets, no offline engine.
//
// Usage: swift tools/sfxgen/main.swift <outputDir>
//
// Machine-checkable gates (GOAL §4 — the builder cannot listen): every file
// must satisfy peak < 0.98 (no clipping) and 0.02 <= RMS <= 0.5. One
// `GATE <name> peak=<v> rms=<v> loopDelta=<v> PASS|FAIL` line per file;
// exits non-zero if any gate fails. (loopDelta is informational for one-shot
// SFX; it is only a pass criterion for music loops in tools/musicgen.)

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

/// Linear-attack / linear-decay-to-sustain / linear-release envelope.
/// Release always completes exactly at `duration` so every sound resolves.
struct ADSR {
    var attack: Double
    var decay: Double
    var sustain: Double
    var release: Double

    func level(at t: Double, duration: Double) -> Double {
        if t < 0 || t >= duration { return 0 }
        var v: Double
        if t < attack {
            v = t / max(attack, 1e-6)
        } else if t < attack + decay {
            v = 1.0 + (sustain - 1.0) * (t - attack) / max(decay, 1e-6)
        } else {
            v = sustain
        }
        let gate = duration - release
        if t > gate {
            v *= max(0, 1.0 - (t - gate) / max(release, 1e-6))
        }
        return max(0, v)
    }
}

/// Percussive exponential decay with a very short linear attack (click-free).
func percEnv(_ t: Double, attack: Double, tau: Double) -> Double {
    min(t / max(attack, 1e-6), 1.0) * exp(-t / tau)
}

func sine(_ phase: Double) -> Double { sin(2.0 * .pi * phase) }
func square(_ phase: Double) -> Double { (phase - floor(phase)) < 0.5 ? 1.0 : -1.0 }
func saw(_ phase: Double) -> Double { 2.0 * (phase - floor(phase)) - 1.0 }

func sampleCount(_ duration: Double) -> Int { Int(duration * sampleRate) }

/// Peak-normalize in place (target < 0.98 clipping gate, with margin).
func normalize(_ samples: inout [Double], peak target: Double = 0.85) {
    var peak = 0.0
    for s in samples { peak = max(peak, abs(s)) }
    guard peak > 0 else { return }
    let g = target / peak
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

// MARK: - Sounds

/// laser.caf — descending square-wave zap, pitch sweep 880 -> 220 Hz, fast decay.
func laser() -> [Double] {
    let dur = 0.15
    let n = sampleCount(dur)
    var out = [Double](repeating: 0, count: n)
    var phase = 0.0
    var lp = OnePoleLP(cutoff: 5200)
    for i in 0..<n {
        let t = Double(i) / sampleRate
        let f = 880.0 * pow(220.0 / 880.0, t / dur)
        phase += f / sampleRate
        let env = percEnv(t, attack: 0.002, tau: 0.045)
        out[i] = lp.process(square(phase)) * env
    }
    return out
}

/// hit.caf — noise burst + low sine thump, sharp attack.
func hit() -> [Double] {
    let dur = 0.12
    let n = sampleCount(dur)
    var out = [Double](repeating: 0, count: n)
    var noise = NoiseSource(seed: 0xDEAD)
    var lp = OnePoleLP(cutoff: 1800)
    var phase = 0.0
    for i in 0..<n {
        let t = Double(i) / sampleRate
        let burst = lp.process(noise.next()) * percEnv(t, attack: 0.001, tau: 0.028) * 0.9
        let f = 90.0 * pow(50.0 / 90.0, t / dur)
        phase += f / sampleRate
        let thump = sine(phase) * percEnv(t, attack: 0.001, tau: 0.05)
        out[i] = burst + thump
    }
    return out
}

/// explosion.caf — filtered noise boom, exponential decay + sine drop 120 -> 40 Hz.
func explosion() -> [Double] {
    let dur = 0.5
    let n = sampleCount(dur)
    var out = [Double](repeating: 0, count: n)
    var noise = NoiseSource(seed: 0xB00B)
    var lp = OnePoleLP(cutoff: 3000)
    var phase = 0.0
    for i in 0..<n {
        let t = Double(i) / sampleRate
        lp.set(cutoff: 3000.0 * pow(220.0 / 3000.0, t / dur))
        let boom = lp.process(noise.next()) * percEnv(t, attack: 0.003, tau: 0.13)
        let f = 120.0 * pow(40.0 / 120.0, t / dur)
        phase += f / sampleRate
        let drop = sine(phase) * percEnv(t, attack: 0.002, tau: 0.18) * 0.8
        // Hard fade over the final 30 ms so the file resolves to silence.
        let tailGate = min(1.0, (dur - t) / 0.03)
        out[i] = (boom + drop) * tailGate
    }
    return out
}

/// pickup.caf — two quick ascending sine blips (E5 -> A5), bright.
func pickup() -> [Double] {
    let dur = 0.12
    let n = sampleCount(dur)
    var out = [Double](repeating: 0, count: n)
    let blips: [(start: Double, freq: Double, len: Double)] = [
        (0.0, 659.255, 0.055),   // E5
        (0.06, 880.0, 0.06),     // A5
    ]
    let env = ADSR(attack: 0.002, decay: 0.02, sustain: 0.55, release: 0.02)
    for blip in blips {
        var phase = 0.0
        let start = Int(blip.start * sampleRate)
        let len = sampleCount(blip.len)
        for j in 0..<len where start + j < n {
            let t = Double(j) / sampleRate
            phase += blip.freq / sampleRate
            // Second harmonic for brightness.
            let tone = sine(phase) + 0.35 * sine(phase * 2.0)
            out[start + j] += tone * env.level(at: t, duration: blip.len)
        }
    }
    return out
}

/// levelup.caf — ascending square arpeggio A4-C5-E5-A5, celebratory.
func levelup() -> [Double] {
    let dur = 0.45
    let n = sampleCount(dur)
    var out = [Double](repeating: 0, count: n)
    let notes: [(start: Double, freq: Double, len: Double)] = [
        (0.00, 440.000, 0.12),   // A4
        (0.10, 523.251, 0.12),   // C5
        (0.20, 659.255, 0.12),   // E5
        (0.30, 880.000, 0.15),   // A5 — rings a touch longer
    ]
    for note in notes {
        var phase = 0.0
        var lp = OnePoleLP(cutoff: 3200)
        let env = ADSR(attack: 0.004, decay: 0.05, sustain: 0.5, release: 0.05)
        let start = Int(note.start * sampleRate)
        let len = sampleCount(note.len)
        for j in 0..<len where start + j < n {
            let t = Double(j) / sampleRate
            phase += note.freq / sampleRate
            out[start + j] += lp.process(square(phase)) * env.level(at: t, duration: note.len)
        }
    }
    return out
}

/// uitick.caf — single short click/blip.
func uitick() -> [Double] {
    let dur = 0.05
    let n = sampleCount(dur)
    var out = [Double](repeating: 0, count: n)
    var phase = 0.0
    var noise = NoiseSource(seed: 0x71C4)
    var lp = OnePoleLP(cutoff: 4500)
    for i in 0..<n {
        let t = Double(i) / sampleRate
        phase += 1600.0 / sampleRate
        let blip = sine(phase) * percEnv(t, attack: 0.0008, tau: 0.009)
        let click = lp.process(noise.next()) * percEnv(t, attack: 0.0005, tau: 0.002) * 0.4
        out[i] = blip + click
    }
    return out
}

/// bossroar.caf — low detuned saw cluster 55-65 Hz, slow AM wobble + noise swell.
func bossroar() -> [Double] {
    let dur = 1.0
    let n = sampleCount(dur)
    var out = [Double](repeating: 0, count: n)
    let freqs = [55.0, 58.0, 61.5, 65.0]
    var phases = [Double](repeating: 0, count: freqs.count)
    var noise = NoiseSource(seed: 0x50A2)
    var clusterLP = OnePoleLP(cutoff: 520)
    var noiseLP = OnePoleLP(cutoff: 900)
    let master = ADSR(attack: 0.08, decay: 0.1, sustain: 0.9, release: 0.3)
    for i in 0..<n {
        let t = Double(i) / sampleRate
        var cluster = 0.0
        for (k, f) in freqs.enumerated() {
            phases[k] += f / sampleRate
            cluster += saw(phases[k])
        }
        cluster = clusterLP.process(cluster / Double(freqs.count))
        let wobble = 0.65 + 0.35 * sin(2.0 * .pi * 3.0 * t - .pi / 2)
        // Noise swell peaking around t = 0.45 s.
        let swell = exp(-pow((t - 0.45) / 0.28, 2))
        let breath = noiseLP.process(noise.next()) * swell * 0.35
        out[i] = (cluster * wobble + breath) * master.level(at: t, duration: dur)
    }
    return out
}

/// revive.caf — shimmering ascending sweep 220 -> 1760 Hz with sparkle.
func revive() -> [Double] {
    let dur = 0.6
    let n = sampleCount(dur)
    var out = [Double](repeating: 0, count: n)
    var phase = 0.0
    var shimmerPhase = 0.0
    let master = ADSR(attack: 0.06, decay: 0.1, sustain: 0.85, release: 0.18)
    for i in 0..<n {
        let t = Double(i) / sampleRate
        let sweepT = min(t / 0.5, 1.0)
        let vibrato = 1.0 + 0.012 * sin(2.0 * .pi * 6.0 * t)
        let f = 220.0 * pow(1760.0 / 220.0, sweepT) * vibrato
        phase += f / sampleRate
        shimmerPhase += f * 2.01 / sampleRate    // detuned octave shimmer
        let tone = sine(phase) + 0.3 * sine(shimmerPhase)
        out[i] = tone * master.level(at: t, duration: dur)
    }
    // Sparkle: deterministic scatter of tiny high sine pings, rising with the sweep.
    var noise = NoiseSource(seed: 0x5EED)
    for p in 0..<10 {
        let start = 0.08 + 0.4 * Double(p) / 10.0 + 0.02 * noise.next()
        let freq = 1800.0 + 2400.0 * Double(p) / 10.0 + 200.0 * noise.next()
        var pingPhase = 0.0
        let s = Int(start * sampleRate)
        for j in 0..<sampleCount(0.05) where s + j < n {
            let t = Double(j) / sampleRate
            pingPhase += freq / sampleRate
            out[s + j] += sine(pingPhase) * percEnv(t, attack: 0.001, tau: 0.018) * 0.22
        }
    }
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
func gate(url: URL, name: String) -> Bool {
    var peak = 0.0
    var sumSquares = 0.0
    var frames = 0
    var first = [Double]()
    var last = [Double]()
    do {
        let file = try AVAudioFile(forReading: url)
        let total = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: total) else { return false }
        try file.read(into: buffer)
        frames = Int(buffer.frameLength)
        guard frames > 128, let channel = buffer.floatChannelData?[0] else { return false }
        for i in 0..<frames {
            let s = Double(channel[i])
            peak = max(peak, abs(s))
            sumSquares += s * s
        }
        first = (0..<64).map { Double(channel[$0]) }
        last = (0..<64).map { Double(channel[frames - 64 + $0]) }
    } catch {
        print("GATE \(name) peak=0 rms=0 loopDelta=0 FAIL (unreadable: \(error.localizedDescription))")
        return false
    }
    let rms = (sumSquares / Double(frames)).squareRoot()
    var loopDelta = 0.0
    for i in 0..<64 { loopDelta += abs(first[i] - last[i]) }
    loopDelta /= 64.0
    // SFX gates: no clipping, sane RMS. loopDelta is informational for one-shots.
    let pass = peak < 0.98 && rms >= 0.02 && rms <= 0.5
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

let sounds: [(name: String, render: () -> [Double])] = [
    ("laser", laser),
    ("hit", hit),
    ("explosion", explosion),
    ("pickup", pickup),
    ("levelup", levelup),
    ("uitick", uitick),
    ("bossroar", bossroar),
    ("revive", revive),
]

var allPass = true
for sound in sounds {
    var samples = sound.render()
    normalize(&samples)
    fadeTail(&samples)
    let url = outputDir.appendingPathComponent("\(sound.name).caf")
    do {
        try writeCAF(samples, to: url)
    } catch {
        print("GATE \(sound.name).caf peak=0 rms=0 loopDelta=0 FAIL (write: \(error.localizedDescription))")
        allPass = false
        continue
    }
    if !gate(url: url, name: "\(sound.name).caf") { allPass = false }
}

exit(allPass ? 0 : 1)
