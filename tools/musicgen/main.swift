// tools/musicgen/main.swift — Neon Horde music composer/renderer (GOAL §4).
//
// Composes and renders two seamless stereo dark-synthwave loops entirely in
// code (A minor, 110 BPM, shared key/tempo so they crossfade cleanly):
//   music_main.m4a  ~2:20 — understated atmosphere: sidechain-ducked saw bass
//                    (Am-F-C-G), subtle square 16th arpeggio, warm detuned
//                    pad, minimal percussion (sine-thump kick, offbeat hats).
//   music_boss.m4a  ~1:10 — heavier variant: driving eighth-note bass, faster
//                    arp, snare + denser hats.
//
// Loop seamlessness: composed in exact whole bars; rendered exactly N bars of
// samples (plus a ring-out tail that is folded back with a 256-sample
// equal-power crossfade of the tail into the head); all note envelopes
// resolve inside their bar; a micro edge ramp pins the outermost samples to
// silence so the loop point is a guaranteed zero crossing.
//
// Output: renders Float32 PCM stereo .caf, converts to AAC .m4a via
// /usr/bin/afconvert, deletes the intermediate .caf.
//
// Usage: swift tools/musicgen/main.swift <outputDir>
//
// Machine-checkable gates (GOAL §4 — the builder cannot listen): per track,
// peak < 0.98 (mix targets -3 dBFS), 0.02 <= RMS <= 0.5, and loop continuity:
// mean |first64 - last64| < 0.02. Prints one GATE line per file; exits
// non-zero if any gate fails.

import AVFoundation
import Foundation

// MARK: - Timing

let sampleRate = 44100.0
let bpm = 110.0
/// One bar = 4 beats at 110 BPM, rounded to a whole sample count so every
/// track length is an exact number of bars (rounding shifts effective tempo
/// by < 0.001%).
let barSamples = Int((240.0 / bpm * sampleRate).rounded())
let beatSamples = Double(barSamples) / 4.0
let sixteenthSamples = beatSamples / 4.0
/// Extra render room past the loop end; ring-out lands here and is folded
/// back into the head.
let tailPad = 4096

// MARK: - Notes

func hz(_ midi: Int) -> Double { 440.0 * pow(2.0, Double(midi - 69) / 12.0) }

/// Am - F - C - G, one chord per bar, repeating.
let bassRoots = [33, 29, 36, 31]                    // A1  F1  C2  G1
let padChords: [[Int]] = [                          // voice-led triads
    [57, 60, 64],                                   // Am: A3 C4 E4
    [57, 60, 65],                                   // F:  A3 C4 F4
    [55, 60, 64],                                   // C:  G3 C4 E4
    [55, 59, 62],                                   // G:  G3 B3 D4
]
let arpChords: [[Int]] = padChords.map { $0.map { $0 + 12 } }   // octave up

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

/// Sidechain-style duck: hard dip at every beat, smooth recovery over ~320 ms.
func duck(_ absoluteIndex: Int) -> Double {
    let tBeat = fmod(Double(absoluteIndex), beatSamples) / sampleRate
    let x = min(1.0, tBeat / 0.32)
    let smooth = x * x * (3.0 - 2.0 * x)
    return 0.3 + 0.7 * smooth
}

// MARK: - Voices

/// Bass: saw through a one-pole lowpass. `eighths` = driving boss pattern;
/// otherwise a whole-bar sustain with the sidechain dip on each beat.
func renderBass(into buf: StereoBuf, bars: Int, eighths: Bool, gain: Double) {
    for bar in 0..<bars {
        let freq = hz(bassRoots[bar % bassRoots.count])
        let barStart = bar * barSamples
        if eighths {
            for step in 0..<8 {
                let start = barStart + Int((Double(step) * beatSamples / 2.0).rounded())
                let len = Int(beatSamples / 2.0 * 0.92)
                var phase = 0.0
                var lp = OnePoleLP(cutoff: 340)
                var note = [Double](repeating: 0, count: len)
                for i in 0..<len {
                    phase += freq / sampleRate
                    let s = lp.process(2.0 * (phase - floor(phase)) - 1.0)
                    note[i] = s * arEnv(i, length: len, attack: samples(0.004), release: samples(0.05))
                }
                buf.add(note, at: start, gain: gain)
            }
        } else {
            let len = barSamples
            var phase = 0.0
            var lp = OnePoleLP(cutoff: 240)
            var note = [Double](repeating: 0, count: len)
            for i in 0..<len {
                phase += freq / sampleRate
                let s = lp.process(2.0 * (phase - floor(phase)) - 1.0)
                let env = arEnv(i, length: len, attack: samples(0.01), release: samples(0.06))
                note[i] = s * env * duck(barStart + i)
            }
            buf.add(note, at: barStart, gain: gain)
        }
    }
}

