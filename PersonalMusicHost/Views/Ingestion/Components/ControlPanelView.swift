//
//  ControlPanelView.swift
//  PersonalMusicHost
//
//  Ingestion control panel: mode picker (single/album), file selection,
//  cover art picker, format toggles (AAC/ALAC), and output configuration.
//

import SwiftUI

struct ControlPanelView: View {
    @EnvironmentObject var viewModel: PipelineViewModel

    var body: some View {
        VStack(spacing: 15) {
            // Mode picker
            Picker("Import mode:", selection: $viewModel.isAlbumMode) {
                Text("Single Tracks").tag(false)
                Text("Album (Folder)").tag(true)
            }
            .pickerStyle(.segmented)

            HStack {
                // File / folder selection
                Button(action: { Task { await viewModel.selectFiles() } }) {
                    Image(systemName: viewModel.isAlbumMode ? "folder.fill" : "music.note.list")
                    Text(viewModel.isAlbumMode ? "Select Album Folder" : "Add Music Files (+)")
                }
                .disabled(viewModel.isProcessing)

                // Cover art selection
                Button(action: { Task { viewModel.selectCoverImage() } }) {
                    Image(systemName: "photo")
                    Text(viewModel.coverImageURL == nil ? "Attach Cover Art" : "Cover Selected")
                        .foregroundColor(viewModel.coverImageURL == nil ? .primary : .green)
                }
                .disabled(viewModel.isProcessing)

                if let url = viewModel.coverImageURL,
                   let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable().scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Spacer()

                Text("Format:")
                Toggle("AAC", isOn: $viewModel.isAACSelected).toggleStyle(.checkbox)
                Toggle("ALAC", isOn: $viewModel.isALACSelected).toggleStyle(.checkbox)
            }

            Divider()

            // Output configuration
            HStack {
                Text("Output:")
                Spacer()
                Toggle("Save locally", isOn: $viewModel.saveToLocal).toggleStyle(.checkbox)
                Toggle("Upload to Firebase", isOn: $viewModel.uploadToDrive).toggleStyle(.checkbox)
                Toggle("Public on homepage", isOn: $viewModel.isPublic)
                    .toggleStyle(.checkbox)
                    .disabled(!viewModel.uploadToDrive)
            }

            if viewModel.saveToLocal {
                HStack {
                    Image(systemName: "folder.fill").foregroundColor(.orange)
                    Text(viewModel.outputDirectory?.lastPathComponent ?? "Workspace not set")
                    Spacer()
                    Button("Select Folder") { viewModel.selectOutputDirectory() }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}
