import AVFoundation

@MainActor
final class BGM {
    static let shared = BGM()

    private var player: AVAudioPlayer?
    private(set) var isPaused = false

    /// Start/continue the background track. If the player already exists, just set volume.
    func play(volume: Float = 0.20) {
        if player == nil {
            guard let url = Bundle.main.url(forResource: "COOPbackground", withExtension: "mp3") else {
                print("BGM: missing COOPbackground.mp3")
                return
            }
            do {
                let p = try AVAudioPlayer(contentsOf: url)
                p.numberOfLoops = -1
                p.volume = volume
                p.prepareToPlay()
                p.play()
                player = p
            } catch {
                print("BGM: error \(error)")
            }
        } else {
            setVolume(volume, fadeDuration: 0.0)
            if isPaused {
                player?.play()
                isPaused = false
            }
        }
    }

    /// Smooth volume change.
    func setVolume(_ volume: Float, fadeDuration: TimeInterval) {
        guard let p = player else { return }
        if fadeDuration <= 0 {
            p.volume = volume
            return
        }
        // Simple linear fade on main thread
        let steps = 20
        let stepDur = fadeDuration / Double(steps)
        let start = p.volume
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDur * Double(i)) {
                let t = Float(Double(i) / Double(steps))
                p.volume = start + (volume - start) * t
            }
        }
    }

    /// Hard stop (releases player).
    func stop() {
        player?.stop()
        player = nil
        isPaused = false
    }

    /// Pause and keep position.
    func pause(fade: TimeInterval = 0.2) {
        guard let p = player, p.isPlaying else { return }
        if fade > 0 { setVolume(0.0, fadeDuration: fade) }
        DispatchQueue.main.asyncAfter(deadline: .now() + fade) {
            p.pause()
            self.isPaused = true
        }
    }

    /// Resume from pause.
    func resume(fade: TimeInterval = 0.2, to volume: Float = 0.20) {
        guard let p = player else { return }
        if !p.isPlaying {
            p.play()
            isPaused = false
        }
        p.volume = 0.0
        setVolume(volume, fadeDuration: fade)
    }
}
