//
//  EditTrackView.swift
//  PersonalMusicHost
//
//  Sheet form for editing a track's metadata (title, artist, album,
//  track number, release year, genre, visibility, and description).
//

import SwiftUI

struct EditTrackView: View {
    @Binding var isPresented: Bool
    @State private var editedTrack: TrackRecord
    @EnvironmentObject var databaseViewModel: DatabaseViewModel
    var onSave: (TrackRecord) -> Void

    init(track: TrackRecord, isPresented: Binding<Bool>, onSave: @escaping (TrackRecord) -> Void) {
        self._editedTrack = State(initialValue: track)
        self._isPresented = isPresented
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Metadata").font(.headline)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            .padding()

            VStack(alignment: .leading, spacing: 15) {
                Text("Track Information").font(.caption).bold()

                Section(header: Text("Cover Art")) {
                    HStack {
                        Image(systemName: editedTrack.coverDriveID != nil ? "photo.fill" : "photo")
                            .resizable().frame(width: 50, height: 50)
                            .foregroundColor(.secondary)

                        Button("Change Cover Art") {
                            if let url = LocalFileService().selectImageFile() {
                                Task {
                                    do {
                                        let newID = try await databaseViewModel.updateCoverImage(imageURL: url)
                                        await MainActor.run { self.editedTrack.coverDriveID = newID }
                                    } catch {
                                        print("Lỗi upload: \(error.localizedDescription)")
                                    }
                                }
                            }
                        }
                    }
                }

                TextField("Track Title", text: $editedTrack.title)
                    .textFieldStyle(.roundedBorder)

                TextField("Artist", text: $editedTrack.artist)
                    .textFieldStyle(.roundedBorder)

                TextField("Album Name", text: Binding(
                    get: { editedTrack.albumId ?? "" },
                    set: { editedTrack.albumId = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)

                HStack {
                    Text("Track #:")
                    TextField("Số", value: $editedTrack.trackNumber, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 60)

                    Text("Release Year:").padding(.leading, 10)
                    TextField("Năm", value: $editedTrack.releaseYear, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 80)

                    Spacer()
                }

                HStack {
                    Text("Genre:")
                    Picker("Genre", selection: Binding(
                        get: { editedTrack.genreId ?? "" },
                        set: { editedTrack.genreId = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Uncategorized").tag("")
                        ForEach(databaseViewModel.availableGenres) { genre in
                            Text(genre.name).tag(genre.id ?? "")
                        }
                    }
                    .frame(width: 200)

                    Spacer()

                    Toggle("Public", isOn: Binding(
                        get: { editedTrack.isPublic ?? false },
                        set: { editedTrack.isPublic = $0 }
                    )).toggleStyle(.checkbox)
                }

                TextField("Track Description (Optional)", text: Binding(
                    get: { editedTrack.description ?? "" },
                    set: { editedTrack.description = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Save Changes") {
                    onSave(editedTrack)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 550, height: 480)
    }
}
