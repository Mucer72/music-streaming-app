//
//  DatabseViewModel.swift
//  PersonalMusicHost
//
//  Created by TwentyMikeyOne on 28/6/26.
//

import Foundation
import SwiftUI
import FirebaseFirestore
import Combine // Bắt buộc để dùng Debounce

enum ManagementMode: String, CaseIterable {
    case track
    case album
    case playlist
}

@MainActor
class DatabaseViewModel: ObservableObject {
    @Published var tracks: [TrackRecord] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // Tìm kiếm & Sắp xếp
    @Published var searchText: String = ""
    @Published var sortOption: String = "albumId"
    
    @Published var availableGenres: [GenreRecord] = []
    
    @Published var selectedTrackIDs = Set<String>()
    
    // Quản lý Album & Playlist
    @Published var albums: [AlbumRecord] = []
    @Published var playlists: [PlaylistRecord] = []
    @Published var managementMode: ManagementMode = .track
    @Published var selectedAlbumIDs = Set<String>()
    @Published var selectedPlaylistIDs = Set<String>()
    
    private var lastDocument: DocumentSnapshot?
    @Published var hasMoreData: Bool = true
    @Published var isFetchingMore: Bool = false
    
    private let dbService = FirebaseDatabaseService.shared
    private let driveService = GoogleDriveService.shared
    private var cancellables = Set<AnyCancellable>()
    
    /// Guard: chỉ fetch lần đầu khi vào màn hình. Sau đó, refresh do pull-to-refresh.
    private(set) var hasLoadedInitially = false
    
    /// Genres cache: hiếm khi thay đổi, chỉ fetch 1 lần trong đời sống của DatabaseViewModel.
    private var cachedGenres: [GenreRecord]?
    
    init() {
        // Lắng nghe sự thay đổi của Search và Sort để tự động load lại data
        $searchText
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadInitialData()
            }
            .store(in: &cancellables)
        
