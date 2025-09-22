import Foundation
import AVFoundation
import QuartzCore   // ✅ for CACurrentMediaTime

final class CountdownSounder {
    private var player: AVAudioPlayer?
    private var lastPlayTime: CFTimeInterval = 0

    /// Play a short tick (used for "3", "2", "1").
    func playTick(blipLength: TimeInterval = 0.15) {
        guard !isRateLimited() else { return }
        play(name: "race_countdown1", ext: "mp3", trim: blipLength)
    }

    /// Play only the tail of the countdown file (used for "GO").
    func playGoTail(tail: TimeInterval = 0.5) {
        guard !isRateLimited() else { return }
        play(name: "race_countdown1", ext: "mp3", tail: tail)
    }

    private func play(name: String, ext: String, trim: TimeInterval? = nil, tail: TimeInterval? = nil) {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            print("⚠️ Missing sound: \(name).\(ext)")
            return
        }

        do {
            let audio = try AVAudioPlayer(contentsOf: url)
            if let trim = trim {
                audio.currentTime = 0
                audio.play()
                audio.setVolume(1, fadeDuration: 0)
                audio.perform(#selector(audio.stop), with: nil, afterDelay: trim)
            } else if let tail = tail {
                let startTime = max(0, audio.duration - tail)
                audio.currentTime = startTime
                audio.play()
            } else {
                audio.play()
            }
            player = audio
            lastPlayTime = CACurrentMediaTime()
        } catch {
            print("⚠️ Audio error: \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
    }

    private func isRateLimited() -> Bool {
        let now = CACurrentMediaTime()
        if now - lastPlayTime < 0.1 { return true }
        return false
    }
}
