import AVFoundation

/// All sound in the game: short effects and looping background music.
/// Nothing is loaded from files; every sound is synthesized when the app starts.
final class SoundFX {
    static let shared = SoundFX()

    enum Effect: String, CaseIterable {
        case tap, run, move, bump, till, plant, water, harvest
        case pick, drop, ship, scan
        case star1, star2, star3, win, fail, error, unlock
    }

    enum Track: String, CaseIterable {
        case farm, warehouse
    }

    private static let sampleRate = 22_050.0
    private var players: [Effect: [AVAudioPlayer]] = [:]
    private var nextPlayer: [Effect: Int] = [:]
    private var lastPlayed: [Effect: CFTimeInterval] = [:]
    private var music: [Track: AVAudioPlayer] = [:]
    private var currentTrack: Track?
    private var wantedTrack: Track?
    private var ready = false
    private let work = DispatchQueue(label: "cc.sound", qos: .utility)

    /// Unit tests run inside the app; keep them silent and fast.
    private let disabled = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    private init() {}

    // MARK: Public

    /// Synthesizes every sound in the background. Call once at launch.
    func prepare() {
        guard !disabled, !ready else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        work.async { [weak self] in
            var built: [Effect: [AVAudioPlayer]] = [:]
            for e in Effect.allCases {
                let data = SoundFX.wav(SoundFX.synth(e))
                var pool: [AVAudioPlayer] = []
                for _ in 0..<(e == .move ? 3 : 2) {
                    if let p = try? AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue) {
                        p.prepareToPlay()
                        pool.append(p)
                    }
                }
                built[e] = pool
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.players = built
                self.ready = true
            }
            // Music takes longer to render, so effects are usable first.
            var tracks: [Track: AVAudioPlayer] = [:]
            for t in Track.allCases {
                let data = SoundFX.wav(SoundFX.musicLoop(t))
                if let p = try? AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue) {
                    p.numberOfLoops = -1
                    p.volume = 0
                    p.prepareToPlay()
                    tracks[t] = p
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.music = tracks
                let wanted = self.wantedTrack
                self.currentTrack = nil
                self.setTrack(wanted)
            }
        }
    }

    func play(_ effect: Effect) {
        guard ready, !disabled else { return }
        let s = AppSettings.shared
        guard s.soundOn, s.soundVolume > 0.01 else { return }
        // At high speeds the same effect would fire many times a second; skip the pile-up.
        let now = CACurrentMediaTime()
        if let last = lastPlayed[effect], now - last < 0.045 { return }
        lastPlayed[effect] = now
        guard let pool = players[effect], !pool.isEmpty else { return }
        let i = (nextPlayer[effect] ?? 0) % pool.count
        nextPlayer[effect] = i + 1
        let p = pool[i]
        p.volume = Float(s.soundVolume)
        p.currentTime = 0
        p.play()
    }

    /// Switches the background music (nil = silence), fading between tracks.
    func setTrack(_ track: Track?) {
        wantedTrack = track
        guard !disabled else { return }
        let s = AppSettings.shared
        let target: Track? = (s.musicOn && s.musicVolume > 0.01) ? track : nil
        if target == currentTrack {
            if let t = target { music[t]?.setVolume(musicLevel, fadeDuration: 0.3) }
            return
        }
        if let old = currentTrack, let p = music[old] {
            p.setVolume(0, fadeDuration: 0.6)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                if self?.currentTrack != old { p.pause() }
            }
        }
        currentTrack = target
        if let t = target, let p = music[t] {
            if !p.isPlaying { p.play() }
            p.setVolume(musicLevel, fadeDuration: 1.0)
        }
    }

    /// Call when sound settings change.
    func settingsChanged() {
        guard !disabled else { return }
        setTrack(wantedTrack)
    }

    private var musicLevel: Float { Float(AppSettings.shared.musicVolume) * 0.55 }

    // MARK: WAV

    private static func wav(_ samples: [Float]) -> Data {
        let sr = UInt32(sampleRate)
        var pcm = [Int16](repeating: 0, count: samples.count)
        for i in samples.indices { pcm[i] = Int16(max(-1, min(1, samples[i])) * 32_000) }
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(pcm.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(sr); u32(sr * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        pcm.withUnsafeBytes { d.append(contentsOf: $0) }
        return d
    }

    // MARK: Effect synthesis

    /// Renders `duration` seconds by calling `f(time, sampleIndex)`.
    private static func render(_ duration: Double, _ f: (Double, Int) -> Double) -> [Float] {
        let n = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            // A few milliseconds of fade at each end avoids clicks.
            let edge = min(1.0, Double(i) / 60, Double(n - 1 - i) / 120)
            out[i] = Float(f(t, i) * edge)
        }
        return out
    }

    /// A tone whose pitch slides from f0 to f1 over `duration`.
    private static func sweep(_ f0: Double, _ f1: Double, _ duration: Double, shape: @escaping (Double) -> Double = { sin($0) }) -> (Double) -> Double {
        return { t in
            let u = min(1, t / duration)
            // Phase is the integral of the frequency.
            let cycles = f0 * t + (f1 - f0) * u * t / 2
            return shape(2 * Double.pi * cycles)
        }
    }

    private static func triangle(_ phase: Double) -> Double {
        let turns = phase / (2 * Double.pi)
        let x = turns - floor(turns)
        return 4 * abs(x - 0.5) - 1
    }

    private static func softSquare(_ phase: Double) -> Double { tanh(3 * sin(phase)) }

    /// White noise run through a simple low-pass filter.
    private static func noise(_ count: Int, smooth: Double, seed: UInt64) -> [Double] {
        var rng = SeededRNG(seed: seed)
        var out = [Double](repeating: 0, count: count)
        var y = 0.0
        for i in 0..<count {
            let x = Double.random(in: -1...1, using: &rng)
            y += (x - y) * smooth
            out[i] = y
        }
        return out
    }

    private static let tau = 2 * Double.pi

    private static func bell(_ f: Double, _ t: Double, decay: Double) -> Double {
        guard t >= 0 else { return 0 }
        let w = tau * f * t
        let a = sin(w)
        let b = 0.45 * sin(w * 2)
        let c = 0.2 * sin(w * 3.01)
        return (a + b + c) * exp(-t * decay) * 0.5
    }

    /// Half a sine wave from 0 up to 1 and back to 0 across `duration`.
    private static func hump(_ t: Double, _ duration: Double) -> Double {
        guard t >= 0, t <= duration else { return 0 }
        return sin(Double.pi * t / duration)
    }

    private static func synth(_ e: Effect) -> [Float] {
        switch e {
        case .tap:
            return render(0.05) { t, _ in
                let tone = sin(tau * 1250 * t)
                return tone * exp(-t * 70) * 0.35
            }
        case .run:
            return render(0.2) { t, _ in
                let a = bell(660, t, decay: 18)
                let b = bell(990, t - 0.08, decay: 14)
                return (a + b) * 0.6
            }
        case .unlock:
            return render(0.4) { t, _ in
                let a = bell(784, t, decay: 12)
                let b = bell(988, t - 0.09, decay: 12)
                let c = bell(1175, t - 0.18, decay: 9)
                return (a + b + c) * 0.55
            }
        case .move:
            let n = noise(Int(0.13 * sampleRate), smooth: 0.12, seed: 3)
            let tone = sweep(170, 250, 0.13)
            return render(0.13) { t, i in
                let env = hump(t, 0.13)
                let mix = n[i] * 0.9 + tone(t) * 0.12
                return mix * env * 0.38
            }
        case .bump:
            let n = noise(Int(0.18 * sampleRate), smooth: 0.5, seed: 5)
            let tone = sweep(160, 45, 0.18)
            return render(0.18) { t, i in
                let low = tone(t) * exp(-t * 16) * 0.75
                let click = n[i] * exp(-t * 90) * 0.5
                return low + click
            }
        case .till:
            let n = noise(Int(0.2 * sampleRate), smooth: 0.25, seed: 7)
            return render(0.2) { t, i in
                let wobble = 0.6 + 0.4 * sin(tau * 28 * t)
                return n[i] * wobble * hump(t, 0.2) * 0.8
            }
        case .plant:
            let tone = sweep(720, 330, 0.09)
            return render(0.1) { t, _ in tone(t) * exp(-t * 28) * 0.5 }
        case .water:
            let lo = noise(Int(0.28 * sampleRate), smooth: 0.08, seed: 11)
            let hi = noise(Int(0.28 * sampleRate), smooth: 0.8, seed: 13)
            return render(0.28) { t, i in
                let hiss = hi[i] - lo[i]
                let wobble = 0.7 + 0.3 * sin(tau * 19 * t)
                return hiss * wobble * hump(t, 0.28) * 0.32
            }
        case .harvest:
            return render(0.45) { t, _ in
                let a = bell(1318.5, t, decay: 9)
                let b = bell(1975.5, t - 0.05, decay: 9)
                return (a + b) * 0.6
            }
        case .pick:
            let tone = sweep(280, 540, 0.13, shape: triangle)
            return render(0.14) { t, _ in tone(t) * hump(t, 0.14) * 0.4 }
        case .drop:
            let tone = sweep(440, 220, 0.12, shape: triangle)
            let thud = sweep(120, 55, 0.1)
            return render(0.22) { t, _ in
                let a = tone(t) * hump(t, 0.12) * 0.35
                var b = 0.0
                if t > 0.1 { b = thud(t - 0.1) * exp(-(t - 0.1) * 25) * 0.6 }
                return a + b
            }
        case .ship:
            return render(0.5) { t, _ in
                let a = bell(880, t, decay: 10)
                let b = bell(1318.5, t - 0.11, decay: 8)
                return (a + b) * 0.65
            }
        case .scan:
            return render(0.16) { t, _ in
                var v = 0.0
                if t < 0.05 { v = softSquare(tau * 1760 * t) }
                if t > 0.08 && t < 0.14 { v = softSquare(tau * 2093 * t) }
                return v * 0.16
            }
        case .star1:
            return render(0.4) { t, _ in bell(880, t, decay: 9) * 0.7 }
        case .star2:
            return render(0.4) { t, _ in bell(1108.7, t, decay: 9) * 0.7 }
        case .star3:
            return render(0.5) { t, _ in
                let a = bell(1318.5, t, decay: 7)
                let b = bell(1760, t - 0.04, decay: 7) * 0.5
                return (a + b) * 0.7
            }
        case .win:
            let notes: [Double] = [523.25, 659.25, 783.99, 1046.5]
            return render(1.0) { t, _ in
                var v = 0.0
                for (k, f) in notes.enumerated() { v += bell(f, t - Double(k) * 0.09, decay: 5) }
                v += bell(1318.5, t - 0.42, decay: 4) * 0.6
                return v * 0.42
            }
        case .fail:
            let tone = sweep(330, 150, 0.36, shape: triangle)
            return render(0.38) { t, _ in tone(t) * hump(t, 0.38) * 0.42 }
        case .error:
            return render(0.22) { t, _ in
                let on = t < 0.08 || (t > 0.12 && t < 0.2)
                return on ? triangle(tau * 155 * t) * 0.45 : 0
            }
        }
    }

    // MARK: Music synthesis

    private struct Song {
        /// One chord per bar, as note frequencies (low to high).
        let chords: [[Double]]
        let bar: Double
        /// Which chord note each arpeggio step plays; -1 is a rest.
        let pattern: [Int]
        let arpOctave: Double
        let beat: Bool
    }

    private static func song(_ t: Track) -> Song {
        switch t {
        case .farm:
            // C major, bright and easy: Cmaj7, Am7, Fmaj7, G6.
            return Song(chords: [[130.81, 261.63, 329.63, 392.0, 493.88], [110.0, 220.0, 261.63, 329.63, 392.0],
                                 [87.31, 174.61, 220.0, 261.63, 329.63], [98.0, 196.0, 246.94, 293.66, 329.63]],
                        bar: 4, pattern: [1, 3, 2, 4, 3, 2, 4, -1], arpOctave: 2, beat: false)
        case .warehouse:
            // D minor with a steady pulse: Dm7, Bbmaj7, Gm7, A7sus4.
            return Song(chords: [[73.42, 146.83, 174.61, 220.0, 261.63], [58.27, 116.54, 146.83, 174.61, 220.0],
                                 [49.0, 98.0, 116.54, 146.83, 174.61], [55.0, 110.0, 146.83, 164.81, 196.0]],
                        bar: 4, pattern: [1, -1, 3, 2, -1, 4, 2, 3], arpOctave: 4, beat: true)
        }
    }

    /// A seamless loop: soft pad chords, a bass note, and a plucked pattern with echo.
    private static func musicLoop(_ track: Track) -> [Float] {
        let s = song(track)
        let barN = Int(s.bar * sampleRate)
        let n = barN * s.chords.count
        var buf = [Double](repeating: 0, count: n)
        let twoPi = 2 * Double.pi

        for (b, chord) in s.chords.enumerated() {
            let start = b * barN
            // Pad: every chord note as two slightly detuned sines that swell and fade over the bar.
            for (k, f) in chord.enumerated() {
                let amp = k == 0 ? 0.11 : 0.045
                let w1 = twoPi * f * 0.998 / sampleRate
                let w2 = twoPi * f * 1.003 / sampleRate
                for i in 0..<barN {
                    let u = Double(i) / Double(barN)
                    let env = pow(sin(Double.pi * u), 0.7)
                    let x = Double(i)
                    buf[start + i] += (sin(w1 * x) + sin(w2 * x)) * amp * env
                }
            }
            // Plucked pattern.
            let stepN = barN / s.pattern.count
            for (step, idx) in s.pattern.enumerated() where idx >= 0 && idx < chord.count {
                let f = chord[idx] * s.arpOctave
                let w = twoPi * f / sampleRate
                let len = Int(1.2 * sampleRate)
                let at = start + step * stepN
                for i in 0..<len {
                    let t = Double(i) / sampleRate
                    let x = Double(i)
                    let voice = sin(w * x) + 0.3 * sin(2 * w * x)
                    let env = exp(-t * 4.5) * min(1, x / 80)
                    buf[(at + i) % n] += voice * env * 0.075
                }
            }
            if s.beat {
                // A soft thump on beats 1 and 3, and a quiet tick on every half beat.
                var rng = SeededRNG(seed: UInt64(b + 1))
                for beat in 0..<8 {
                    let at = start + beat * (barN / 8)
                    if beat % 4 == 0 {
                        for i in 0..<Int(0.22 * sampleRate) {
                            let t = Double(i) / sampleRate
                            let phase = twoPi * (70 - 90 * t) * t
                            buf[(at + i) % n] += sin(phase) * exp(-t * 16) * 0.16
                        }
                    }
                    for i in 0..<Int(0.03 * sampleRate) {
                        let t = Double(i) / sampleRate
                        let r = Double.random(in: -1...1, using: &rng)
                        buf[(at + i) % n] += r * exp(-t * 140) * 0.018
                    }
                }
            }
        }

        // Echo that wraps around the loop, so the end flows back into the start.
        let delay = Int(0.375 * sampleRate)
        var out = buf
        for tap in 1...3 {
            let gain = pow(0.38, Double(tap))
            let shift = delay * tap
            for i in 0..<n { out[(i + shift) % n] += buf[i] * gain * 0.6 }
        }

        let peak = out.reduce(0) { max($0, abs($1)) }
        let scale = peak > 0 ? 0.6 / peak : 1
        return out.map { Float($0 * scale) }
    }
}