        $sortOption
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadInitialData()
            }
            .store(in: &cancellables)
        
        $managementMode
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadInitialData()
            }
            .store(in: &cancellables)
    }
    
    // (Bỏ biến filteredTracks cũ vì giờ ta dùng danh sách gốc từ Server)
    
    func loadInitialData() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        lastDocument = nil
        hasMoreData = true
        selectedTrackIDs.removeAll()
        selectedAlbumIDs.removeAll()
        selectedPlaylistIDs.removeAll()
        
        Task {
            do {
                if managementMode == .album {
                    self.albums = try await dbService.fetchAllAlbums()
                    self.hasMoreData = false
                } else if managementMode == .playlist {
                    if let uid = FirebaseAuthService.shared.currentUID {
                        self.playlists = try await dbService.fetchUserPlaylists(uid: uid)
                    }
                    self.hasMoreData = false
                } else {
                    let result = try await dbService.fetchPaginatedTracks(
                        limit: 50,
                        after: nil,
                        sortBy: sortOption,
                        searchText: searchText.trimmingCharacters(in: .whitespaces)
                    )
                    
                    // Sử dụng genres từ cache nếu có; chỉ fetch khi chưa có cache.
                    if cachedGenres == nil {
                        let genres = try await dbService.fetchGenres()
                        self.cachedGenres = genres
                        self.availableGenres = genres
                        print("🌐 [Genres] Fetched từ Firestore.")
                    } else {
                        self.availableGenres = cachedGenres!
                        print("⚡️ [Genres] Cache HIT — bỏ qua fetch.")
                    }
                    
                    self.tracks = result.tracks
                    self.lastDocument = result.lastDoc
                    self.hasMoreData = !result.tracks.isEmpty
                }
                self.hasLoadedInitially = true
            } catch {
                self.errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
    
    /// Gọi bởi pull-to-refresh UI. Buộc reset và fetch lại toàn bộ data hiện tại.
    func refreshData() async {
        hasLoadedInitially = false
        // Reset genre cache để cũng refresh genres mới nhất
        cachedGenres = nil
        loadInitialData()
    }
    
    func loadMoreData() {
        guard !isFetchingMore && hasMoreData && managementMode == .track else { return }
        isFetchingMore = true
        
        Task {
            do {
                let result = try await dbService.fetchPaginatedTracks(
                    limit: 50,
                    after: lastDocument,
                    sortBy: sortOption,
                    searchText: searchText.trimmingCharacters(in: .whitespaces)
                )
                if result.tracks.isEmpty {
                    self.hasMoreData = false
                } else {
                    self.tracks.append(contentsOf: result.tracks)
                    self.lastDocument = result.lastDoc
                }
            } catch {
                print("Lỗi tải thêm dữ liệu: \(error.localizedDescription)")
            }
            isFetchingMore = false
        }
    }
    
    func saveChanges(for track: TrackRecord) {
        Task {
            do {
                try await dbService.updateTrack(track)
                if let index = tracks.firstIndex(where: { $0.id == track.id }) {
                    tracks[index] = track
                }
            } catch {
                self.errorMessage = "Lỗi cập nhật: \(error.localizedDescription)"
            }
        }
    }
    
    func saveAlbumChanges(for album: AlbumRecord) {
        Task {
            do {
                try await dbService.updateAlbum(album)
                if let index = albums.firstIndex(where: { $0.id == album.id }) {
                    albums[index] = album
                }
                
                // Đồng bộ isPublic cho tất cả bài hát thuộc album này
                if let albumId = album.id, let isPublic = album.isPublic {
                    let albumTracks = try await dbService.fetchTracks(forAlbumId: albumId)
                    for var track in albumTracks {
                        track.isPublic = isPublic
                        try await dbService.updateTrack(track)
                    }
                }
            } catch {
                self.errorMessage = "Lỗi cập nhật Album: \(error.localizedDescription)"
            }
        }
    }
    
    func deleteSelectedPlaylists() {
        let playlistsToDelete = playlists.filter { selectedPlaylistIDs.contains($0.id ?? "") }
        guard !playlistsToDelete.isEmpty else { return }
        
        let ids = playlistsToDelete.compactMap { $0.id }
        Task {
            isLoading = true
            do {
                try await dbService.deletePlaylists(ids: ids)
                playlists.removeAll { ids.contains($0.id ?? "") }
                selectedPlaylistIDs.removeAll()
            } catch {
                self.errorMessage = "Lỗi xoá Playlist: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
    
    func savePlaylistChanges(for playlist: PlaylistRecord) {
        Task {
            do {
                try await dbService.updatePlaylist(playlist)
                if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
                    playlists[index] = playlist
                }
                
                // Đồng bộ isPublic cho tất cả bài hát trong playlist nếu playlist chuyển sang public
                // Nhưng theo logic hiện tại, playlist public -> không tự public bài hát. 
                // Playlist private -> các bài vẫn giữ nguyên trạng thái.
                // Do đó ta không cần tự động updateTracks như album.
            } catch {
                self.errorMessage = "Lỗi cập nhật Playlist: \(error.localizedDescription)"
            }
        }
    }
    
    func deleteSelectedTracks() {
        let tracksToDelete = tracks.filter { selectedTrackIDs.contains($0.id ?? "") }
        guard !tracksToDelete.isEmpty else { return }
        
        Task {
            isLoading = true
            for track in tracksToDelete {
                await executeDelete(for: track)
            }
            tracks.removeAll { selectedTrackIDs.contains($0.id ?? "") }
            selectedTrackIDs.removeAll()
            isLoading = false
        }
    }
    
    func deleteSingleTrack(_ track: TrackRecord) {
        Task {
            isLoading = true
            await executeDelete(for: track)
            tracks.removeAll { $0.id == track.id }
            selectedTrackIDs.remove(track.id ?? "")
            isLoading = false
        }
    }
    
    private func executeDelete(for track: TrackRecord) async {
        guard let trackId = track.id else { return }
        
        do {
            print("🗑️ Bắt đầu luồng xoá toàn diện cho bài: \(track.title)")
            
            // 1. XOÁ FILE AAC TRÊN DRIVE (NẾU CÓ)
            if let aacID = track.googleDriveAACID, !aacID.isEmpty {
                print("⏳ Đang gỡ bỏ file AAC khỏi Google Drive (ID: \(aacID))...")
                do {
                    try await driveService.deleteFile(fileID: aacID)
                    print("✅ Đã xoá file AAC trên Drive thành công.")
                } catch {
                    // Nếu lỗi do file không tồn tại trên Drive, vẫn cho phép chạy tiếp để dọn DB
                    print("⚠️ Cảnh báo xoá file AAC trên Drive: \(error.localizedDescription)")
                }
            }
            
            // 2. XOÁ FILE ALAC TRÊN DRIVE (NẾU CÓ)
            if let alacID = track.googleDriveALACID, !alacID.isEmpty {
                print("⏳ Đang gỡ bỏ file ALAC khỏi Google Drive (ID: \(alacID))...")
                do {
                    try await driveService.deleteFile(fileID: alacID)
                    print("✅ Đã xoá file ALAC trên Drive thành công.")
                } catch {
                    print("⚠️ Cảnh báo xoá file ALAC trên Drive: \(error.localizedDescription)")
                }
            }
            
            // 3. CUỐI CÙNG MỚI XOÁ METADATA TRÊN FIRESTORE
            // Đảm bảo không làm mất liên kết ID trên Drive trước khi file thực sự được xử lý
            print("⏳ Đang dọn dẹp Metadata trên Firestore...")
            try await dbService.deleteTrack(trackId: trackId)
            print("🎉 Đã xoá hoàn tất bài hát '\(track.title)' khỏi hệ thống song phương!")
            
        } catch {
            // Chỉ ghi nhận lỗi hệ thống nghiêm trọng (như mất mạng, Firestore lỗi quyền)
            self.errorMessage = "Lỗi nghiêm trọng khi xoá bài hát: \(error.localizedDescription)"
            print("❌ LỖI TRONG TIẾN TRÌNH XOÁ: \(error)")
        }
    }
    
    func updateCoverImage(imageData: Data, mimeType: String = "image/jpeg") async throws -> String {
        let rootID = try await driveService.getOrCreateFolder(name: AppEnvironment.driveRootFolderName)
        let coversFolderID = try await driveService.getOrCreateFolder(name: "covers", parentID: rootID)
        let newCoverID = try await driveService.uploadImageData(imageData: imageData, mimeType: mimeType, folderID: coversFolderID)
        try await driveService.setPublicPermission(fileID: newCoverID)
        return newCoverID
    }
    
    func updateCoverImage(imageURL: URL) async throws -> String {
        let rootID = try await driveService.getOrCreateFolder(name: AppEnvironment.driveRootFolderName)
        let coversFolderID = try await driveService.getOrCreateFolder(name: "covers", parentID: rootID)
        let newCoverID = try await driveService.uploadImageFile(fileURL: imageURL, folderID: coversFolderID)
        try await driveService.setPublicPermission(fileID: newCoverID)
        return newCoverID
    }
    
    // --- QUẢN LÝ ALBUM ---
    func deleteSelectedAlbums() {
        let idsToDelete = selectedAlbumIDs
        
        Task {
            isLoading = true
            do {
                for albumId in idsToDelete {
                    // 1. Quét tìm tất cả Track thuộc Album
                    let albumTracks = try await dbService.fetchTracks(forAlbumId: albumId)
                    
                    // 2. Xoá file AAC/ALAC của các Track trên Drive & Xoá Track trên Firestore
                    for track in albumTracks {
                        await executeDelete(for: track)
                    }
                    
                    // 3. Xoá Cover Image trên Drive
                    if let album = albums.first(where: { $0.id == albumId }) {
                        if !album.coverDriveID.isEmpty {
                            try? await driveService.deleteFile(fileID: album.coverDriveID)
                        }
                    }
                    
                    // 4. Xoá Album trên Firestore
                    try await dbService.deleteAlbum(albumId: albumId)
                }
                
                self.albums.removeAll { idsToDelete.contains($0.id ?? "") }
                self.selectedAlbumIDs.removeAll()
            } catch {
                self.errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
