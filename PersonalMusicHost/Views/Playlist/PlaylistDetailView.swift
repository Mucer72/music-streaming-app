//
//  PlaylistDetailView.swift
//  PersonalMusicHost
//
//  Sheet view showing the full contents of a playlist (system "Liked" or user-created).
//  Supports playing, queuing, and selecting tracks.
//

import SwiftUI

struct PlaylistDetailView: View {
    let playlist: PlaylistRecord
    var onTrackSelect: ((TrackRecord) -> Void)?
    @EnvironmentObject var viewModel: PlayerViewModel
    @Environment(\.dismiss) var dismiss

    @State private var playlistTracks: [TrackRecord] = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Header
            #if os(iOS)
            VStack(alignment: .center, spacing: 16) {
                HStack {
                    Spacer()
                    PanelCloseButton(action: { dismiss() })
                }
                
                // Cover art
                if let coverID = playlist.coverDriveID {
                    SecureDriveImage(fileID: coverID)
                        .frame(width: 140, height: 140)
                        .cornerRadius(12).shadow(radius: 5)
                } else {
                    ZStack {
                        Color.gray.opacity(0.3)
                        Image(systemName: "music.note.list")
                            .font(.system(size: 40)).foregroundColor(.gray)
                    }
                    .frame(width: 140, height: 140)
                    .cornerRadius(12).shadow(radius: 5)
                }
                
                VStack(alignment: .center, spacing: 6) {
                    Text("PLAYLIST")
                        .font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                    
                    Text(playlist.title)
                        .font(.title2).fontWeight(.bold).lineLimit(2)
                        .multilineTextAlignment(.center)
                    
                    if let description = playlist.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    HStack {
                        Text("\(playlist.trackIds.count) tracks")
                            .font(.subheadline).foregroundColor(.secondary)
                        Text("•").foregroundColor(.secondary)
                        if playlist.isPublic {
                            Text("Public").font(.subheadline).foregroundColor(.secondary)
                        } else {
                            Text("Private").font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(spacing: 24) {
                        Button(action: {
                            if !playlistTracks.isEmpty {
                                viewModel.playTracks(playlistTracks)
                                dismiss()
                            }
                        }) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 44)).foregroundColor(.blue)
                        }
                        .buttonStyle(.plain).disabled(playlistTracks.isEmpty)
                        
                        Button(action: {
                            if !playlistTracks.isEmpty {
                                viewModel.addTracksToPlaylist(playlistTracks)
                            }
                        }) {
                            Image(systemName: "plus.square.fill.on.square.fill")
                                .font(.title).foregroundColor(.purple)
                        }
                        .buttonStyle(.plain)
                        .disabled(playlistTracks.isEmpty)
                    }
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            #else
            HStack(alignment: .top, spacing: 20) {
                // Cover art
                if let coverID = playlist.coverDriveID {
                    SecureDriveImage(fileID: coverID)
                        .frame(width: 150, height: 150)
                        .cornerRadius(12).shadow(radius: 5)
                } else {
                    ZStack {
                        Color.gray.opacity(0.3)
                        Image(systemName: "music.note.list")
                            .font(.system(size: 50)).foregroundColor(.gray)
                    }
                    .frame(width: 150, height: 150)
                    .cornerRadius(12).shadow(radius: 5)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("PLAYLIST")
                        .font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                    
                    Text(playlist.title)
                        .font(.system(size: 36, weight: .bold)).lineLimit(2)
                    
                    if let description = playlist.description {
                        Text(description).font(.subheadline).foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("\(playlist.trackIds.count) tracks")
                            .font(.subheadline).foregroundColor(.secondary)
                        Text("•").foregroundColor(.secondary)
                        if playlist.isPublic {
                            Text("Public").font(.subheadline).foregroundColor(.secondary)
                        } else {
                            Text("Private").font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(spacing: 16) {
                        Button(action: {
                            if !playlistTracks.isEmpty {
                                viewModel.playTracks(playlistTracks)
                                dismiss()
                            }
                        }) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 44)).foregroundColor(.blue)
                        }
                        .buttonStyle(.plain).disabled(playlistTracks.isEmpty)
                        
                        Button(action: {
                            if !playlistTracks.isEmpty {
                                viewModel.addTracksToPlaylist(playlistTracks)
                            }
                        }) {
                            Image(systemName: "plus.square.fill.on.square.fill")
                                .font(.title).foregroundColor(.purple)
                        }
                        .buttonStyle(.plain)
                        .disabled(playlistTracks.isEmpty)
                        .help("Add entire playlist to queue")
                    }
                    .padding(.top, 8)
                }
                
                Spacer()
                PanelCloseButton(action: { dismiss() })
            }
            .padding()
            #endif

            Divider()

            // MARK: - Track List
            if isLoading {
                Spacer()
                ProgressView("Loading tracks...").frame(maxWidth: .infinity)
                Spacer()
            } else if playlistTracks.isEmpty {
                Spacer()
                Text("This playlist has no tracks yet.")
                    .foregroundColor(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    ForEach(Array(playlistTracks.enumerated()), id: \.element.id) { index, track in
                        HStack {
                            Text("\(index + 1)")
                                .font(.caption).foregroundColor(.secondary)
                                .frame(width: 24, alignment: .leading)

                            ZStack(alignment: .bottomTrailing) {
                                SecureDriveImage(fileID: track.coverDriveID)
                                    .frame(width: 40, height: 40)
                                    .cornerRadius(4)
                                
                                let isLiked = viewModel.likedTrackIds.contains(track.id ?? "")
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(isLiked ? .pink : .white)
                                    .frame(width: 18, height: 18)
                                    .background(Color.black.opacity(0.55))
                                    .clipShape(Circle())
                                    .offset(x: 2, y: 2)
                                    .onTapGesture {
                                        viewModel.toggleLike(for: track)
                                    }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title).font(.subheadline).bold().lineLimit(1)
                                Text(track.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
                            }

                            Spacer()

                            Button(action: { viewModel.playTrack(track); dismiss() }) {
                                Image(systemName: "play.fill").foregroundColor(.blue).font(.title3)
                            }.buttonStyle(.plain)

                            Button(action: { withAnimation { viewModel.addToPlaylist(track) } }) {
                                Image(systemName: "plus.circle.fill").foregroundColor(.purple).font(.title3)
                            }.buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let onTrackSelect = onTrackSelect {
                                onTrackSelect(track); dismiss()
                            } else {
                                viewModel.playTrack(track); dismiss()
                            }
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        .background(Color(NSColor.windowBackgroundColor))
        #else
        .background(Color(.systemBackground))
        #endif
        .task { await loadTracks() }
    }

    private func loadTracks() async {
        defer { isLoading = false }  // Đảm bảo luôn tắt loading dù có lỗi
        if playlist.type == .systemLiked {
            self.playlistTracks = viewModel.likedTracks
            return
        }
        do {
            // ✅ Route qua ViewModel thay vì gọi Service trực tiếp — đúng MVVM
            self.playlistTracks = try await viewModel.fetchPlaylistTracks(trackIds: playlist.trackIds)
        } catch {
            print("Error loading tracks for playlist: \(error.localizedDescription)")
        }
    }
}
