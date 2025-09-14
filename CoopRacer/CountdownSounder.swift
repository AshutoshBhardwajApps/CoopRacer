import Foundation
import AVFoundation

@MainActor
final class CountdownSounder: NSObject {
    private var player: AVAudioPlayer?

    /// Play once for a discrete tick value (3, 2, 1, 0). 0 corresponds to the "START" visual.
    func playTickNumber(_ tick: Int) {
        guard (0...3).contains(tick) else { return }

        // Stop any in-flight playback so ticks never overlap
        player?.stop()
        player = nil

        guard let url = Bundle.main.url(forResource: "race_countdown1", withExtension: "mp3") else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            p.numberOfLoops = 0
            p.play()
            player = p

            // Safety: trim long files to a short blip
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
                self?.player?.stop()
                self?.player = nil
            }
        } catch {
            // ignore
        }
    }

    func stop() {
        player?.stop()
        player = nil
    }
}
