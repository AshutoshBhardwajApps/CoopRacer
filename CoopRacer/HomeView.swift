import SwiftUI

struct HomeView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var animateCars = false
    @State private var showComingSoon = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 28) {
                    // Top row little cars
                    HStack {
                        Image(systemName: "car.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.p1)
                            .opacity(animateCars ? 1 : 0.35)
                            .offset(x: animateCars ? -4 : 0)
                        Spacer()
                        Image(systemName: "car.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.p2)
                            .opacity(animateCars ? 1 : 0.35)
                            .offset(x: animateCars ? 4 : 0)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                    // Title
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Text("CO")
                                .foregroundStyle(.white)
                            Text("OP")
                                .foregroundStyle(.white)
                        }
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .tracking(2)

                        Text("RACER")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .tracking(6)
                            .padding(.top, 2)
                    }
                    .padding(.top, 6)

                    Spacer(minLength: 8)

                    // Buttons stack
                    VStack(spacing: 14) {
                        Button {
                            showComingSoon = true
                        } label: {
                            MenuButtonLabel(title: "SINGLE PLAYER")
                        }

                        NavigationLink {
                            ContentView()
                                .navigationBarBackButtonHidden(true)
                        } label: {
                            MenuButtonLabel(
                                title: "TWO PLAYER",
                                accent: LinearGradient(
                                    colors: [Theme.p1, Theme.p1.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        }
                    }
                    .padding(.horizontal, 28)

                    Spacer()

                    NavigationLink {
                        SettingsView()
                    } label: {
                        MenuButtonLabel(title: "SETTINGS")
                    }
                    .padding(.horizontal, 28)

                    NavigationLink {
                        HighScoresView()
                    } label: {
                        MenuButtonLabel(title: "HIGH SCORES")
                    }
                    .padding(.horizontal, 28)

                    // ✅ EVENT button removed
                    // (Nothing else needed here – layout still looks clean.)
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            // Let ContentView clear any navigation flags when we’re safely back home
            NotificationCenter.default.post(name: Notification.Name("CoopRacer.ResetNavFlag"), object: nil)

            // Start/continue background track for menu, but only if enabled
                if settings.musicEnabled {
                    BGM.shared.play(volume: 0.24)
                } else {
                    BGM.shared.play(volume: 0.0)    // keep it running but silent
                }

            // Gentle header car wiggle
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                animateCars = true
            }
        }
        .alert("Coming soon", isPresented: $showComingSoon) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This mode isn’t available yet. Try Two Player!")
        }
    }
}

// Simple reusable menu button label
private struct MenuButtonLabel: View {
    var title: String
    var accent: LinearGradient = .init(
        colors: [Color.white.opacity(0.12), Color.white.opacity(0.06)],
        startPoint: .top, endPoint: .bottom
    )

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(accent)
            .frame(height: 56)
            .overlay(
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.6), radius: 8, y: 4)
    }
}
