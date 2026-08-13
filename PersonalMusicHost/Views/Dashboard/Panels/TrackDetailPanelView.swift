//
//  TrackDetailPanelView.swift
//  PersonalMusicHost
//
//  Right-panel detail view for a selected track. Displays cover art,
//  metadata, and action buttons (add to queue / like / add to playlist).
//

import SwiftUI

struct TrackDetailPanelView: View {
    let track: TrackRecord
    @ObservedObject var viewModel: PlayerViewModel
    let onBack: () -> Void
    let onClose: () -> Void
    let onAdd: () -> Void
    let onAddToPlaylist: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header with Back and Close Button
            HStack {
                PanelBackButton(action: onBack)
                Spacer()
                PanelCloseButton(action: onClose)
            }
            .padding()

            ScrollView {
                VStack(spacing: 24) {
                    ZStack(alignment: .center) {
                        SecureDriveImage(fileID: track.coverDriveID)
                            .frame(width: 250, height: 250)
                            .cornerRadius(12)
                            .shadow(radius: 8)
                        
                        Button(action: {
                            withAnimation {
                                viewModel.playTrack(track)
                            }
                            onClose()
                        }) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 64))
                                .foregroundColor(.blue)
                                .background(Color.white.clipShape(Circle()))
                                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 16)

                    VStack(spacing: 8) {
                        Text(track.title)
                            .font(.largeTitle).bold().multilineTextAlignment(.center)
                        Text(track.artist)
                            .font(.title3).foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        if let albumId = track.albumId,
                           let album = viewModel.albums.first(where: { $0.id == albumId }) {
                            detailRow(icon: "opticaldisc", label: "Album", value: album.title)
                        }
                        if let releaseYear = track.releaseYear {
                            detailRow(icon: "calendar", label: "Release Year", value: "\(releaseYear)")
                        }
                        if let genreId = track.genreId,
                           let genre = viewModel.availableGenres.first(where: { $0.id == genreId }) {
                            detailRow(icon: "music.note", label: "Genre", value: genre.name)
                        }
                        detailRow(icon: "headphones", label: "Streams", value: "\(track.streamCount)")

                        if let description = track.description, !description.isEmpty {
                            Text(description)
                                .font(.body).foregroundColor(.secondary).italic()
                                .padding(.top, 8)
                        }

                        HStack {
                            Image(systemName: "person.circle.fill").foregroundColor(.secondary)
                            Text("Contributor:").foregroundColor(.secondary)
                            NavigationLink(value: AppRoute.userProfile(track.contributor)) {
                                Text(viewModel.usersCache[track.contributor]?.displayName
                                     ?? viewModel.usersCache[track.contributor]?.email
                                     ?? track.contributor)
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    HStack(spacing: 12) {
                        // Like toggle
                        let isLiked = track.id != nil && viewModel.likedTrackIds.contains(track.id!)
                        Button(action: { viewModel.toggleLike(for: track) }) {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .font(.title2)
                                .foregroundColor(isLiked ? .pink : .primary)
                                .frame(width: 50, height: 50)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)

                        // Add to queue
                        Button(action: onAdd) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add to Queue")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)

                        // Add to playlist
                        Button(action: onAddToPlaylist) {
                            Image(systemName: "text.badge.plus")
                                .font(.title2)
                                .foregroundColor(.purple)
                                .frame(width: 50, height: 50)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            viewModel.fetchUser(uid: track.contributor)
        }
    }

    private func detailRow(icon: String, label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundColor(.secondary).frame(width: 20)
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).bold()
        }
    }
}
