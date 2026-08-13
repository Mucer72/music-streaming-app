//
//  LibraryView.swift
//  PersonalMusicHost
//
//  The default home library view displaying playlists, top tracks,
//  albums, and genre chips in horizontally-scrolling sections.
//  Shown when the search field is empty and no genre is selected.
//

import SwiftUI

struct LibraryView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @ObservedObject var playlistManager: PlaylistManagerViewModel

    // Selection callbacks (state lives in parent MusicDashboardView)
    let onPlaylistSelect: (PlaylistRecord) -> Void
    let onTrackSelect: (TrackRecord) -> Void
    let onAlbumSelect: (AlbumRecord) -> Void
    let onGenreSelect: (GenreRecord) -> Void

    // Action callbacks (call through to viewModel, but routed via parent)
    let onAddTrackToQueue: (TrackRecord) -> Void
    let onAddTrackToPlaylist: (TrackRecord) -> Void
    let onAddAlbumToQueue: (AlbumRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {

            // Section 0: Danh Sách Phát (Playlists)
            SectionView(title: "📚 Playlists") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        // Liked Tracks (Virtual Playlist)
                        PlaylistCard(
                            title: "Liked",
                            description: "\(viewModel.likedTracks.count) tracks",
                            systemImage: "heart.fill",
                            color: .pink
                        )
                        .onTapGesture {
                            onPlaylistSelect(PlaylistRecord(
                                title: "Liked",
                                ownerUID: "",
                                trackIds: [],
                                type: .systemLiked
                            ))
                        }

                        // Custom Playlists
                        ForEach(playlistManager.userPlaylists) { playlist in
                            PlaylistCard(
                                title: LocalizedStringKey(playlist.title),
                                description: "\(playlist.trackIds.count) tracks",
                                systemImage: "music.note.list",
                                color: .blue
                            )
                            .onTapGesture { onPlaylistSelect(playlist) }
                        }
                    }
                    .padding(.horizontal)
                }
            }

            // Section 1: Top 10 Phát Nhiều Nhất
            if !viewModel.topTracks.isEmpty {
                SectionView(title: "🔥 Top 10 Most Played") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(Array(viewModel.topTracks.enumerated()), id: \.element.id) { index, track in
                                TrackCard(track: track, rank: index + 1)
                                    .onTapGesture {
                                        withAnimation(.spring()) { onTrackSelect(track) }
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }

            // Section 2: Albums Nổi Bật
            if !viewModel.albums.isEmpty {
                SectionView(title: "💿 Featured Albums") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(viewModel.albums, id: \.id) { album in
                                AlbumCard(album: album)
                                    .onTapGesture {
                                        withAnimation(.spring()) { onAlbumSelect(album) }
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }

            // Section 3: Thể Loại
            if !viewModel.availableGenres.isEmpty {
                SectionView(title: "🎭 Genres") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(viewModel.availableGenres) { genre in
                                Text(genre.name)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 24)
                                    .background(LinearGradient(
                                        gradient: Gradient(colors: [.blue, .purple]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                    .cornerRadius(8)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.spring()) { onGenreSelect(genre) }
                                    }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 100)
                    }
                }
            }
        }
        .padding(.vertical)
    }
}
