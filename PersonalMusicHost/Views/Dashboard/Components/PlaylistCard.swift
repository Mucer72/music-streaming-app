//
//  PlaylistCard.swift
//  PersonalMusicHost
//
//  Card view for displaying a playlist (system or user-created)
//  in the horizontal playlist section of the library.
//

import SwiftUI

struct PlaylistCard: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading) {
            ZStack {
                color.opacity(0.8)
                Image(systemName: systemImage)
                    .font(.system(size: 40))
                    .foregroundColor(.white)
            }
            .frame(width: 140, height: 140)
            .cornerRadius(12)
            .shadow(radius: 4)

            Text(title)
                .font(.headline)
                .lineLimit(1)
                .padding(.top, 4)

            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(width: 140)
        .contentShape(Rectangle())
    }
}
