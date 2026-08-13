//
//  AlbumGlobalInfoView.swift
//  PersonalMusicHost
//
//  Global album metadata editor shown in Album mode. Lets the user set
//  cover, name, artist, year, genre, and description for the whole album,
//  then push values down to all queued tracks at once.
//

import SwiftUI

struct AlbumGlobalInfoView: View {
    @EnvironmentObject var viewModel: PipelineViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // Cover art preview
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .cornerRadius(8)

                if let url = viewModel.coverImageURL,
                   let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable().scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle).foregroundColor(.gray)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Album Global Info").font(.headline)

                HStack {
                    VStack(alignment: .leading) {
                        Text("Album Name").font(.caption).foregroundColor(.secondary)
                        TextField("Shared Album Name", text: $viewModel.globalAlbumName)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading) {
                        Text("Artist").font(.caption).foregroundColor(.secondary)
                        TextField("Shared Artist Name", text: $viewModel.globalArtistName)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading) {
                        Text("Release Year").font(.caption).foregroundColor(.secondary)
                        TextField("Year", text: $viewModel.globalReleaseYear)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading) {
                        Text("Genre").font(.caption).foregroundColor(.secondary)
                        Picker("Genre", selection: $viewModel.globalGenreId) {
                            Text("Select Genre").tag("")
                            ForEach(viewModel.availableGenres) { genre in
                                Text(genre.name).tag(genre.id ?? "")
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 150)
                    }
                }

                VStack(alignment: .leading) {
                    Text("Album Description (Optional)").font(.caption).foregroundColor(.secondary)
                    TextField("Write something about this album...", text: $viewModel.globalDescription)
                        .textFieldStyle(.roundedBorder)
                }

                Button(action: {
                    withAnimation { viewModel.applyGlobalAlbumInfo() }
                }) {
                    Text("Apply to all tracks below").font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}
