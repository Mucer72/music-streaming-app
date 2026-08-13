//
//  ProfileViewModel.swift
//  PersonalMusicHost
//

import Foundation
import Combine

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var userRecord: UserRecord?
    @Published var totalTracks: Int = 0
    @Published var totalAlbums: Int = 0
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    var targetUID: String? // If nil, use currentUID
    
    init(targetUID: String? = nil) {
        self.targetUID = targetUID
    }
    
    private let dbService = FirebaseDatabaseService.shared
    
    func loadUserProfile() async {
        guard let uid = targetUID ?? FirebaseAuthService.shared.currentUID else {
            self.errorMessage = "Người dùng chưa đăng nhập"
            return
        }
        
        self.isLoading = true
        self.errorMessage = nil
        
        do {
            async let fetchedUser = dbService.fetchUserRecord(uid: uid)
            async let tracksCount = dbService.countUserTracks(uid: uid)
            async let albumsCount = dbService.countUserAlbums(uid: uid)
            
            self.userRecord = try await fetchedUser
            self.totalTracks = try await tracksCount
            self.totalAlbums = try await albumsCount
            
        } catch {
            print("❌ Lỗi khi tải dữ liệu người dùng: \(error.localizedDescription)")
            self.errorMessage = "Không thể tải thông tin. Vui lòng thử lại sau."
        }
        
        self.isLoading = false
    }
}
