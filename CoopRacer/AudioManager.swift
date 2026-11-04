import AVFoundation
import SwiftUI

@MainActor
final class BGM {

    static let shared = BGM()

    private var player: AVAudioPlayer?
    private(set) var isPaused = false

    private var settings: SettingsStore { SettingsStore.shared }

    // MARK: - PLAY
    func play(volume: Float = 0.20) {

        // 🚫 User disabled music → stop and do nothing
        guard settings.musicEnabled else {
            stop()
            return
        }

        // Start fresh
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
                isPaused = false
            } catch {
                print("BGM: error \(error)")
            }
            return
        }

        // Already exists → update volume
        setVolume(volume, fadeDuration: 0.0)

        if isPaused {
            player?.play()
            isPaused = false
        }
    }

    // MARK: - VOLUME
    func setVolume(_ volume: Float, fadeDuration: TimeInterval) {

        // 🚫 No music if disabled
        guard settings.musicEnabled else {
            stop()
            return
        }

        guard let p = player else { return }

        if fadeDuration <= 0 {
            p.volume = volume
            return
        }

        // Smooth linear fade
        let steps = 24
        let stepDur = fadeDuration / Double(steps)
        let start = p.volume

        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDur * Double(i)) {
                let t = Float(Double(i) / Double(steps))
                p.volume = start + (volume - start) * t
            }
        }
    }

    // MARK: - STOP
    func stop() {
        player?.stop()
        player = nil
        isPaused = false
    }

    // MARK: - PAUSE
    func pause(fade: TimeInterval = 0.2) {
        guard settings.musicEnabled else { return }
        guard let p = player, p.isPlaying else { return }

        if fade > 0 { setVolume(0.0, fadeDuration: fade) }
        DispatchQueue.main.asyncAfter(deadline: .now() + fade) {
            p.pause()
            self.isPaused = true
        }
    }

    // MARK: - RESUME
    func resume(fade: TimeInterval = 0.2, to volume: Float = 0.20) {

        guard settings.musicEnabled else {
            stop()
            return
        }
        guard let p = player else { return }

        if !p.isPlaying {
            p.play()
            isPaused = false
        }

        p.volume = 0.0
        setVolume(volume, fadeDuration: fade)
    }
}
