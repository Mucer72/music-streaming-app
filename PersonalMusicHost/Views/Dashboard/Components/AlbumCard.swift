//
//  AlbumCard.swift
//  PersonalMusicHost
//
//  Card view for displaying an album in horizontal scrolling sections.
//

import SwiftUI

struct AlbumCard: View {
    let album: AlbumRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureDriveImage(fileID: album.coverDriveID)
                .frame(width: 140, height: 140)
                .cornerRadius(12)
                .shadow(radius: 4)

            Text(album.title)
                .font(.headline)
                .lineLimit(1)

            Text("\(album.artist) • \(album.totalTracks) tracks")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(width: 140)
        .contentShape(Rectangle())
    }
}
