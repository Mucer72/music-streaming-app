//
//  AlbumRowView.swift
//  PersonalMusicHost
//
//  List row for an album in DatabaseManagementView.
//  Shows thumbnail, title/artist/year, track count, and edit action.
//  Cross-platform compatible for macOS and iOS.
//

import SwiftUI

struct AlbumRowView: View {
    let album: AlbumRecord
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Album cover thumbnail
            if !album.coverDriveID.isEmpty {
                SecureDriveImage(fileID: album.coverDriveID)
                    .frame(width: 44, height: 44)
                    .cornerRadius(6)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "opticaldisc").font(.title3).foregroundColor(.secondary))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(album.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(album.artist) • \(album.releaseYear)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(album.totalTracks) bài")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.trailing, 4)

            #if os(macOS)
            Divider().frame(height: 20).padding(.horizontal, 4)

            Button(action: onEdit) {
                Image(systemName: "pencil.circle.fill")
                    .foregroundColor(.purple).font(.title2)
            }
            .buttonStyle(.plain)
            .help("Edit Album")
            #endif
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        #if os(iOS)
        .swipeActions(edge: .trailing) {
            Button(action: onEdit) {
                Label("Sửa", systemImage: "pencil")
            }
            .tint(.purple)
        }
        .contextMenu {
            Button(action: onEdit) {
                Label("Chỉnh sửa Album", systemImage: "pencil")
            }
        }
        #endif
    }
}
