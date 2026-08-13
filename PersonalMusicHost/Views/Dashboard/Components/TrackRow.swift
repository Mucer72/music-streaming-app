//
//  TrackRow.swift
//  PersonalMusicHost
//
//  Row view for a track in list-based sections (search results, genre view).
//  Supports optional rank display and exposes callbacks for all actions.
//

import SwiftUI

struct TrackRow: View {
    let track: TrackRecord
    let isTop: Bool
    var rank: Int = 0
    let onTap: () -> Void
    let onAddToQueue: () -> Void
    let onAddToPlaylist: () -> Void

    var body: some View {
        HStack {
            if isTop {
                Text("#\(rank)")
                    .font(.caption).bold()
                    .foregroundColor(.secondary)
                    .frame(width: 20, alignment: .leading)
            }

            SecureDriveImage(fileID: track.coverDriveID)
                .frame(width: 40, height: 40)
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 4) {
                Text(track.title).font(.subheadline).bold().lineLimit(1)
                Text(track.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }

            Spacer()

            Button(action: onAddToPlaylist) {
                Image(systemName: "text.badge.plus").foregroundColor(.purple).font(.title3)
            }.buttonStyle(.plain)

            Button(action: onAddToQueue) {
                Image(systemName: "plus.circle.fill").foregroundColor(.blue).font(.title3)
            }.buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}
