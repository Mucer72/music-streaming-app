//
//  MobileMainAppView.swift
//  MobileMusicStreaming
//
//  Created by TwentyMikeyOne on 14/7/26.
//

import SwiftUI

struct MobileMainAppView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    
    @StateObject private var playerViewModel = PlayerViewModel()
    @StateObject private var playlistManager = PlaylistManagerViewModel()
    
    @State private var selectedTab = 0
    @State private var selectedPlaylist: PlaylistRecord?
    @State private var selectedAlbum: AlbumRecord?
    @State private var selectedGenre: GenreRecord?
    @State private var trackToAddToPlaylist: TrackRecord?
    @State private var selectedTrackDetail: TrackRecord?
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Main Tab Navigation (Native TabView restored)
            TabView(selection: $selectedTab) {
                // Tab 1: Library
                NavigationStack {
                    ScrollView {
                        LibraryView(
                            viewModel: playerViewModel,
                            playlistManager: playlistManager,
                            onPlaylistSelect: { playlist in
                                selectedPlaylist = playlist
                            },
                            onTrackSelect: { track in
                                selectedTrackDetail = track
                            },
                            onAlbumSelect: { album in
                                selectedAlbum = album
                            },
                            onGenreSelect: { genre in
                                selectedGenre = genre
                            },
                            onAddTrackToQueue: { track in
                                playerViewModel.addToPlaylist(track)
                            },
                            onAddTrackToPlaylist: { track in
                                trackToAddToPlaylist = track
                            },
                            onAddAlbumToQueue: { album in
                                playerViewModel.addAlbumToPlaylist(album)
                            }
                        )
                    }
                    .navigationTitle("Thư viện")
                    .background(Color(.systemBackground))
                }
                .tabItem {
                    Label("Thư viện", systemImage: "music.note.house")
                }
                .tag(0)
                
                // Tab 2: Playlists (Dedicated Tab)
                MobilePlaylistsTab(
                    viewModel: playerViewModel,
                    playlistManager: playlistManager,
                    onPlaylistSelect: { playlist in
                        selectedPlaylist = playlist
                    }
                )
                .tabItem {
                    Label("Playlist", systemImage: "music.note.list")
                }
                .tag(1)
                
                // Tab 3: Search
                NavigationStack {
                    ScrollView {
                        if playerViewModel.searchText.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 60))
                                    .foregroundColor(.secondary)
                                Text("Tìm kiếm bài hát, nghệ sĩ hoặc album...")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 100)
                            .frame(maxWidth: .infinity)
                        } else {
                            SearchResultsView(
                                filteredAlbums: playerViewModel.filteredAlbums,
                                filteredTracks: playerViewModel.filteredTracks,
                                onAlbumTap: { album in
                                    selectedAlbum = album
                                },
                                onTrackTap: { track in
                                    selectedTrackDetail = track
                                },
                                onAddTrackToQueue: { track in
                                    playerViewModel.addToPlaylist(track)
                                },
                                onAddTrackToPlaylist: { track in
                                    trackToAddToPlaylist = track
                                },
                                onAddAlbumToQueue: { album in
                                    playerViewModel.addAlbumToPlaylist(album)
                                }
                            )
                        }
                    }
                    .navigationTitle("Tìm kiếm")
                    .searchable(text: $playerViewModel.searchText, prompt: "Bài hát, nghệ sĩ, album...")
                    .background(Color(.systemBackground))
                }
                .tabItem {
                    Label("Tìm kiếm", systemImage: "magnifyingglass")
                }
                .tag(2)
                
                // Tab 4: Profile
                NavigationStack {
                    ProfileView()
                        .environmentObject(authViewModel)
                }
                .tabItem {
                    Label("Cá nhân", systemImage: "person.crop.circle")
                }
                .tag(3)
            }
            .accentColor(.blue)
            
            // Floating Mini Player (displayed above TabBar if a track is active)
            if playerViewModel.playingTrack != nil {
                MiniPlayerView()
                    .environmentObject(playerViewModel)
                    .padding(.horizontal)
                    .padding(.bottom, 56) // Hover cleanly above native TabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(), value: playerViewModel.playingTrack?.id)
        .task {
            await playlistManager.fetchPlaylists()
        }
        // Sheet: Custom Playlists Detail View
        .sheet(item: $selectedPlaylist) { playlist in
            NavigationStack {
                PlaylistDetailView(playlist: playlist) { track in
                    selectedTrackDetail = track
                }
                .environmentObject(playerViewModel)
            }
        }
        // Sheet: Album Detail Panel (embedded as sheet on mobile)
        .sheet(item: $selectedAlbum) { album in
            NavigationStack {
                AlbumDetailPanelView(
                    album: album,
                    viewModel: playerViewModel,
                    onBack: { selectedAlbum = nil },
                    onClose: { selectedAlbum = nil },
                    onAdd: {
                        playerViewModel.addAlbumToPlaylist(album)
                        selectedAlbum = nil
                    },
                    onTrackSelect: { track in
                        selectedTrackDetail = track
                        selectedAlbum = nil
                    }
                )
                .environmentObject(playerViewModel)
            }
        }
        // Sheet: Genre Selection Results View
        .sheet(item: $selectedGenre) { genre in
            let genreTracks = playerViewModel.tracks.filter { $0.genreId == genre.id }
            let genreAlbums = playerViewModel.albums.filter { $0.genreId == genre.id }
            
            NavigationStack {
                GenreResultsView(
                    genre: genre,
                    genreTracks: genreTracks,
                    genreAlbums: genreAlbums,
                    onBack: { selectedGenre = nil },
                    onAlbumTap: { album in
                        selectedAlbum = album
                        selectedGenre = nil
                    },
                    onTrackTap: { track in
                        selectedTrackDetail = track
                        selectedGenre = nil
                    },
                    onAddTrackToQueue: { track in
                        playerViewModel.addToPlaylist(track)
                    },
                    onAddTrackToPlaylist: { track in
                        trackToAddToPlaylist = track
                    },
                    onAddAlbumToQueue: { album in
                        playerViewModel.addAlbumToPlaylist(album)
                    }
                )
            }
        }
        .sheet(item: $trackToAddToPlaylist) { track in
            AddToPlaylistSheet(track: track)
                .environmentObject(playlistManager)
        }
        // Sheet: Track Detail panel
        .sheet(item: $selectedTrackDetail) { track in
            NavigationStack {
                TrackDetailPanelView(
                    track: track,
                    viewModel: playerViewModel,
                    onBack: { selectedTrackDetail = nil },
                    onClose: { selectedTrackDetail = nil },
                    onAdd: {
                        playerViewModel.addToPlaylist(track)
                        selectedTrackDetail = nil
                    },
                    onAddToPlaylist: {
                        trackToAddToPlaylist = track
                        selectedTrackDetail = nil
                    }
                )
                .environmentObject(playerViewModel)
            }
        }
        .sheet(isPresented: $playerViewModel.isPlayerExpanded) {
            MobilePlayerSheetView()
                .environmentObject(playerViewModel)
        }
    }
}

