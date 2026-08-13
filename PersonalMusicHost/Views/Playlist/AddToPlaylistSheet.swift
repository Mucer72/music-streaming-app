//
//  AddToPlaylistSheet.swift
//  PersonalMusicHost
//
//  Sheet for adding a track to an existing playlist or creating a new one.
//

import SwiftUI

struct AddToPlaylistSheet: View {
    let track: TrackRecord
    @EnvironmentObject var playlistManager: PlaylistManagerViewModel
    @Environment(\.dismiss) var dismiss

    @State private var showingNewPlaylistAlert = false
    @State private var newPlaylistTitle = ""

    var body: some View {
        NavigationView {
            VStack {
                if playlistManager.isLoading {
                    ProgressView("Loading playlists...").padding()

                } else if playlistManager.userPlaylists.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 40)).foregroundColor(.gray)
                        Text("You don't have any playlists yet.").foregroundColor(.secondary)
                    }
                    .padding(.top, 40)

                } else {
                    List {
                        ForEach(playlistManager.userPlaylists) { playlist in
                            Button(action: {
                                Task {
                                    let success = await playlistManager.addTrackToPlaylist(
                                        track: track, playlist: playlist)
                                    if success { dismiss() }
                                }
                            }) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(playlist.title).font(.headline)
                                        (Text("\(playlist.trackIds.count) tracks • ") + (playlist.isPublic ? Text("Public") : Text("Private")))
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if let trackId = track.id, playlist.trackIds.contains(trackId) {
                                        Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                        }
                    }
                }

                Spacer()

                Button(action: { showingNewPlaylistAlert = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Create New Playlist").fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding()
                    .background(Color.blue).cornerRadius(12)
                }
                .buttonStyle(.plain)
                .padding()
            }
            .navigationTitle("Add to Playlist")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Create Playlist", isPresented: $showingNewPlaylistAlert) {
                TextField("Playlist Name", text: $newPlaylistTitle)
                Button("Cancel", role: .cancel) { newPlaylistTitle = "" }
                Button("Create & Add Track") {
                    let title = newPlaylistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { return }
                    Task {
                        let success = await playlistManager.createNewPlaylistAndAddTrack(
                            title: title, track: track)
                        if success { dismiss() }
                    }
                }
            } message: {
                Text("Enter a name for your new playlist.")
            }
        }
        .task { await playlistManager.fetchPlaylists() }
    }
}
