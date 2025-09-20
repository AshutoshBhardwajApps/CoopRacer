import AVFoundation

@MainActor
final class BGM {
    static let shared = BGM()
    private var player: AVAudioPlayer?
    private var targetVolume: Float = 0.22

    private init() {
        // Mix politely with other audio; respects Silent switch.
        // If you want to play even on Silent, change to .playback.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
    }

    /// Start (or resume) COOPbackground.mp3. Safe to call multiple times.
    func play(volume: Float = 0.22, fadeIn: TimeInterval = 0.4) {
        targetVolume = volume

        if let p = player {
            // Already loaded; just fade to target and ensure playing
            if !p.isPlaying { p.play() }
            fadeVolume(to: volume, duration: fadeIn)
            return
        }

        guard let url = Bundle.main.url(forResource: "COOPbackground", withExtension: "mp3") else {
            return
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 0.001
            p.prepareToPlay()
            p.play()
            player = p
            fadeVolume(to: volume, duration: fadeIn)
        } catch {
            // ignore playback errors
        }
    }

    /// Fade to a new volume without stopping.
    func setVolume(_ volume: Float, fadeDuration: TimeInterval = 0.25) {
        targetVolume = volume
        fadeVolume(to: volume, duration: fadeDuration)
    }

    /// Pause immediately (no fade).
    func pause() {
        player?.pause()
    }

    /// Resume immediately to last targetVolume.
    func resume(fadeIn: TimeInterval = 0.25) {
        guard let p = player else { return }
        if !p.isPlaying { p.play() }
        fadeVolume(to: targetVolume, duration: fadeIn)
    }

    /// Stop with a short fade, and release the player.
    func stop(fadeOut: TimeInterval = 0.35) {
        guard let p = player else { return }
        let steps = max(2, Int(fadeOut / 0.025))
        var i = 0
        let startVol = p.volume
        Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { [weak self] t in
            guard let self, let player = self.player else { t.invalidate(); return }
            i += 1
            let tNorm = min(1.0, Float(i) / Float(steps))
            player.volume = startVol + (0 - startVol) * tNorm
            if i >= steps {
                t.invalidate()
                player.stop()
                self.player = nil
            }
        }
    }

    // MARK: - Private fade helper (renamed to avoid shadowing)
    private func fadeVolume(to volume: Float, duration: TimeInterval) {
        guard let p = player else { return }
        if duration <= 0 {
            p.volume = volume
            return
        }
        let steps = max(2, Int(duration / 0.025))
        var i = 0
        let startVol = p.volume
        Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { [weak self] t in
            guard let self, let player = self.player else { t.invalidate(); return }
            i += 1
            let tNorm = min(1.0, Float(i) / Float(steps))
            player.volume = startVol + (volume - startVol) * tNorm
            if i >= steps { t.invalidate() }
        }
    }
}
