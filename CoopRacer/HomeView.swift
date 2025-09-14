import SwiftUI

struct HomeView: View {
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
                            // Your existing game view
                            ContentView()
                                .navigationBarBackButtonHidden(true)
                        } label: {
                            MenuButtonLabel(
                                title: "TWO PLAYER",
                                accent: LinearGradient(colors: [Theme.p1, Theme.p1.opacity(0.7)],
                                                       startPoint: .topLeading,
                                                       endPoint: .bottomTrailing)
                            )
                        }
                    }
                    .padding(.horizontal, 28)

                    Spacer()

                    // Big bottom "Event" button
                    Button {
                        showComingSoon = true
                    } label: {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.white.opacity(0.08))
                            .overlay(
                                Text("EVENT")
                                    .font(.title3.bold())
                                    .foregroundStyle(.white)
                            )
                            .frame(height: 72)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(.white.opacity(0.15), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
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
    var accent: LinearGradient = .init(colors: [Color.white.opacity(0.12), Color.white.opacity(0.06)],
                                       startPoint: .top, endPoint: .bottom)

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(accent)
            .frame(height: 56)
            .overlay(
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.6), radius: 8, y: 4)
    }
}