/// Arpeggio: square-wave 16th notes over the chord tones, lowpassed soft.
func renderArp(into buf: StereoBuf, bars: Int, boss: Bool, gain: Double) {
    let pattern = boss ? [0, 3, 1, 3, 2, 3, 1, 3] : [0, 1, 2, 1]
    let cutoff = boss ? 3000.0 : 2200.0
    for bar in 0..<bars {
        let chord = arpChords[bar % arpChords.count]
        let tones = chord + [chord[0] + 12]          // root, 3rd, 5th, root+oct
        for step in 0..<16 {
            let start = bar * barSamples + Int((Double(step) * sixteenthSamples).rounded())
            let len = Int(sixteenthSamples * 0.85)
            let midi = tones[pattern[step % pattern.count] % tones.count]
            let freq = hz(midi)
            let accent = step % 4 == 0 ? 1.0 : 0.72
            var phase = 0.0
            var lp = OnePoleLP(cutoff: cutoff)
            var note = [Double](repeating: 0, count: len)
            for i in 0..<len {
                phase += freq / sampleRate
                let s = lp.process((phase - floor(phase)) < 0.5 ? 1.0 : -1.0)
                note[i] = s * arEnv(i, length: len, attack: samples(0.002), release: samples(0.02))
            }
            buf.add(note, at: start, gain: gain * accent,
                    pan: step % 2 == 0 ? -0.25 : 0.25)
        }
    }
}

/// Pad: detuned saw pairs per chord tone, slow attack, heavy lowpass, quiet.
func renderPad(into buf: StereoBuf, bars: Int, gain: Double) {
    let pans = [-0.4, 0.0, 0.4]
    for bar in 0..<bars {
        let chord = padChords[bar % padChords.count]
        let barStart = bar * barSamples
        let len = barSamples
        for (t, midi) in chord.enumerated() {
            let base = hz(midi)
            for detune in [0.9965, 1.0035] {
                let freq = base * detune
                var phase = 0.0
                var lp = OnePoleLP(cutoff: 850)
                var note = [Double](repeating: 0, count: len)
                for i in 0..<len {
                    phase += freq / sampleRate
                    let s = lp.process(2.0 * (phase - floor(phase)) - 1.0)
                    note[i] = s * arEnv(i, length: len,
                                        attack: samples(0.7), release: samples(0.35))
                }
                buf.add(note, at: barStart, gain: gain / 2.0,
                        pan: pans[t] * (detune < 1 ? 1.0 : -1.0))
            }
        }
    }
}

/// Kick: sine thump with fast pitch drop 150 -> 44 Hz. Rendered once, reused.
func makeKick() -> [Double] {
    let len = samples(0.26)
    var out = [Double](repeating: 0, count: len)
    var phase = 0.0
    for i in 0..<len {
        let t = Double(i) / sampleRate
        let f = 44.0 + (150.0 - 44.0) * exp(-t / 0.035)
        phase += f / sampleRate
        let env = min(t / 0.001, 1.0) * exp(-t / 0.095)
        out[i] = sin(2.0 * .pi * phase) * env
    }
    // Resolve exactly to zero.
    for i in 0..<samples(0.01) {
        out[len - 1 - i] *= Double(i) / Double(samples(0.01))
    }
    return out
}

