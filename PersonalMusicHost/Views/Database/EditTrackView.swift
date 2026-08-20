//
//  EditTrackView.swift
//  PersonalMusicHost
//
//  Sheet form for editing a track's metadata (title, artist, album,
//  track number, release year, genre, visibility, and description).
//  Cross-platform compatible for macOS and iOS.
//

import SwiftUI
import PhotosUI

struct EditTrackView: View {
    @Binding var isPresented: Bool
    @State private var editedTrack: TrackRecord
    @EnvironmentObject var databaseViewModel: DatabaseViewModel
    var onSave: (TrackRecord) -> Void

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingCover = false
    @State private var uploadErrorMessage: String?

    init(track: TrackRecord, isPresented: Binding<Bool>, onSave: @escaping (TrackRecord) -> Void) {
        self._editedTrack = State(initialValue: track)
        self._isPresented = isPresented
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // ─── COVER ART SECTION ─────────────────────────────
                    HStack(spacing: 16) {
                        ZStack {
                            if let coverID = editedTrack.coverDriveID, !coverID.isEmpty {
                                SecureDriveImage(fileID: coverID)
                                    .frame(width: 64, height: 64)
                                    .cornerRadius(10)
                                    .clipped()
                            } else {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.secondary.opacity(0.15))
                                    .frame(width: 64, height: 64)
                                    .overlay(
                                        Image(systemName: "music.note")
                                            .font(.title2)
                                            .foregroundColor(.secondary)
                                    )
                            }

                            if isUploadingCover {
                                ProgressView()
                                    .controlSize(.regular)
                                    .frame(width: 64, height: 64)
                                    .background(Color.black.opacity(0.4).cornerRadius(10))
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Ảnh bìa bài hát")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            HStack(spacing: 8) {
                                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                    Label("Chọn ảnh", systemImage: "photo.on.rectangle")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .disabled(isUploadingCover)

                                #if os(macOS)
                                Button(action: selectLocalImage) {
                                    Label("Tập tin...", systemImage: "folder")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .disabled(isUploadingCover)
                                #endif
                            }

                            if let error = uploadErrorMessage {
                                Text(error)
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .padding(.bottom, 4)

                    // ─── METADATA FIELDS ───────────────────────────────
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tên bài hát").font(.caption).foregroundColor(.secondary)
                            TextField("Tiêu đề bài hát", text: $editedTrack.title)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Nghệ sĩ").font(.caption).foregroundColor(.secondary)
                            TextField("Tên nghệ sĩ", text: $editedTrack.artist)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Album").font(.caption).foregroundColor(.secondary)
                            TextField("Tên album (nếu có)", text: Binding(
                                get: { editedTrack.albumId ?? "" },
                                set: { editedTrack.albumId = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Số thứ tự (#)").font(.caption).foregroundColor(.secondary)
                                TextField("Track #", value: $editedTrack.trackNumber, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 100)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Năm phát hành").font(.caption).foregroundColor(.secondary)
                                TextField("Năm", value: $editedTrack.releaseYear, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 120)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Thể loại").font(.caption).foregroundColor(.secondary)
                            Picker("Thể loại", selection: Binding(
                                get: { editedTrack.genreId ?? "" },
                                set: { editedTrack.genreId = $0.isEmpty ? nil : $0 }
                            )) {
                                Text("Chưa phân loại").tag("")
                                ForEach(databaseViewModel.availableGenres) { genre in
                                    Text(genre.name).tag(genre.id ?? "")
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Toggle(isOn: Binding(
                            get: { editedTrack.isPublic ?? false },
                            set: { editedTrack.isPublic = $0 }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Công khai (Public)")
                                    .font(.subheadline)
                                Text("Cho phép người dùng khác xem và nghe bài hát này")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        #if os(macOS)
                        .toggleStyle(.checkbox)
                        #endif
                        .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Mô tả / Ghi chú (Tùy chọn)").font(.caption).foregroundColor(.secondary)
                            TextField("Mô tả bài hát", text: Binding(
                                get: { editedTrack.description ?? "" },
                                set: { editedTrack.description = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Chỉnh sửa bài hát")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        onSave(editedTrack)
                        isPresented = false
                    }
                    .fontWeight(.bold)
                }
            }
            .onChange(of: selectedPhotoItem) { newItem in
                handlePhotoSelection(newItem)
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, maxWidth: 560, minHeight: 520, maxHeight: 580)
        #endif
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        Task {
            isUploadingCover = true
            uploadErrorMessage = nil
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    let newID = try await databaseViewModel.updateCoverImage(imageData: data)
                    await MainActor.run {
                        self.editedTrack.coverDriveID = newID
                    }
                }
            } catch {
                await MainActor.run {
                    self.uploadErrorMessage = "Lỗi tải ảnh: \(error.localizedDescription)"
                }
            }
            await MainActor.run {
                isUploadingCover = false
            }
        }
    }

    #if os(macOS)
    private func selectLocalImage() {
        if let url = LocalFileService().selectImageFile() {
            Task {
                isUploadingCover = true
                uploadErrorMessage = nil
                do {
                    let newID = try await databaseViewModel.updateCoverImage(imageURL: url)
                    await MainActor.run { self.editedTrack.coverDriveID = newID }
                } catch {
                    await MainActor.run { self.uploadErrorMessage = "Lỗi tải ảnh: \(error.localizedDescription)" }
                }
                await MainActor.run { isUploadingCover = false }
            }
        }
    }
    #endif
}
