//
//  PlaylistManagerViewModel.swift
//  PersonalMusicHost
//

import Combine
import Foundation
import FirebaseAuth

@MainActor
class PlaylistManagerViewModel: ObservableObject {
    @Published var userPlaylists: [PlaylistRecord] = []
    @Published var isLoading = false
    
    private let dbService = FirebaseDatabaseService.shared
    
    /// Guard để tránh fetch lại khi Dashboard re-appear mà data chưa thay đổi.
    /// Chỉ được reset sau khi có write operation (tạo/xoá playlist).
    private var hasFetchedOnce = false
    
    /// Fetch danh sách playlist. Bỏ qua nếu đã có data và không có write mới.
    /// Truyền `force: true` để bắt fetch lại (ví dụ: sau khi write).
    func fetchPlaylists(force: Bool = false) async {
        guard let uid = FirebaseAuthService.shared.currentUID ?? Auth.auth().currentUser?.uid else { return }
        
        // Skip nếu đã fetch và không bị ép buộc refresh
        if hasFetchedOnce && !force && !userPlaylists.isEmpty {
            print("⚡️ [Cache HIT] Playlists — bỏ qua fetch, dùng data trong bộ nhớ.")
            return
        }
        
        self.isLoading = true
        do {
            let playlists = try await dbService.fetchUserPlaylists(uid: uid)
            self.userPlaylists = playlists
            self.hasFetchedOnce = true
        } catch {
            print("❌ Lỗi tải danh sách playlist: \(error.localizedDescription)")
        }
        self.isLoading = false
    }
    
    func createNewPlaylistAndAddTrack(title: String, track: TrackRecord) async -> Bool {
        guard let uid = FirebaseAuthService.shared.currentUID ?? Auth.auth().currentUser?.uid else { return false }
        
        self.isLoading = true
        do {
            // Tạo playlist mới
            let newPlaylistId = try await dbService.createPlaylist(title: title, ownerUID: uid)
            
            // Thêm track vào
            try await dbService.addTrackToPlaylist(track: track, playlistId: newPlaylistId)
            
            // Data đã thay đổi → force fetch lại
            await fetchPlaylists(force: true)
            return true
        } catch {
            print("❌ Lỗi tạo playlist: \(error.localizedDescription)")
            self.isLoading = false
            return false
        }
    }
    
    func addTrackToPlaylist(track: TrackRecord, playlist: PlaylistRecord) async -> Bool {
        guard let playlistId = playlist.id else { return false }
        
        self.isLoading = true
        do {
            try await dbService.addTrackToPlaylist(track: track, playlistId: playlistId)
            // Data đã thay đổi → force fetch lại để cập nhật trackIds/cover/isPublic
            await fetchPlaylists(force: true)
            return true
        } catch {
            print("❌ Lỗi thêm track vào playlist: \(error.localizedDescription)")
            self.isLoading = false
            return false
        }
    }
}
