//
//  SettingsView.swift
//  CoopRacer
//
//  Created by Ashutosh Bhardwaj on 2025-09-21.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Player Names") {
                TextField("Player 1", text: $settings.player1Name)
                TextField("Player 2", text: $settings.player2Name)
            }

            Section("Player 1 Car") {
                CarGrid(selection: $settings.player1Car)
            }

            Section("Player 2 Car") {
                CarGrid(selection: $settings.player2Car)
            }
        }
        .navigationTitle("Settings")
    }
}

private struct CarGrid: View {
    @Binding var selection: String

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(SettingsStore.carOptions, id: \.self) { name in
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selection == name ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selection == name ? .blue : .white.opacity(0.15), lineWidth: selection == name ? 2 : 1)
                        )

                    VStack(spacing: 6) {
                        Image(name)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 56)
                        Text(name)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(8)
                }
                .onTapGesture { selection = name }
            }
        }
        .padding(.vertical, 6)
    }
}
