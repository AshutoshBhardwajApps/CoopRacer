import Foundation
import AVFoundation

@MainActor
final class CountdownSounder: NSObject {
    private var player: AVAudioPlayer?
    private var lastTick: Int = 4  // start above 3 so we beep at 3 first

    func maybePlay(for secondsRemaining: Double) {
        let current = Int(ceil(max(0, secondsRemaining)))   // 3,2,1,0
        guard current != lastTick else { return }
        lastTick = current

        // Stop any in-flight tick so we don't overlap
        player?.stop()
        player = nil

        guard let url = Bundle.main.url(forResource: "race_countdown1", withExtension: "mp3") else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            p.numberOfLoops = 0
            p.play()
            player = p

            // Safety: force short blip even if the file is long
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

    func reset() { lastTick = 4 }
}
