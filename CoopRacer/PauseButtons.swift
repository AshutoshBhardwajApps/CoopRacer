//
//  PauseButtons.swift
//  CoopRacer
//
//  Created by Ashutosh Bhardwaj on 2025-11-22.
//
import SwiftUI

struct PauseButtons: View {
    let tap: () -> Void

    var body: some View {
        VStack {
            Button(action: tap) {
                PauseChip(label: "Pause")
                    .rotationEffect(.degrees(180))
            }
            .padding(.top, 6)

            Spacer()

            Button(action: tap) {
                PauseChip(label: "Pause")
            }
            .padding(.bottom, 6)
        }
    }
}

private struct PauseChip: View {
    var label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "pause.fill")
                .font(.subheadline.bold())
            Text(label)
                .font(.subheadline.bold())
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(.ultraThinMaterial)
        .foregroundStyle(.white)
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        .contentShape(Rectangle())
    }
}
