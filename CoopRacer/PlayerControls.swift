//
//  PlayerControlse.swift
//  CoopRacer
//
//  Created by Ashutosh Bhardwaj on 2025-11-22.
//
//
//  PlayerControls.swift
//  CoopRacer
//
//  Copyright 2025
//
import SwiftUI

struct PlayerControls: View {
    var title: String
    var color: Color
    @Binding var left: Bool
    @Binding var right: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .bold()
                .foregroundColor(color)

            HStack(spacing: 12) {
                HoldPad(isPressed: $left,  title: "Left")
                HoldPad(isPressed: $right, title: "Right")
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .background(Color.black)
    }
}

struct PlayerControlsMirrored: View {
    var title: String
    var color: Color
    @Binding var left: Bool
    @Binding var right: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .bold()
                .foregroundColor(color)
                .rotationEffect(.degrees(180))

            HStack(spacing: 12) {
                HoldPad(isPressed: $right, title: "Right", flipText: true)
                HoldPad(isPressed: $left,  title: "Left",  flipText: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .background(Color.black)
    }
}
