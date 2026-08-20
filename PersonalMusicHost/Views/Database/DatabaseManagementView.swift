//
//  DatabaseManagementView.swift
//  PersonalMusicHost
//
//  Cloud database management screen. Orchestrates the toolbar,
//  search/sort bar, and data table for tracks, albums, and playlists.
//  Cross-platform compatible for macOS and iOS.
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

            // ─── SEARCH & SORT BAR ─────────────────────────────────────
            HStack(spacing: 12) {
                #if os(macOS)
                TextField("🔍 Tìm kiếm bài hát...", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                #else
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Tìm kiếm theo tên...", text: $viewModel.searchText)
                    if !viewModel.searchText.isEmpty {
                        Button(action: { viewModel.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                #endif

                if viewModel.managementMode == .track {
                    Menu {
                        Button(action: { viewModel.sortOption = "albumId" }) {
                            Label("Theo Album", systemImage: viewModel.sortOption == "albumId" ? "checkmark" : "")
                        }
                        Button(action: { viewModel.sortOption = "title" }) {
                            Label("Theo Tên bài hát", systemImage: viewModel.sortOption == "title" ? "checkmark" : "")
                        }
                        Button(action: { viewModel.sortOption = "artist" }) {
                            Label("Theo Nghệ sĩ", systemImage: viewModel.sortOption == "artist" ? "checkmark" : "")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                            #if os(macOS)
                            Text("Sắp xếp")
                            #endif
                        }
                    }
                    .disabled(!viewModel.searchText.isEmpty)
                    #if os(macOS)
                    .frame(width: 120)
                    #endif
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // ─── DATA LIST ─────────────────────────────────────────────
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
                .refreshable {
                    await viewModel.refreshData()
                }

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
                .refreshable {
                    await viewModel.refreshData()
                }

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
                            ProgressView("Đang tải thêm...")
                            Spacer()
                        }
                        .padding()
                    }
                }
                .listStyle(.inset)
                .refreshable {
                    await viewModel.refreshData()
                }
            }
        }
        .navigationTitle("Quản lý Thư viện")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button(action: {
                        Task { await viewModel.refreshData() }
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }
        #endif
        .onAppear {
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
