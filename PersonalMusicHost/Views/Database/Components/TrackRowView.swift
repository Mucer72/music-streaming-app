//
//  TrackRowView.swift
//  PersonalMusicHost
//
//  List row for a track in DatabaseManagementView.
//  Shows track number, title/artist, file-format badges, and edit/delete actions.
//

import SwiftUI

struct TrackRowView: View {
    let track: TrackRecord
    @Binding var isShowingEditSheet: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 15) {
            Text(String(format: "%02d", track.trackNumber))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(track.title).font(.headline)
                Text("\(track.artist) • \(track.albumId ?? "Single")")
                    .font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            // File format badges
            HStack(spacing: 4) {
                Image(systemName: (track.googleDriveAACID?.isEmpty == false)
                      ? "a.circle.fill" : "a.circle")
                    .foregroundColor((track.googleDriveAACID?.isEmpty == false) ? .blue : .gray)

                Image(systemName: (track.googleDriveALACID?.isEmpty == false)
                      ? "l.circle.fill" : "l.circle")
                    .foregroundColor((track.googleDriveALACID?.isEmpty == false) ? .purple : .gray)
            }

            Divider().frame(height: 20).padding(.horizontal, 8)

            Button(action: {
                onEdit()
                // Small delay to let state propagate before the sheet triggers
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
        }
        .padding(.vertical, 4)
    }
}
