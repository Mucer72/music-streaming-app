//
//  AlbumRow.swift
//  PersonalMusicHost
//
//  Row view for an album in list-based sections (search results, genre view).
//  Exposes tap and add-to-queue callbacks.
//

import SwiftUI

struct AlbumRow: View {
    let album: AlbumRecord
    let onTap: () -> Void
    let onAddToQueue: () -> Void

    var body: some View {
        HStack {
            SecureDriveImage(fileID: album.coverDriveID)
                .frame(width: 45, height: 45)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 4) {
                Text(album.title).font(.subheadline).bold().lineLimit(1)
                Text("\(album.artist) • \(album.totalTracks) tracks")
                    .font(.caption).foregroundColor(.secondary).lineLimit(1)
            }

            Spacer()

            Button(action: onAddToQueue) {
                Image(systemName: "plus.square.fill.on.square.fill")
                    .foregroundColor(.purple).font(.title3)
            }
            .buttonStyle(.plain)
            .help("Add entire album to queue")
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}
