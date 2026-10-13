import SwiftUI

struct CreditsView: View {
    var body: some View {
        List {
            Section("GAME") {
                Text("COOP Racer")
                    .font(.headline)
                Text("A two-player local racing game for iPhone.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Section("DEVELOPMENT") {
                LabeledContent("Developer", value: "Ashutosh Bhardwaj")
            }

            // TODO: credit COOPbackground.mp3 and the engine/crash sounds here
            // if their licences require attribution (CoopHockey's track is
            // CC BY 4.0 and is credited in its CreditsView).

            Section("FRAMEWORKS") {
                LabeledContent("Ads",      value: "Google Mobile Ads SDK")
                LabeledContent("Payments", value: "StoreKit")
                LabeledContent("Game",     value: "SpriteKit")
            }
        }
        .navigationTitle("Credits")
    }
}
