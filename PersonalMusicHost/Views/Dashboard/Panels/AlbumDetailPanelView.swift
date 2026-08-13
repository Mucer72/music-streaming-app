//
//  AlbumDetailPanelView.swift
//  PersonalMusicHost
//
//  Right-panel detail view for a selected album. Displays cover art,
//  album metadata, contributor info, and a track list.
//

import SwiftUI

struct AlbumDetailPanelView: View {
    let album: AlbumRecord
    @ObservedObject var viewModel: PlayerViewModel
    let onBack: () -> Void
    let onClose: () -> Void
    let onAdd: () -> Void
    let onTrackSelect: (TrackRecord) -> Void

    @State private var albumTracks: [TrackRecord] = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Responsive Header (macOS Horizontal, iOS Vertical)
            #if os(macOS)
            HStack(alignment: .top, spacing: 20) {
                PanelBackButton(action: onBack)

                SecureDriveImage(fileID: album.coverDriveID)
                    .frame(width: 150, height: 150)
                    .cornerRadius(12)
                    .shadow(radius: 5)

                VStack(alignment: .leading, spacing: 8) {
                    Text("ALBUM")
                        .font(.caption).fontWeight(.bold).foregroundColor(.secondary)

                    Text(album.title)
                        .font(.system(size: 32, weight: .bold))
                        .lineLimit(2)

                    Text("\(album.artist) • \(album.releaseYear, format: .number.grouping(.never))")
                        .font(.title3).foregroundColor(.secondary)

                    if let genreId = album.genreId,
                       let genre = viewModel.availableGenres.first(where: { $0.id == genreId }) {
                        Text(genre.name)
                            .font(.subheadline).foregroundColor(.secondary)
                    }

                    if let description = album.description, !description.isEmpty {
                        Text(description)
                            .font(.caption).foregroundColor(.secondary).italic().lineLimit(2)
                    }

                    HStack {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.secondary).font(.caption)
                        NavigationLink(value: AppRoute.userProfile(album.contributor)) {
                            Text(viewModel.usersCache[album.contributor]?.displayName
                                 ?? viewModel.usersCache[album.contributor]?.email
                                 ?? album.contributor)
                                .font(.caption).foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 16) {
                        Button(action: {
                            if !albumTracks.isEmpty { 
                                viewModel.playTracks(albumTracks) 
                                onClose()
                            }
                        }) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 40)).foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .disabled(albumTracks.isEmpty)

                        Button(action: {
                            if !albumTracks.isEmpty { viewModel.addTracksToPlaylist(albumTracks) }
                        }) {
                            Image(systemName: "plus.square.fill.on.square.fill")
                                .font(.title2).foregroundColor(.purple)
                        }
                        .buttonStyle(.plain)
                        .disabled(albumTracks.isEmpty)
                    }
                    .padding(.top, 8)
                }

                Spacer()
                PanelCloseButton(action: onClose)
            }
            .padding()
            #else
            VStack(spacing: 16) {
                // Navigation controls
                HStack {
                    PanelBackButton(action: onBack)
                    Spacer()
                    PanelCloseButton(action: onClose)
                }
                
                // Centered Cover
                SecureDriveImage(fileID: album.coverDriveID)
                    .frame(width: 180, height: 180)
                    .cornerRadius(16)
                    .shadow(radius: 8)
                
                // Album Metadata
                VStack(spacing: 6) {
                    Text("ALBUM")
                        .font(.caption).bold().foregroundColor(.secondary)
                    
                    Text(album.title)
                        .font(.title2).bold()
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    
                    Text("\(album.artist) • \(album.releaseYear)")
                        .font(.headline).foregroundColor(.secondary)
                    
                    if let genreId = album.genreId,
                       let genre = viewModel.availableGenres.first(where: { $0.id == genreId }) {
                        Text(genre.name)
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    
                    if let description = album.description, !description.isEmpty {
                        Text(description)
                            .font(.caption).foregroundColor(.secondary).italic()
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                    }
                }
                .padding(.horizontal)
                
                // Contributor info
                HStack(spacing: 4) {
                    Image(systemName: "person.circle.fill")
                        .foregroundColor(.secondary).font(.caption)
                    NavigationLink(value: AppRoute.userProfile(album.contributor)) {
                        Text(viewModel.usersCache[album.contributor]?.displayName
                             ?? viewModel.usersCache[album.contributor]?.email
                             ?? album.contributor)
                            .font(.caption).foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
                
                // Action Buttons
                HStack(spacing: 16) {
                    Button(action: {
                        if !albumTracks.isEmpty { 
                            viewModel.playTracks(albumTracks) 
                            onClose()
                        }
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Play Album")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                    .disabled(albumTracks.isEmpty)
                    
                    Button(action: {
                        if !albumTracks.isEmpty { viewModel.addTracksToPlaylist(albumTracks) }
                    }) {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("Queue")
                        }
                        .font(.headline)
                        .foregroundColor(.purple)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                    .disabled(albumTracks.isEmpty)
                }
                .padding(.top, 4)
            }
            .padding()
            #endif

            Divider()

            // Track List
            if isLoading {
                Spacer()
                ProgressView("Loading tracks...")
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if albumTracks.isEmpty {
                Spacer()
                Text("This album has no tracks yet.")
                    .foregroundColor(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    ForEach(albumTracks, id: \.id) { track in
                        HStack {
                            Text("\(track.trackNumber)")
                                .font(.caption).foregroundColor(.secondary)
                                .frame(width: 24, alignment: .leading)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title).font(.subheadline).bold().lineLimit(1)
                                Text(track.artist).font(.caption)
                                    .foregroundColor(.secondary).lineLimit(1)
                            }

                            Spacer()

                            Button(action: { 
                                viewModel.playTrack(track) 
                                onClose()
                            }) {
                                Image(systemName: "play.fill")
                                    .foregroundColor(.blue).font(.title3)
                            }.buttonStyle(.plain)

                            Button(action: { withAnimation { viewModel.addToPlaylist(track) } }) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.purple).font(.title3)
                            }.buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture { onTrackSelect(track) }
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
        #if os(macOS)
        .background(Color(NSColor.windowBackgroundColor))
        #else
        .background(Color(.systemBackground))
        #endif
        .task(id: album.id) {
            viewModel.fetchUser(uid: album.contributor)
            await loadTracks()
        }
    }

    private func loadTracks() async {
        defer { isLoading = false }  // Đảm bảo luôn tắt loading dù guard/catch
        guard let albumId = album.id else { return }
        do {
            // ✅ Route qua ViewModel thay vì gọi Service trực tiếp — đúng MVVM
            let tracks = try await viewModel.fetchAlbumTracks(albumId: albumId)
            self.albumTracks = tracks.sorted { $0.trackNumber < $1.trackNumber }
        } catch {
            print("Error loading album tracks: \(error)")
        }
    }
}
