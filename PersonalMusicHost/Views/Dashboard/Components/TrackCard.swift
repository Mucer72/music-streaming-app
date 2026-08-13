//
//  TrackCard.swift
//  PersonalMusicHost
//
//  Card view for displaying a track in horizontal scrolling sections
//  (Top 10 list). Supports optional rank badge overlay.
//

import SwiftUI

struct TrackCard: View {
    let track: TrackRecord
    let rank: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                SecureDriveImage(fileID: track.coverDriveID)
                    .frame(width: 140, height: 140)
                    .cornerRadius(12)
                    .shadow(radius: 4)

                if let rank = rank {
                    Text("#\(rank)")
                        .font(.caption).bold()
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                        .padding(6)
                }
            }

            Text(track.title)
                .font(.headline)
                .lineLimit(1)

            Text(track.artist)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(width: 140)
        .contentShape(Rectangle())
    }
}
