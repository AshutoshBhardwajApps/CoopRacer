import SwiftUI

struct HomeView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var purchaseManager: PurchaseManager

    @State private var animateCars = false
    @State private var showComingSoon = false
    @State private var showRemoveAdsSheet = false

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

                    // Settings + lifetime record + Remove Ads, as on CoopHockey's home screen
                    VStack(spacing: 10) {
                        NavigationLink(destination: SettingsView()) {
                            VStack(spacing: 6) {
                                Image(systemName: "gearshape.fill")
                                    .font(.title2)
                                Text("Settings")
                                    .font(.caption)
                            }
                            .foregroundColor(.white.opacity(0.75))
                        }

                        if settings.totalRoundsPlayed > 0 {
                            Text("Rounds: \(settings.totalRoundsPlayed)  •  P1 \(settings.p1WinsTotal)  –  P2 \(settings.p2WinsTotal)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        // Remove Ads pill — visible only until purchased.
                        if !settings.hasRemovedAds {
                            Button {
                                showRemoveAdsSheet = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "nosign")
                                    Text("Remove Ads")
                                    if let price = purchaseManager.localizedPrice {
                                        Text("· \(price)")
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                }
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.cyan)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().stroke(Color.cyan.opacity(0.55), lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(.top, 8)

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
            // Let ContentView clear any navigation flags when we’re safely back home
            NotificationCenter.default.post(name: Notification.Name("CoopRacer.ResetNavFlag"), object: nil)

            // Start/continue background track for menu
            BGM.shared.play(volume: 0.24)

            // Gentle header car wiggle
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                animateCars = true
            }
        }
        .fullScreenCover(isPresented: $showRemoveAdsSheet) {
            RemoveAdsPromoView(onDismiss: { showRemoveAdsSheet = false })
                .environmentObject(settings)
                .environmentObject(purchaseManager)
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
