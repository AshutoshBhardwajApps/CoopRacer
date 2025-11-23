//
//  CountdownOverlay.swift
//  CoopRacer
//
//  Created by Ashutosh Bhardwaj on 2025-11-22.
//
//
//  CountdownOverlay.swift
//  CoopRacer
//
//
import SwiftUI

struct CountdownOverlay: View {
    let startTick: Int
    let raceStarted: Bool
    @Binding var pulse: Bool

    var body: some View {
        Group {
            if !raceStarted {
                Group {
                    if startTick >= 1 {
                        Text("\(startTick)")
                            .font(.system(size: 120,
                                          weight: .black,
                                          design: .rounded))
                    } else {
                        Text("START")
                            .font(.system(size: 96,
                                          weight: .black,
                                          design: .rounded))
                    }
                }
                .foregroundStyle(.white.opacity(0.95))
                .padding(40)
                .background(.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .opacity(pulse ? 0.5 : 1.0)
                .scaleEffect(pulse ? 1.08 : 0.96)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                    ) {
                        pulse = true
                    }
                }
            }
        }
    }
}
