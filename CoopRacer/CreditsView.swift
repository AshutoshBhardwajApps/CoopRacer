//
//  CreditsView.swift
//  CoopRacer
//
//  Created by Ashutosh Bhardwaj on 2025-11-21.
//

import SwiftUI

struct CreditsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                Text("Credits")
                    .font(.largeTitle)
                    .bold()
                    .padding(.bottom, 10)

                Group {
                    Text("Car Artwork")
                        .font(.headline)

                    Text("""
Game car design by sujit1717  
Provided by Unlucky Studio  
Project: http://www.unluckystudio.com
""")
                }

                Divider().padding(.vertical, 10)

                Group {
                    Text("Background Music")
                        .font(.headline)

                    Text("""
"Game background music loop short" by ManuelGraf  
Source: https://freesound.org/s/410574/  
License: Creative Commons Attribution 4.0
""")
                }

                Divider().padding(.vertical, 10)

                Text("""
Co Op Racer © 2025  
All rights reserved by Ashutosh Bhardwaj
""")
                .font(.footnote)
                .foregroundColor(.secondary)

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Credits")
    }
}

struct CreditsView_Previews: PreviewProvider {
    static var previews: some View {
        CreditsView()
    }
}
