//
//  PlaylistRowView.swift
//  PersonalMusicHost
//
//  List row for a playlist in DatabaseManagementView.
//  Shows thumbnail, title, public/private status, track count, and edit action.
//  Cross-platform compatible for macOS and iOS.
//

import SwiftUI

struct PlaylistRowView: View {
    let playlist: PlaylistRecord
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Playlist cover thumbnail
            if let coverID = playlist.coverDriveID, !coverID.isEmpty {
                SecureDriveImage(fileID: coverID)
                    .frame(width: 44, height: 44)
                    .cornerRadius(6)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "music.note.list").font(.title3).foregroundColor(.secondary))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(playlist.isPublic ? "Công khai" : "Riêng tư")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("\(playlist.trackIds.count) bài")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.trailing, 4)

            #if os(macOS)
            Divider().frame(height: 20).padding(.horizontal, 4)

            Button(action: onEdit) {
                Image(systemName: "pencil.circle.fill")
                    .foregroundColor(.green).font(.title2)
            }
            .buttonStyle(.plain)
            .help("Edit Playlist")
            #endif
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        #if os(iOS)
        .swipeActions(edge: .trailing) {
            Button(action: onEdit) {
                Label("Sửa", systemImage: "pencil")
            }
            .tint(.green)
        }
        .contextMenu {
            Button(action: onEdit) {
                Label("Chỉnh sửa Playlist", systemImage: "pencil")
            }
        }
        #endif
    }
}
