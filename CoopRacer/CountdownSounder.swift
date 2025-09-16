import AVFoundation

@MainActor
final class CountdownSounder {
    private var player: AVAudioPlayer?

    /// Short blip for 3/2/1.
    func playTick(blipLength: TimeInterval = 0.18) {
        guard let url =
            Bundle.main.url(forResource: "race_countdown_tick", withExtension: "mp3")
            ?? Bundle.main.url(forResource: "race_countdown1", withExtension: "mp3")
        else { return }

        // Stop any in-flight audio so ticks don’t overlap.
        stop()

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            p.numberOfLoops = 0
            p.play()
            player = p

            // Hard stop after the blip so it never lingers.
            DispatchQueue.main.asyncAfter(deadline: .now() + blipLength) { [weak self] in
                guard let self = self, self.player === p else { return }
                self.player?.stop()
                self.player = nil
            }
        } catch { /* ignore */ }
    }

    /// Play only the tail of the countdown file at GO (default 0.5s).
    func playGoTail(tail: TimeInterval = 0.5) {
        // Prefer a dedicated GO file if present; otherwise take the tail of countdown1.
        guard let url =
            Bundle.main.url(forResource: "race_go", withExtension: "mp3")
            ?? Bundle.main.url(forResource: "race_countdown1", withExtension: "mp3")
        else { return }

        // Ensure no tick is still playing.
        stop()

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            p.numberOfLoops = 0

            // Jump to the last `tail` seconds (clamped to start ≥ 0).
            let start = max(0, p.duration - tail)
            p.currentTime = start
            p.play()
            player = p

            // Stop right after the tail to avoid lingering ambience.
            let guardTime = min(tail + 0.05, p.duration)
            DispatchQueue.main.asyncAfter(deadline: .now() + guardTime) { [weak self] in
                guard let self = self, self.player === p else { return }
                self.player?.stop()
                self.player = nil
            }
        } catch { /* ignore */ }
    }

    func stop() {
        player?.stop()
        player = nil
    }
}
