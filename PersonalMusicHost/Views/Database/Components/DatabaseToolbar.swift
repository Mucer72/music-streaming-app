//
//  DatabaseToolbar.swift
//  PersonalMusicHost
//
//  Top toolbar for DatabaseManagementView: title, mode picker (track/album/playlist),
//  loading indicator, bulk-delete button, and refresh button.
//

import SwiftUI

struct DatabaseToolbar: View {
    @EnvironmentObject var viewModel: DatabaseViewModel

    var body: some View {
        HStack {
            Text("CLOUD DATA MANAGEMENT")
                .font(.title2).fontWeight(.black).tracking(1.5)

            Picker("", selection: $viewModel.managementMode) {
                Text("Tracks").tag(ManagementMode.track)
                Text("Albums").tag(ManagementMode.album)
                Text("Playlists").tag(ManagementMode.playlist)
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
            .padding(.leading, 20)

            Spacer()

            if viewModel.isLoading {
                ProgressView().padding(.trailing, 10)
            }

            // Bulk delete button (shown only when items are selected)
            if viewModel.managementMode == .track && !viewModel.selectedTrackIDs.isEmpty {
                Button(role: .destructive, action: { viewModel.deleteSelectedTracks() }) {
                    Image(systemName: "trash.fill")
                    Text("Delete \(viewModel.selectedTrackIDs.count) tracks")
                }
                .buttonStyle(.borderedProminent).tint(.red)

            } else if viewModel.managementMode == .album && !viewModel.selectedAlbumIDs.isEmpty {
                Button(role: .destructive, action: { viewModel.deleteSelectedAlbums() }) {
                    Image(systemName: "trash.fill")
                    Text("Delete \(viewModel.selectedAlbumIDs.count) albums")
                }
                .buttonStyle(.borderedProminent).tint(.red)

            } else if viewModel.managementMode == .playlist && !viewModel.selectedPlaylistIDs.isEmpty {
                Button(role: .destructive, action: { viewModel.deleteSelectedPlaylists() }) {
                    Image(systemName: "trash.fill")
                    Text("Delete \(viewModel.selectedPlaylistIDs.count) playlists")
                }
                .buttonStyle(.borderedProminent).tint(.red)
            }

            Button(action: {
                Task { await viewModel.refreshData() }
            }) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("Refresh")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}
