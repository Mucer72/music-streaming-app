//
//  GenreResultsView.swift
//  PersonalMusicHost
//
//  Displays filtered albums and tracks for a selected genre.
//  Shown in the library's left panel when a genre chip is tapped.
//

import SwiftUI

struct GenreResultsView: View {
    let genre: GenreRecord
    let genreTracks: [TrackRecord]
    let genreAlbums: [AlbumRecord]
    let onBack: () -> Void
    let onAlbumTap: (AlbumRecord) -> Void
    let onTrackTap: (TrackRecord) -> Void
    let onAddTrackToQueue: (TrackRecord) -> Void
    let onAddTrackToPlaylist: (TrackRecord) -> Void
    let onAddAlbumToQueue: (AlbumRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Back header
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left.circle.fill").font(.title2)
                    Text("Genre: \(genre.name)").font(.title2).bold()
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            if !genreAlbums.isEmpty {
                Text("Featured Albums")
                    .font(.title3).bold().padding(.horizontal)
                ForEach(genreAlbums, id: \.id) { album in
                    AlbumRow(
                        album: album,
                        onTap: { onAlbumTap(album) },
                        onAddToQueue: { onAddAlbumToQueue(album) }
                    )
                    .padding(.horizontal)
                }
            }

            if !genreTracks.isEmpty {
                Text("Tracks")
                    .font(.title3).bold().padding(.horizontal)
                ForEach(genreTracks, id: \.id) { track in
                    TrackRow(
                        track: track,
                        isTop: false,
                        onTap: { onTrackTap(track) },
                        onAddToQueue: { onAddTrackToQueue(track) },
                        onAddToPlaylist: { onAddTrackToPlaylist(track) }
                    )
                    .padding(.horizontal)
                }
            } else if genreAlbums.isEmpty {
                Text("No data available for this genre.")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .padding(.vertical)
    }
}
