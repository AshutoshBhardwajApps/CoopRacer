import SwiftUI

/// A large tappable/holdable pad that sets a binding TRUE while pressed, FALSE when released.
struct HoldPad: View {
    @Binding var isPressed: Bool
    var title: String
    var flipText: Bool = false  // rotate just the label for the top player

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.primary.opacity(0.15), lineWidth: 1)
                .background(RoundedRectangle(cornerRadius: 14).fill(.primary.opacity(0.05)))
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .rotationEffect(.degrees(flipText ? 180 : 0))
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { _ in isPressed = false }
        )
        .frame(height: 56)
    }
}
