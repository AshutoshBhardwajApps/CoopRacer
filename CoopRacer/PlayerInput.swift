import Foundation

final class PlayerInput: ObservableObject {
    // Player 1 controls (bottom)
    @Published var p1Left: Bool = false
    @Published var p1Right: Bool = false

    // Player 2 controls (top)
    @Published var p2Left: Bool = false
    @Published var p2Right: Bool = false
}
