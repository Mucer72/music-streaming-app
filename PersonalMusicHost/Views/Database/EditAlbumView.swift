//
//  EditAlbumView.swift
//  PersonalMusicHost
//
//  Sheet form for editing an album's metadata (title, artist, year,
//  genre, cover art, visibility, and description).
//

import SwiftUI

struct EditAlbumView: View {
    @Binding var isPresented: Bool
    @State private var editedAlbum: AlbumRecord
    @EnvironmentObject var databaseViewModel: DatabaseViewModel
    var onSave: (AlbumRecord) -> Void

    init(album: AlbumRecord, isPresented: Binding<Bool>, onSave: @escaping (AlbumRecord) -> Void) {
        self._editedAlbum = State(initialValue: album)
        self._isPresented = isPresented
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Album").font(.headline)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            .padding()

            VStack(alignment: .leading, spacing: 15) {
                Text("Album Information").font(.caption).bold()

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
                                        await MainActor.run { self.editedAlbum.coverDriveID = newID }
                                    } catch {
                                        print("Lỗi upload ảnh bìa Album: \(error.localizedDescription)")
                                    }
                                }
                            }
                        }
                    }
                }

                TextField("Album Name", text: $editedAlbum.title)
                    .textFieldStyle(.roundedBorder)

                TextField("Artist", text: $editedAlbum.artist)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("Release Year:")
                    TextField("Năm", value: $editedAlbum.releaseYear, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 100)
                    Spacer()
                }

                HStack {
                    Text("Genre:")
                    Picker("Genre", selection: Binding(
                        get: { editedAlbum.genreId ?? "" },
                        set: { editedAlbum.genreId = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Uncategorized").tag("")
                        ForEach(databaseViewModel.availableGenres) { genre in
                            Text(genre.name).tag(genre.id ?? "")
                        }
                    }
                    .frame(width: 200)

                    Spacer()

                    Toggle("Public", isOn: Binding(
                        get: { editedAlbum.isPublic ?? false },
                        set: { editedAlbum.isPublic = $0 }
                    )).toggleStyle(.checkbox)
                }

                TextField("Album Description (Optional)", text: Binding(
                    get: { editedAlbum.description ?? "" },
                    set: { editedAlbum.description = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Save Changes") {
                    onSave(editedAlbum)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 550, height: 450)
    }
}
