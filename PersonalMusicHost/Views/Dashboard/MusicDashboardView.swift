//
//  MusicDashboardView.swift
//  PersonalMusicHost
//
//  Main screen: two-column layout (library left, detail/player right).
//  All sub-panels and content sections live in Dashboard/Components/ and Dashboard/Panels/.
//

import SwiftUI

#if os(macOS)
struct MusicDashboardView: View {
    @EnvironmentObject var viewModel: PlayerViewModel
    @StateObject private var playlistManager = PlaylistManagerViewModel()

    @State private var selectedTrackDetail: TrackRecord?
    @State private var selectedAlbumDetail: AlbumRecord?
    @State private var selectedGenre: GenreRecord?
    @State private var selectedPlaylist: PlaylistRecord?
    @State private var trackToAddToPlaylist: TrackRecord?

    var body: some View {
        let isRightPanelVisible = selectedTrackDetail != nil
            || selectedAlbumDetail != nil
            || (!viewModel.playlist.isEmpty && viewModel.isPlayerExpanded)

        VStack(spacing: 0) {
            // ─── TOP BAR ───────────────────────────────────────────────
            DashboardTopBar(searchText: $viewModel.searchText)

            // ─── MAIN CONTENT ──────────────────────────────────────────
            GeometryReader { geometry in
                let isCompact = geometry.size.width < 800
                
                ZStack(alignment: .bottom) {
                    HStack(spacing: 0) {

                        // 👈 LEFT COLUMN: Library
                        if !isCompact || !isRightPanelVisible {
                            ScrollView {
                        if viewModel.isLoading {
                            ProgressView("Syncing...").padding(.top, 50)

                        } else if !viewModel.searchText.isEmpty {
                            SearchResultsView(
                                filteredAlbums: viewModel.filteredAlbums,
                                filteredTracks: viewModel.filteredTracks,
                                onAlbumTap: { album in
                                    withAnimation(.spring()) {
                                        selectedTrackDetail = nil
                                        selectedAlbumDetail = album
                                    }
                                },
                                onTrackTap: { track in
                                    withAnimation(.spring()) {
                                        selectedAlbumDetail = nil
                                        selectedTrackDetail = track
                                    }
                                },
                                onAddTrackToQueue: { track in
                                    withAnimation { viewModel.addToPlaylist(track) }
                                },
                                onAddTrackToPlaylist: { track in
                                    trackToAddToPlaylist = track
                                },
                                onAddAlbumToQueue: { album in
                                    withAnimation { viewModel.addAlbumToPlaylist(album) }
                                }
                            )

                        } else if let genre = selectedGenre {
                            let genreTracks = viewModel.tracks
                                .filter { $0.genreId == genre.id }
                                .sorted { $0.streamCount > $1.streamCount }
                            let genreAlbums = viewModel.albums.filter { $0.genreId == genre.id }

                            GenreResultsView(
                                genre: genre,
                                genreTracks: genreTracks,
                                genreAlbums: genreAlbums,
                                onBack: {
                                    withAnimation(.spring()) { selectedGenre = nil }
                                },
                                onAlbumTap: { album in
                                    withAnimation(.spring()) {
                                        selectedTrackDetail = nil
                                        selectedAlbumDetail = album
                                    }
                                },
                                onTrackTap: { track in
                                    withAnimation(.spring()) {
                                        selectedAlbumDetail = nil
                                        selectedTrackDetail = track
                                    }
                                },
                                onAddTrackToQueue: { track in
                                    withAnimation { viewModel.addToPlaylist(track) }
                                },
                                onAddTrackToPlaylist: { track in
                                    trackToAddToPlaylist = track
                                },
                                onAddAlbumToQueue: { album in
                                    withAnimation { viewModel.addAlbumToPlaylist(album) }
                                }
                            )

                        } else {
                            LibraryView(
                                viewModel: viewModel,
                                playlistManager: playlistManager,
                                onPlaylistSelect: { playlist in
                                    selectedPlaylist = playlist
                                },
                                onTrackSelect: { track in
                                    withAnimation(.spring()) {
                                        selectedAlbumDetail = nil
                                        selectedTrackDetail = track
                                    }
                                },
                                onAlbumSelect: { album in
                                    withAnimation(.spring()) {
                                        selectedTrackDetail = nil
                                        selectedAlbumDetail = album
                                    }
                                },
                                onGenreSelect: { genre in
                                    withAnimation(.spring()) { selectedGenre = genre }
                                },
                                onAddTrackToQueue: { track in
                                    withAnimation { viewModel.addToPlaylist(track) }
                                },
                                onAddTrackToPlaylist: { track in
                                    trackToAddToPlaylist = track
                                },
                                onAddAlbumToQueue: { album in
                                    withAnimation { viewModel.addAlbumToPlaylist(album) }
                                }
                            )
                        }
                    }
                    .frame(minWidth: isRightPanelVisible && !isCompact ? 450 : 0, maxWidth: .infinity)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
                    }

                    // 👉 RIGHT COLUMN: Detail panels / Player
                    if isRightPanelVisible {
                        VStack(spacing: 0) {
                            if let track = selectedTrackDetail {
                                TrackDetailPanelView(
                                    track: track,
                                    viewModel: viewModel,
                                    onBack: {
                                        withAnimation { selectedTrackDetail = nil }
                                    },
                                    onClose: {
                                        withAnimation {
                                            selectedTrackDetail = nil
                                            selectedAlbumDetail = nil
                                        }
                                    },
                                    onAdd: {
                                        withAnimation {
                                            viewModel.addToPlaylist(track)
                                            selectedTrackDetail = nil
                                        }
                                    },
                                    onAddToPlaylist: {
                                        trackToAddToPlaylist = track
                                    }
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)

                            } else if let album = selectedAlbumDetail {
                                AlbumDetailPanelView(
                                    album: album,
                                    viewModel: viewModel,
                                    onBack: {
                                        withAnimation { selectedAlbumDetail = nil }
                                    },
                                    onClose: {
                                        withAnimation { selectedAlbumDetail = nil }
                                    },
                                    onAdd: {
                                        withAnimation {
                                            viewModel.addAlbumToPlaylist(album)
                                            selectedAlbumDetail = nil
                                        }
                                    },
                                    onTrackSelect: { track in
                                        withAnimation { selectedTrackDetail = track }
                                    }
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)

                            } else {
                                // Turntable player
                                if viewModel.focusedTrack != nil {
                                    TurntableCDView()
                                        .environmentObject(viewModel)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                } else {
                                    Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                                }

                                Divider()
                                TrackCarouselView()
                                    .environmentObject(viewModel)
                                    .background(Color.gray.opacity(0.05))
                            }
                        }
                        .frame(minWidth: isCompact ? 0 : 320, maxWidth: isCompact ? .infinity : 690, maxHeight: .infinity)
                        .background(Color(NSColor.windowBackgroundColor))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }

                    // Mini player bar (when queue exists but player is collapsed)
                    if !viewModel.playlist.isEmpty
                        && !viewModel.isPlayerExpanded
                        && selectedTrackDetail == nil
                        && selectedAlbumDetail == nil {
                        MiniPlayerView()
                            .environmentObject(viewModel)
                            .padding()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .animation(.spring(), value: isRightPanelVisible)
        .animation(.spring(), value: viewModel.isPlayerExpanded)
        .task {
            await playlistManager.fetchPlaylists()
        }
        .sheet(item: $selectedPlaylist) { playlist in
            PlaylistDetailView(playlist: playlist) { track in
                selectedTrackDetail = track
            }
            .environmentObject(viewModel)
        }
        .sheet(item: $trackToAddToPlaylist) { track in
            AddToPlaylistSheet(track: track)
                .environmentObject(playlistManager)
        }
    }
}
#endif
