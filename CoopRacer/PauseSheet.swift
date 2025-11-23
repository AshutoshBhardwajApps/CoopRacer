//
//  PauseSheet.swift
//  CoopRacer
//
//  Created by Ashutosh Bhardwaj on 2025-11-22.
//
import SwiftUI

struct PauseSheet: View {
    var resume: () -> Void
    var restart: () -> Void
    var goHome: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Resume", action: resume)
                    Button("Restart Round", action: restart)
                    Button("Leave and go to Home",
                           role: .destructive,
                           action: goHome)
                }
            }
            .navigationTitle("Paused")
        }
        .presentationDetents([.medium])
    }
}