struct MobilePlayerSheetView: View {
    @EnvironmentObject var viewModel: PlayerViewModel
    
    var body: some View {
        ZStack {
            // Elegant dark gradient background
            LinearGradient(
                colors: [Color.black, Color(red: 0.1, green: 0.1, blue: 0.15)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 10) {
                // Drag handle bar
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 40, height: 5)
                    .padding(.top, 12)
                
                // Playing Track Details
                VStack(spacing: 4) {
                    Text(viewModel.focusedTrack?.title ?? "Không có bài hát")
                        .font(.title2).fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(viewModel.focusedTrack?.artist ?? "")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal)
                
                // Show Turntable spinning CD
                TurntableCDView()
                    .environmentObject(viewModel)
                    .frame(maxHeight: .infinity)
                
                // Playlist Queue (Always visible inside a glass deck)
                VStack(spacing: 0) {
                    TrackCarouselView()
                        .environmentObject(viewModel)
                }
                .background(.thinMaterial)
                .cornerRadius(24)
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
        }
    }
}

// MARK: - Mobile Playlists Tab View
struct MobilePlaylistsTab: View {
    @ObservedObject var viewModel: PlayerViewModel
    @ObservedObject var playlistManager: PlaylistManagerViewModel
    let onPlaylistSelect: (PlaylistRecord) -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Virtual "Liked Tracks" Playlist Row
                    PlaylistRowView(
                        title: "Bài hát đã thích",
                        description: "\(viewModel.likedTracks.count) bài hát",
                        systemImage: "heart.fill",
                        color: .pink
                    ) {
                        onPlaylistSelect(PlaylistRecord(
                            title: "Đã thích",
                            ownerUID: "",
                            trackIds: [],
                            type: .systemLiked
                        ))
                    }
                    
                    // User Custom Playlists
                    ForEach(playlistManager.userPlaylists) { playlist in
                        PlaylistRowView(
                            title: playlist.title,
                            description: "\(playlist.trackIds.count) bài hát",
                            systemImage: "music.note.list",
                            color: .blue
                        ) {
                            onPlaylistSelect(playlist)
                        }
                    }
                }
                .padding()
                .padding(.top, 8)
            }
            .navigationTitle("Danh sách phát")
            .background(Color(.systemBackground))
        }
    }
}

struct PlaylistRowView: View {
    let title: String
    let description: String
    let systemImage: String
    let color: Color
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Color.clear
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundColor(.white)
            }
            .frame(width: 52, height: 52)
            .background(
                LinearGradient(
                    colors: [color, color.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(12)
            .shadow(color: color.opacity(0.35), radius: 6, y: 3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.footnote)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .cornerRadius(16)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

