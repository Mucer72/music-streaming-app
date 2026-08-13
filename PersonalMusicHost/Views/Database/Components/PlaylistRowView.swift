//
//  PlaylistRowView.swift
//  PersonalMusicHost
//
//  List row for a playlist in DatabaseManagementView.
//  Shows playlist icon, title, public/private status, track count, and edit action.
//

import SwiftUI

struct PlaylistRowView: View {
    let playlist: PlaylistRecord
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: "music.note.list")
                .foregroundColor(.secondary).font(.title2)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.title).font(.headline)
                if playlist.isPublic {
                    Text("Public").font(.caption).foregroundColor(.secondary)
                } else {
                    Text("Private").font(.caption).foregroundColor(.secondary)
                }
            }

            Spacer()

            Text("\(playlist.trackIds.count) tracks")
                .font(.caption).foregroundColor(.secondary).padding(.trailing, 10)

            Divider().frame(height: 20).padding(.horizontal, 8)

            Button(action: onEdit) {
                Image(systemName: "pencil.circle.fill")
                    .foregroundColor(.green).font(.title2)
            }
            .buttonStyle(.plain)
            .help("Edit Playlist")
        }
        .padding(.vertical, 4)
    }
}
