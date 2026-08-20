//
//  EditPlaylistView.swift
//  PersonalMusicHost
//
//  Sheet form for editing a playlist's metadata (title, cover art,
//  public/private toggle, and description).
//  Cross-platform compatible for macOS and iOS.
//

import SwiftUI
import PhotosUI

struct EditPlaylistView: View {
    @Binding var isPresented: Bool
    @State private var editedPlaylist: PlaylistRecord
    @EnvironmentObject var databaseViewModel: DatabaseViewModel
    var onSave: (PlaylistRecord) -> Void

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingCover = false
    @State private var uploadErrorMessage: String?

    init(playlist: PlaylistRecord, isPresented: Binding<Bool>, onSave: @escaping (PlaylistRecord) -> Void) {
        self._editedPlaylist = State(initialValue: playlist)
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
                            if let coverID = editedPlaylist.coverDriveID, !coverID.isEmpty {
                                SecureDriveImage(fileID: coverID)
                                    .frame(width: 64, height: 64)
                                    .cornerRadius(10)
                                    .clipped()
                            } else {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.secondary.opacity(0.15))
                                    .frame(width: 64, height: 64)
                                    .overlay(
                                        Image(systemName: "music.note.list")
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
                            Text("Ảnh bìa Playlist")
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
                            Text("Tên Playlist").font(.caption).foregroundColor(.secondary)
                            TextField("Tiêu đề danh sách phát", text: $editedPlaylist.title)
                                .textFieldStyle(.roundedBorder)
                        }

                        Toggle(isOn: $editedPlaylist.isPublic) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Công khai (Public)")
                                    .font(.subheadline)
                                Text("Cho phép mọi người tìm kiếm và nghe playlist này")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        #if os(macOS)
                        .toggleStyle(.checkbox)
                        #endif
                        .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Mô tả Playlist (Tùy chọn)").font(.caption).foregroundColor(.secondary)
                            TextField("Mô tả tóm tắt", text: Binding(
                                get: { editedPlaylist.description ?? "" },
                                set: { editedPlaylist.description = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Chỉnh sửa Playlist")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        onSave(editedPlaylist)
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
        .frame(minWidth: 480, maxWidth: 540, minHeight: 400, maxHeight: 460)
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
                        self.editedPlaylist.coverDriveID = newID
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
                    await MainActor.run { self.editedPlaylist.coverDriveID = newID }
                } catch {
                    await MainActor.run { self.uploadErrorMessage = "Lỗi tải ảnh: \(error.localizedDescription)" }
                }
                await MainActor.run { isUploadingCover = false }
            }
        }
    }
    #endif
}
