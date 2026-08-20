//
//  TrackRowView.swift
//  PersonalMusicHost
//
//  List row for a track in DatabaseManagementView.
//  Shows track number, thumbnail, title/artist, file-format badges, and edit/delete actions.
//  Cross-platform compatible for macOS and iOS.
//

import SwiftUI

struct TrackRowView: View {
    let track: TrackRecord
    @Binding var isShowingEditSheet: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", track.trackNumber))
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 24)

            // Cover art thumbnail
            if let coverID = track.coverDriveID, !coverID.isEmpty {
                SecureDriveImage(fileID: coverID)
                    .frame(width: 40, height: 40)
                    .cornerRadius(6)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: "music.note").font(.caption).foregroundColor(.secondary))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(track.artist) • \(track.albumId ?? "Single")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // File format badges
            HStack(spacing: 4) {
                Image(systemName: (track.googleDriveAACID?.isEmpty == false)
                      ? "a.circle.fill" : "a.circle")
                    .foregroundColor((track.googleDriveAACID?.isEmpty == false) ? .blue : .secondary.opacity(0.4))

                Image(systemName: (track.googleDriveALACID?.isEmpty == false)
                      ? "l.circle.fill" : "l.circle")
                    .foregroundColor((track.googleDriveALACID?.isEmpty == false) ? .purple : .secondary.opacity(0.4))
            }
            .font(.footnote)

            #if os(macOS)
            Divider().frame(height: 20).padding(.horizontal, 4)

            Button(action: {
                onEdit()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isShowingEditSheet = true
                }
            }) {
                Image(systemName: "pencil.circle.fill")
                    .foregroundColor(.blue).font(.title2)
            }
            .buttonStyle(.plain)
            .help("Edit Metadata")

            Button(action: onDelete) {
                Image(systemName: "trash.circle.fill")
                    .foregroundColor(.red).font(.title2)
            }
            .buttonStyle(.plain)
            .help("Delete this track")
            #endif
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        #if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Xóa", systemImage: "trash")
            }
            Button(action: {
                onEdit()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isShowingEditSheet = true
                }
            }) {
                Label("Sửa", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button(action: {
                onEdit()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isShowingEditSheet = true
                }
            }) {
                Label("Chỉnh sửa", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Xóa bài hát", systemImage: "trash")
            }
        }
        #endif
    }
}
