//
//  SearchResultsView.swift
//  PersonalMusicHost
//
//  Displays search results for both albums and tracks.
//  Shown in the library's left panel when the search field is non-empty.
//

import SwiftUI

struct SearchResultsView: View {
    let filteredAlbums: [AlbumRecord]
    let filteredTracks: [TrackRecord]
    let onAlbumTap: (AlbumRecord) -> Void
    let onTrackTap: (TrackRecord) -> Void
    let onAddTrackToQueue: (TrackRecord) -> Void
    let onAddTrackToPlaylist: (TrackRecord) -> Void
    let onAddAlbumToQueue: (AlbumRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !filteredAlbums.isEmpty {
                Text("Album Results")
                    .font(.title3).bold().padding(.horizontal)
                ForEach(filteredAlbums, id: \.id) { album in
                    AlbumRow(
                        album: album,
                        onTap: { onAlbumTap(album) },
                        onAddToQueue: { onAddAlbumToQueue(album) }
                    )
                    .padding(.horizontal)
                }
            }

            if !filteredTracks.isEmpty {
                Text("Track Results")
                    .font(.title3).bold().padding(.horizontal)
                ForEach(filteredTracks, id: \.id) { track in
                    TrackRow(
                        track: track,
                        isTop: false,
                        onTap: { onTrackTap(track) },
                        onAddToQueue: { onAddTrackToQueue(track) },
                        onAddToPlaylist: { onAddTrackToPlaylist(track) }
                    )
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical)
    }
}
