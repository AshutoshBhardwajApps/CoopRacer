import SwiftUI

/// A large tappable/holdable pad that sets a binding TRUE while pressed, FALSE when released.
struct HoldPad: View {
    @Binding var isPressed: Bool
    var title: String
    var flipText: Bool = false

    var body: some View {
        ZStack {
            // GUARANTEED VISIBLE BACKGROUND
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.15))                   // dark grey, NOT black
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(isPressed ? 1.0 : 0.4), lineWidth: 2)
                )

            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)                    // ALWAYS visible
                .rotationEffect(.degrees(flipText ? 180 : 0))
        }
        .frame(height: 56)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed { isPressed = true }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}
