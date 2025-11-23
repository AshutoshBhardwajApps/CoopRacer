import SwiftUI

struct HoldPad: View {
    @Binding var isPressed: Bool
    let title: String
    var flipText: Bool = false

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundColor(.white.opacity(0.7))
            .rotationEffect(.degrees(flipText ? 180 : 0))     // << flip label if needed
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(isPressed ? Color.white.opacity(0.25) : Color.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }
}
