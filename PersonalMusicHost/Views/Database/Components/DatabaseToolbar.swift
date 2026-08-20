//
//  DatabaseToolbar.swift
//  PersonalMusicHost
//
//  Top toolbar for DatabaseManagementView: title, mode picker (track/album/playlist),
//  loading indicator, bulk-delete button, and refresh button.
//  Cross-platform compatible for macOS and iOS.
//

import SwiftUI

struct DatabaseToolbar: View {
    @EnvironmentObject var viewModel: DatabaseViewModel

    var body: some View {
        #if os(macOS)
        HStack {
            Text("QUẢN LÝ DỮ LIỆU CLOUD")
                .font(.title2).fontWeight(.black).tracking(1.5)

            Picker("", selection: $viewModel.managementMode) {
                Text("Bài hát").tag(ManagementMode.track)
                Text("Album").tag(ManagementMode.album)
                Text("Playlist").tag(ManagementMode.playlist)
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            .padding(.leading, 16)

            Spacer()

            if viewModel.isLoading {
                ProgressView().padding(.trailing, 10)
            }

            // Bulk delete button (shown only when items are selected)
            if viewModel.managementMode == .track && !viewModel.selectedTrackIDs.isEmpty {
                Button(role: .destructive, action: { viewModel.deleteSelectedTracks() }) {
                    Image(systemName: "trash.fill")
                    Text("Xóa \(viewModel.selectedTrackIDs.count) bài")
                }
                .buttonStyle(.borderedProminent).tint(.red)

            } else if viewModel.managementMode == .album && !viewModel.selectedAlbumIDs.isEmpty {
                Button(role: .destructive, action: { viewModel.deleteSelectedAlbums() }) {
                    Image(systemName: "trash.fill")
                    Text("Xóa \(viewModel.selectedAlbumIDs.count) album")
                }
                .buttonStyle(.borderedProminent).tint(.red)

            } else if viewModel.managementMode == .playlist && !viewModel.selectedPlaylistIDs.isEmpty {
                Button(role: .destructive, action: { viewModel.deleteSelectedPlaylists() }) {
                    Image(systemName: "trash.fill")
                    Text("Xóa \(viewModel.selectedPlaylistIDs.count) playlist")
                }
                .buttonStyle(.borderedProminent).tint(.red)
            }

            Button(action: {
                Task { await viewModel.refreshData() }
            }) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("Làm mới")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.ultraThinMaterial)
        #else
        // iOS Segmented Bar
        VStack(spacing: 8) {
            Picker("Chế độ", selection: $viewModel.managementMode) {
                Text("Bài hát").tag(ManagementMode.track)
                Text("Album").tag(ManagementMode.album)
                Text("Playlist").tag(ManagementMode.playlist)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 4)
        }
        #endif
    }
}
