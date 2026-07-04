import AVFoundation
import UIKit
import NeonHordeCore

/// Runtime audio engine (GOAL §4 Audio & Haptics, AMENDMENT v3 / Phase 8C).
/// ONE AVAudioEngine drives everything: a small round-robin pool of
/// AVAudioPlayerNode SFX voices, two looping music players (main / boss)
/// crossfaded by game intensity, and a third looping player for the forest
/// ambience bed (tools/sfxgen ambience_forest.caf) at low gain.
/// All SFX .caf files (tools/sfxgen) are preloaded into AVAudioPCMBuffers at
/// start; each shot is a scheduleBuffer on the next voice — lowest latency,
/// per-sound volume, one code path with music. Never
/// SKAction.playSoundFileNamed (no volume control, memory quirks).
///
/// Owner overrides (AMENDMENT v3): every SFX / music / ambience resource
/// first looks for a bundled "ext_<name>.mp3" (AI-generated audio dropped
/// via ArtDrop and copied into the bundle at integration time) and prefers
/// it over the generated file; absent overrides fall back exactly as before.
///
/// Session is `.ambient` (never interrupts the user's own music); when
/// `secondaryAudioShouldBeSilencedHint` is set, game music AND the ambience
/// bed mute but one-shot SFX stay. Every failure path no-ops gracefully so
/// the game runs fine with no audio hardware or missing assets (simulator
/// safety).
final class AudioManager {
    static let shared = AudioManager()

    /// All code-generated SFX (tools/sfxgen). Raw value = .caf resource name.
    enum SFX: String, CaseIterable {
        case laser, hit, explosion, pickup, levelup, uitick, bossroar, revive
    }

    // MARK: - Tuning

