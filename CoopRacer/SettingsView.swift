import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("PLAYER NAMES") {
                TextField("Player 1", text: $settings.player1Name)
                TextField("Player 2", text: $settings.player2Name)
            }

            Section("PLAYER 1 CAR") {
                CarGrid(selection: $settings.player1Car)
            }

            Section("PLAYER 2 CAR") {
                CarGrid(selection: $settings.player2Car)
            }
        }
        .navigationTitle("Settings")
    }
}

private struct CarGrid: View {
    @Binding var selection: String
    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(SettingsStore.carOptions, id: \.self) { name in
                CarThumb(name: name, selected: selection == name)
                    .onTapGesture { selection = name }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct CarThumb: View {
    let name: String
    let selected: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(selected ? Color.blue : Color.white.opacity(0.15),
                                lineWidth: selected ? 2 : 1)
                )

            VStack(spacing: 8) {
                carImage
                    .resizable()
                    .renderingMode(.original)          // <- no template tinting
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: 64)

                Text(name)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(10)

            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .padding(8)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // Loads from asset catalog OR bundle PNGs.
    private var carImage: Image {
        #if canImport(UIKit)
        if let ui = UIImage(named: name) {
            return Image(uiImage: ui)
        }
        #endif
        // Fallback: a letter tile if image missing
        return Image(systemName: "car.fill")
    }
}
