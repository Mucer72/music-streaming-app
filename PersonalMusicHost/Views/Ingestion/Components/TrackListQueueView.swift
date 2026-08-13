//
//  TrackListQueueView.swift
//  PersonalMusicHost
//
//  Inline metadata editor for the tracks queued for ingestion.
//  Uses SwiftUI's Binding List to sync edits directly to the ViewModel.
//

import SwiftUI

struct TrackListQueueView: View {
    @EnvironmentObject var viewModel: PipelineViewModel

    var body: some View {
        VStack(alignment: .leading) {
            Text("Processing Queue & Metadata Editor")
                .font(.headline)
                .padding(.bottom, 5)

            List($viewModel.tracks) { $track in
                HStack(alignment: .top, spacing: 15) {

                    // Track number
                    VStack(alignment: .leading) {
                        Text("#").font(.caption).foregroundColor(.secondary)
                        TextField("0", value: $track.trackNumber, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 40)
                            .multilineTextAlignment(.center)
                    }

                    // Title
                    VStack(alignment: .leading) {
                        Text("Track Title").font(.caption).foregroundColor(.secondary)
                        TextField("Song Name", text: $track.title)
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(maxWidth: .infinity)

                    // Artist
                    VStack(alignment: .leading) {
                        Text("Artist").font(.caption).foregroundColor(.secondary)
                        TextField("Performer", text: $track.artist)
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(maxWidth: .infinity)

                    // Album name (optional)
                    VStack(alignment: .leading) {
                        Text("Album (Optional)").font(.caption).foregroundColor(.secondary)
                        TextField("Album Name", text: $track.albumName)
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(maxWidth: .infinity)

                    // Genre (required)
                    VStack(alignment: .leading) {
                        Text("Genre *").font(.caption).foregroundColor(.secondary)
                        Picker("Genre", selection: Binding(
                            get: { track.genreId ?? "" },
                            set: { track.genreId = $0 }
                        )) {
                            Text("Select Genre").tag("")
                            ForEach(viewModel.availableGenres) { genre in
                                Text(genre.name).tag(genre.id ?? "")
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 120)
                    }

                    // Status indicators
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("Status").font(.caption).foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            HStack(spacing: 2) {
                                if track.localAAC_URL  != nil { Image(systemName: "a.circle.fill").foregroundColor(.blue) }
                                if track.localALAC_URL != nil { Image(systemName: "l.circle.fill").foregroundColor(.purple) }
                            }
                            HStack(spacing: 2) {
                                if track.driveAAC_ID  != nil { Image(systemName: "icloud.fill").foregroundColor(.green) }
                                if track.driveALAC_ID != nil { Image(systemName: "icloud.fill").foregroundColor(.green) }
                            }
                            Text(String(format: "%02d:%02d",
                                        Int(track.duration) / 60,
                                        Int(track.duration) % 60))
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(4)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 6)
                .disabled(viewModel.isProcessing)
            }
            .listStyle(.inset)
            .cornerRadius(8)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}
