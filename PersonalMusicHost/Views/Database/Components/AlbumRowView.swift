//
//  AlbumRowView.swift
//  PersonalMusicHost
//
//  List row for an album in DatabaseManagementView.
//  Shows disc icon, title/artist/year, track count, and edit action.
//

import SwiftUI

struct AlbumRowView: View {
    let album: AlbumRecord
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: "opticaldisc")
                .foregroundColor(.secondary).font(.title2)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(album.title).font(.headline)
                Text("\(album.artist) • Released: \(album.releaseYear)")
                    .font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            Text("\(album.totalTracks) tracks")
                .font(.caption).foregroundColor(.secondary).padding(.trailing, 10)

            Divider().frame(height: 20).padding(.horizontal, 8)

            Button(action: onEdit) {
                Image(systemName: "pencil.circle.fill")
                    .foregroundColor(.purple).font(.title2)
            }
            .buttonStyle(.plain)
            .help("Edit Album")
        }
        .padding(.vertical, 4)
    }
}