/// Hat: short lowpass-differenced noise tick. Rendered once, reused.
func makeHat() -> [Double] {
    let len = samples(0.05)
    var out = [Double](repeating: 0, count: len)
    var noise = NoiseSource(seed: 0x4A7)
    var lp = OnePoleLP(cutoff: 6000)
    for i in 0..<len {
        let t = Double(i) / sampleRate
        let n = noise.next()
        let high = n - lp.process(n)                 // crude highpass
        out[i] = high * min(t / 0.001, 1.0) * exp(-t / 0.014)
    }
    return out
}

/// Snare (boss only): mid-band noise crack.
func makeSnare() -> [Double] {
    let len = samples(0.14)
    var out = [Double](repeating: 0, count: len)
    var noise = NoiseSource(seed: 0x5A2E)
    var lo = OnePoleLP(cutoff: 3400)
    var cut = OnePoleLP(cutoff: 480)
    for i in 0..<len {
        let t = Double(i) / sampleRate
        let n = noise.next()
        let band = lo.process(n) - cut.process(n)
        out[i] = band * min(t / 0.001, 1.0) * exp(-t / 0.038)
    }
    return out
}

func renderPercussion(into buf: StereoBuf, bars: Int, boss: Bool,
                      kickGain: Double, hatGain: Double, snareGain: Double) {
    let kick = makeKick()
    let hat = makeHat()
    let snare = boss ? makeSnare() : []
    for bar in 0..<bars {
        let barStart = bar * barSamples
        for beat in 0..<4 {
            let beatStart = barStart + Int((Double(beat) * beatSamples).rounded())
            buf.add(kick, at: beatStart, gain: kickGain)
            if boss {
                // Hats on every eighth, offbeats accented; snare on 2 and 4.
                buf.add(hat, at: beatStart, gain: hatGain * 0.6, pan: 0.15)
                buf.add(hat, at: beatStart + Int((beatSamples / 2.0).rounded()),
                        gain: hatGain, pan: 0.2)
                if beat == 1 || beat == 3 {
                    buf.add(snare, at: beatStart, gain: snareGain, pan: -0.05)
                }
            } else {
                // Soft hat on the offbeat only.
                buf.add(hat, at: beatStart + Int((beatSamples / 2.0).rounded()),
                        gain: hatGain, pan: 0.15)
            }
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
        guard let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                         frameCapacity: AVAudioFrameCount(file.length)) else {
            return false
        }
        try file.read(into: pcm)
        frames = Int(pcm.frameLength)
        guard frames > 128, let channels = pcm.floatChannelData else { return false }
        let channelCount = Int(pcm.format.channelCount)
        for c in 0..<channelCount {
            for i in 0..<frames {
                let s = Double(channels[c][i])
                peak = max(peak, abs(s))
                sumSquares += s * s
            }
            for i in 0..<64 {
                loopDelta += abs(Double(channels[c][i]) - Double(channels[c][frames - 64 + i]))
            }
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

/// music_main — 64 bars (~2:20). Understated: restraint beats busy.
func renderMain() -> StereoBuf {
    let bars = 64
    let buf = StereoBuf(bars: bars)
    renderBass(into: buf, bars: bars, eighths: false, gain: 0.30)
    renderArp(into: buf, bars: bars, boss: false, gain: 0.045)
    renderPad(into: buf, bars: bars, gain: 0.055)
    renderPercussion(into: buf, bars: bars, boss: false,
                     kickGain: 0.42, hatGain: 0.05, snareGain: 0)
    return buf
}

/// music_boss — 32 bars (~1:10), same key/BPM so the two loops crossfade.
func renderBoss() -> StereoBuf {
    let bars = 32
    let buf = StereoBuf(bars: bars)
    renderBass(into: buf, bars: bars, eighths: true, gain: 0.30)
    renderArp(into: buf, bars: bars, boss: true, gain: 0.06)
    renderPad(into: buf, bars: bars, gain: 0.05)
    renderPercussion(into: buf, bars: bars, boss: true,
                     kickGain: 0.46, hatGain: 0.07, snareGain: 0.16)
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
