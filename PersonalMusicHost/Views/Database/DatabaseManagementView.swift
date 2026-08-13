//
//  DatabaseManagementView.swift
//  PersonalMusicHost
//
//  Cloud database management screen. Orchestrates the toolbar,
//  search/sort bar, and data table for tracks, albums, and playlists.
//  All row components live in Database/Components/.
//

import SwiftUI

struct DatabaseManagementView: View {
    @EnvironmentObject var viewModel: DatabaseViewModel
    @State private var editingTrack: TrackRecord?
    @State private var editingAlbum: AlbumRecord?
    @State private var editingPlaylist: PlaylistRecord?
    @State private var isShowingEditSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // ─── TOOLBAR ───────────────────────────────────────────────
            DatabaseToolbar()

            // ─── SEARCH & SORT ─────────────────────────────────────────
            HStack {
                TextField("🔍 Search by track name...", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)

                Picker("Sort:", selection: $viewModel.sortOption) {
                    Text("By Album").tag("albumId")
                    Text("By Title").tag("title")
                    Text("By Artist").tag("artist")
                }
                .pickerStyle(.menu)
                .frame(width: 200)
                // Disable sort while searching to avoid Firestore composite index conflicts
                .disabled(!viewModel.searchText.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            // ─── DATA TABLE ────────────────────────────────────────────
            if viewModel.managementMode == .album {
                List(selection: $viewModel.selectedAlbumIDs) {
                    ForEach(viewModel.albums, id: \.id) { album in
                        AlbumRowView(
                            album: album,
                            onEdit: { editingAlbum = album }
                        )
                        .tag(album.id ?? "")
                    }
                }
                .listStyle(.inset)

            } else if viewModel.managementMode == .playlist {
                List(selection: $viewModel.selectedPlaylistIDs) {
                    ForEach(viewModel.playlists, id: \.id) { playlist in
                        PlaylistRowView(
                            playlist: playlist,
                            onEdit: { editingPlaylist = playlist }
                        )
                        .tag(playlist.id ?? "")
                    }
                }
                .listStyle(.inset)

            } else {
                List(selection: $viewModel.selectedTrackIDs) {
                    ForEach(viewModel.tracks, id: \.id) { track in
                        TrackRowView(
                            track: track,
                            isShowingEditSheet: $isShowingEditSheet,
                            onEdit: { editingTrack = track },
                            onDelete: { viewModel.deleteSingleTrack(track) }
                        )
                        .tag(track.id ?? "")
                        .onAppear {
                            if track.id == viewModel.tracks.last?.id {
                                viewModel.loadMoreData()
                            }
                        }
                    }

                    if viewModel.isFetchingMore {
                        HStack {
                            Spacer()
                            ProgressView("Loading more data...")
                            Spacer()
                        }
                        .padding()
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear {
            // Chỉ fetch lần đầu tiên vào màn hình. Lần sau sử dụng data trong bộ nhớ.
            // Kéo xuống đầu danh sách để làm mới dữ liệu (pull-to-refresh).
            if !viewModel.hasLoadedInitially {
                viewModel.loadInitialData()
            }
        }
        .sheet(item: $editingTrack) { track in
            EditTrackView(
                track: track,
                isPresented: Binding(get: { true }, set: { if !$0 { editingTrack = nil } })
            ) { updatedTrack in
                viewModel.saveChanges(for: updatedTrack)
            }
            .environmentObject(viewModel)
            .id(track.id)
        }
        .sheet(item: $editingAlbum) { album in
            EditAlbumView(
                album: album,
                isPresented: Binding(get: { true }, set: { if !$0 { editingAlbum = nil } })
            ) { updatedAlbum in
                viewModel.saveAlbumChanges(for: updatedAlbum)
            }
            .environmentObject(viewModel)
            .id(album.id)
        }
        .sheet(item: $editingPlaylist) { playlist in
            EditPlaylistView(
                playlist: playlist,
                isPresented: Binding(get: { true }, set: { if !$0 { editingPlaylist = nil } })
            ) { updatedPlaylist in
                viewModel.savePlaylistChanges(for: updatedPlaylist)
            }
            .environmentObject(viewModel)
            .id(playlist.id)
        }
    }
}
