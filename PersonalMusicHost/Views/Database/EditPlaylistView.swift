//
//  EditPlaylistView.swift
//  PersonalMusicHost
//
//  Sheet form for editing a playlist's metadata (title, cover art,
//  public/private toggle, and description).
//

import SwiftUI

struct EditPlaylistView: View {
    @Binding var isPresented: Bool
    @State private var editedPlaylist: PlaylistRecord
    @EnvironmentObject var databaseViewModel: DatabaseViewModel
    var onSave: (PlaylistRecord) -> Void

    init(playlist: PlaylistRecord, isPresented: Binding<Bool>, onSave: @escaping (PlaylistRecord) -> Void) {
        self._editedPlaylist = State(initialValue: playlist)
        self._isPresented = isPresented
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Playlist").font(.headline)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            .padding()

            VStack(alignment: .leading, spacing: 15) {
                Text("Playlist Information").font(.caption).bold()

                Section(header: Text("Cover Art")) {
                    HStack {
                        Image(systemName: "photo.fill")
                            .resizable().frame(width: 50, height: 50)
                            .foregroundColor(.secondary)

                        Button("Change Cover Art") {
                            if let url = LocalFileService().selectImageFile() {
                                Task {
                                    do {
                                        let newID = try await databaseViewModel.updateCoverImage(imageURL: url)
                                        await MainActor.run { self.editedPlaylist.coverDriveID = newID }
                                    } catch {
                                        print("Lỗi upload ảnh bìa Playlist: \(error.localizedDescription)")
                                    }
                                }
                            }
                        }
                    }
                }

                TextField("Playlist Name", text: $editedPlaylist.title)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Toggle("Public", isOn: $editedPlaylist.isPublic)
                        .toggleStyle(.checkbox)
                    Spacer()
                }

                TextField("Playlist Description (Optional)", text: Binding(
                    get: { editedPlaylist.description ?? "" },
                    set: { editedPlaylist.description = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Save Changes") {
                    onSave(editedPlaylist)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }
}