    private static let voiceCount = 6
    /// Per-kind rate limit so spammy sounds (laser/pickup) cannot stack.
    private static let throttleInterval: CFTimeInterval = 0.05
    private static let crossfadeDuration: Double = 1.5
    private static let musicVolume: Float = 0.85
    /// The forest bed sits low under the music (its file is also rendered at
    /// a low ~0.07 RMS by the tools/sfxgen ambience gate).
    private static let ambienceVolume: Float = 0.5
    /// Canonical format for the shared SFX voice pool. Generated .caf SFX
    /// are already mono 44.1 kHz Float32; owner ext_*.mp3 overrides are
    /// converted on load so any buffer can play on any round-robin voice.
    private static let sfxFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                 sampleRate: 44100,
                                                 channels: 1,
                                                 interleaved: false)

    /// Per-sound gain: frequent sounds sit low, punctuation sounds sit high.
    private static let gains: [SFX: Float] = [
        .laser: 0.35, .pickup: 0.4, .uitick: 0.6, .hit: 0.7,
        .levelup: 0.8, .revive: 0.85, .explosion: 0.9, .bossroar: 1.0,
    ]

    // MARK: - State

    private let engine = AVAudioEngine()
    private var sfxVoices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private let musicMain = AVAudioPlayerNode()
    private let musicBoss = AVAudioPlayerNode()
    private let ambiencePlayer = AVAudioPlayerNode()

    private var sfxBuffers: [SFX: AVAudioPCMBuffer] = [:]
    private var mainBuffer: AVAudioPCMBuffer?
    private var bossBuffer: AVAudioPCMBuffer?
    private var ambienceBuffer: AVAudioPCMBuffer?

    private var started = false
    private var musicOn = true
    private var sfxOn = true
    private var bossMode = false
    /// 0 = main loop audible, 1 = boss loop audible.
    private var crossfade: Double = 0
    /// True while the user's own audio should silence game music (GOAL §4).
    private var otherAudioSilencesMusic = false
    private var lastPlayTime: [SFX: CFTimeInterval] = [:]
    private var fadeTimer: Timer?

    private init() {}

    // MARK: - Lifecycle

    /// Builds the engine once, preloads every buffer, starts the music loops.
    /// Safe to call repeatedly — later calls just re-apply the toggles.
    func start(musicOn: Bool, sfxOn: Bool) {
        guard !started else {
            setMusicOn(musicOn)
            setSFXOn(sfxOn)
            return
        }
        self.musicOn = musicOn
        self.sfxOn = sfxOn

        configureSession()
        loadBuffers()
        // Nothing to play (e.g. assets not generated yet) — stay dormant.
        guard !sfxBuffers.isEmpty || mainBuffer != nil || bossBuffer != nil
                || ambienceBuffer != nil else { return }

        buildGraph()
        observeNotifications()
        engine.prepare()
        do {
            try engine.start()
        } catch {
            return    // no audio hardware — every public call no-ops
        }
        started = true
        refreshSilenceHint()
        startMusic()
    }

    /// Applies the persisted settings toggles (GOAL §4: toggles live in the
    /// save file's MetaState).
    func apply(_ meta: MetaState) {
        setMusicOn(meta.musicOn)
        setSFXOn(meta.sfxOn)
    }

    // MARK: - SFX

    /// Schedules a one-shot on the next round-robin voice. Throttled per kind
    /// (50 ms) so rapid-fire events cannot stack into a blowout.
    func play(_ sfx: SFX) {
        guard started, sfxOn, engine.isRunning,
              let buffer = sfxBuffers[sfx] else { return }
        let now = CACurrentMediaTime()
        if let last = lastPlayTime[sfx], now - last < Self.throttleInterval { return }
        lastPlayTime[sfx] = now

        let voice = sfxVoices[nextVoice]
        nextVoice = (nextVoice + 1) % sfxVoices.count
        voice.stop()
        voice.volume = Self.gains[sfx] ?? 0.7
        voice.scheduleBuffer(buffer, at: nil, options: [])
        voice.play()
    }

    // MARK: - Music

    /// Crossfades between the main and boss loops over 1.5 s. Both loops run
    /// continuously (same key/BPM by construction — tools/musicgen), so the
    /// fade is a pure volume move.
    func setBossMode(_ on: Bool) {
        guard bossMode != on else { return }
        bossMode = on
        guard started else { return }
        fadeTimer?.invalidate()
        let stepInterval = 1.0 / 30.0
        let step = stepInterval / Self.crossfadeDuration
        fadeTimer = Timer.scheduledTimer(withTimeInterval: stepInterval,
                                         repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            self.crossfade += self.bossMode ? step : -step
            if self.crossfade <= 0 || self.crossfade >= 1 {
                self.crossfade = min(max(self.crossfade, 0), 1)
                timer.invalidate()
            }
            self.applyMusicVolumes()
        }
    }

    func setMusicOn(_ on: Bool) {
        musicOn = on
        applyMusicVolumes()
    }

    func setSFXOn(_ on: Bool) {
        sfxOn = on
        applyMusicVolumes()    // the diegetic ambience bed follows this toggle
    }

    // MARK: - Setup

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
        } catch {
            // .ambient rarely fails; if it does, the engine start will no-op.
        }
    }

    private func loadBuffers() {
        for sfx in SFX.allCases {
            sfxBuffers[sfx] = loadBuffer(resource: sfx.rawValue, ext: "caf",
                                         convertTo: Self.sfxFormat)
        }
        mainBuffer = loadBuffer(resource: "music_main", ext: "m4a")
        bossBuffer = loadBuffer(resource: "music_boss", ext: "m4a")
        ambienceBuffer = loadBuffer(resource: "ambience_forest", ext: "caf")
    }

    /// Resolves an audio resource with owner-override support (AMENDMENT v3):
    /// a bundled "ext_<name>.mp3" — AI-generated audio dropped via ArtDrop
    /// and copied into the bundle at integration time (e.g. ext_laser.mp3,
    /// ext_music_main.mp3, ext_ambience_forest.mp3) — is preferred over the
    /// generated file. Falls back to the generated resource, then to nil
    /// (every caller no-ops gracefully), exactly as before.
    private func loadBuffer(resource: String, ext: String,
                            convertTo canonical: AVAudioFormat? = nil) -> AVAudioPCMBuffer? {
        if let url = Bundle.main.url(forResource: "ext_" + resource, withExtension: "mp3"),
           let buffer = canonicalized(decodeFully(url), canonical) {
            return buffer
        }
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            return nil
        }
        return canonicalized(decodeFully(url), canonical)
    }

    /// Decodes an audio resource fully into memory (AAC music included — a
    /// preloaded buffer scheduled with .loops is the only gapless path).
    private func decodeFully(_ url: URL) -> AVAudioPCMBuffer? {
        do {
            let file = try AVAudioFile(forReading: url)
            guard file.length > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AVAudioFrameCount(file.length))
            else { return nil }
            try file.read(into: buffer)
            return buffer
        } catch {
            return nil
        }
    }

    /// Converts a buffer to the canonical SFX pool format when needed (mp3
    /// overrides may be stereo / a different sample rate; every buffer must
    /// match the format its shared voice was connected with).
    private func canonicalized(_ buffer: AVAudioPCMBuffer?,
                               _ canonical: AVAudioFormat?) -> AVAudioPCMBuffer? {
        guard let buffer = buffer else { return nil }
        guard let canonical = canonical, buffer.format != canonical else { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: canonical) else {
            return nil
        }
        let ratio = canonical.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: canonical,
                                         frameCapacity: capacity) else { return nil }
        var fed = false
        var convError: NSError?
        let status = converter.convert(to: out, error: &convError) { _, outStatus in
            if fed {
                outStatus.pointee = .endOfStream
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }
        return status == .error || out.frameLength == 0 ? nil : out
    }

    private func buildGraph() {
        let mixer = engine.mainMixerNode
        if !sfxBuffers.isEmpty,
           let format = Self.sfxFormat ?? sfxBuffers.values.first?.format {
            for _ in 0..<Self.voiceCount {
                let voice = AVAudioPlayerNode()
                engine.attach(voice)
                engine.connect(voice, to: mixer, format: format)
                sfxVoices.append(voice)
            }
        }
        if let buffer = mainBuffer {
            engine.attach(musicMain)
            engine.connect(musicMain, to: mixer, format: buffer.format)
        }
        if let buffer = bossBuffer {
            engine.attach(musicBoss)
            engine.connect(musicBoss, to: mixer, format: buffer.format)
        }
        if let buffer = ambienceBuffer {
            engine.attach(ambiencePlayer)
            engine.connect(ambiencePlayer, to: mixer, format: buffer.format)
        }
    }

    /// (Re)schedules both music loops and the ambience bed from the top and
    /// applies volumes. Loops are scheduled with .loops for gapless playback
    /// (GOAL §4).
    private func startMusic() {
        guard engine.isRunning else { return }
        if let buffer = mainBuffer {
            musicMain.stop()
            musicMain.scheduleBuffer(buffer, at: nil, options: .loops)
            musicMain.play()
        }
        if let buffer = bossBuffer {
            musicBoss.stop()
            musicBoss.scheduleBuffer(buffer, at: nil, options: .loops)
            musicBoss.play()
        }
        if let buffer = ambienceBuffer {
            ambiencePlayer.stop()
            ambiencePlayer.scheduleBuffer(buffer, at: nil, options: .loops)
            ambiencePlayer.play()
        }
        applyMusicVolumes()
    }

    /// Equal-power blend of the two music loops plus the ambience bed, gated
    /// by the toggles and the other-audio silence hint.
    ///
    /// Ambience policy: the forest bed is diegetic (the world itself, not
    /// score), so it follows the SFX toggle — a player who mutes music but
    /// keeps SFX still hears the forest. As a *continuous* bed, though, it
    /// defers to the user's own audio exactly like music does; only one-shot
    /// SFX play over a podcast.
    private func applyMusicVolumes() {
        let audible = musicOn && !otherAudioSilencesMusic
        let base = audible ? Self.musicVolume : 0
        musicMain.volume = base * Float(cos(crossfade * .pi / 2))
        musicBoss.volume = base * Float(sin(crossfade * .pi / 2))
        ambiencePlayer.volume = sfxOn && !otherAudioSilencesMusic ? Self.ambienceVolume : 0
    }

    // MARK: - Session notifications

    private func observeNotifications() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        center.addObserver(self, selector: #selector(handleInterruption(_:)),
                           name: AVAudioSession.interruptionNotification,
                           object: session)
        center.addObserver(self, selector: #selector(handleSilenceHint),
                           name: AVAudioSession.silenceSecondaryAudioHintNotification,
                           object: session)
        center.addObserver(self, selector: #selector(handleDidBecomeActive),
                           name: UIApplication.didBecomeActiveNotification,
                           object: nil)
    }

    /// Calls / Siri / alarms: stop on begin, rebuild playback on end.
    @objc private func handleInterruption(_ note: Notification) {
        guard let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            engine.stop()
        case .ended:
            restartEngine()
        @unknown default:
            break
        }
    }

    @objc private func handleSilenceHint() {
        refreshSilenceHint()
    }

    /// Foregrounding: the silence hint may have changed while backgrounded,
    /// and an interruption may have ended without an .ended notification.
    @objc private func handleDidBecomeActive() {
        refreshSilenceHint()
        if started && !engine.isRunning {
            restartEngine()
        }
    }

    private func refreshSilenceHint() {
        otherAudioSilencesMusic = AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
        applyMusicVolumes()
    }

    private func restartEngine() {
        guard started else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(true)
        } catch {
            // Session still owned by the interruptor — retry on next activate.
        }
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                return
            }
        }
        refreshSilenceHint()
        startMusic()
    }
}
