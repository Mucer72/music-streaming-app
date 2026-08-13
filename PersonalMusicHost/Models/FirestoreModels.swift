//
//  FirestoreModels.swift
//  PersonalMusicHost
//
//  Created by TwentyMikeyOne on 27/6/26.
//

import Foundation
import FirebaseFirestore

// 1. Model cho Album
struct AlbumRecord: Identifiable, Codable {
    @DocumentID var id: String? // Tự động lấy Document ID của Firestore
    var title: String
    var artist: String
    var releaseYear: Int
    var description: String?
    var totalTracks: Int
    var coverDriveID: String
    var genreId: String?
    var contributor: String // uid của người upload
    var isPublic: Bool? = false // Xác định public/private
    @ServerTimestamp var createdAt: Timestamp? // Tự động lấy giờ server
}

// 2. Model cho Bài hát (Track)
struct TrackRecord: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String
    var artist: String
    var duration: Double
    var albumId: String?
    var trackNumber: Int
    var releaseYear: Int?
    var description: String?
    var streamCount: Int = 0
    var coverDriveID: String?
    var genreId: String?
    var contributor: String
    var isPublic: Bool? = false
    var googleDriveALACID: String?
    var googleDriveAACID: String?
    @ServerTimestamp var createdAt: Timestamp?
}

// 3. Model cho User
struct UserRecord: Identifiable, Codable {
    @DocumentID var id: String?
    var uid: String
    var email: String
    var displayName: String?
    var photoURL: String?
    var respectCount: Int? = 0 // Tổng lượt thích nhận được
    @ServerTimestamp var createdAt: Timestamp?
}

// 4. Model cho Thể loại (Genre)
struct GenreRecord: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var order: Int? // Để sắp xếp thứ tự hiển thị
}

// 5. Model cho Like
enum LikeItemType: String, Codable {
    case track
}

struct LikeRecord: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var trackId: String
    var itemType: LikeItemType = .track
    var contributorId: String
    @ServerTimestamp var createdAt: Timestamp?
}

// 6. Model cho Playlist
enum PlaylistType: String, Codable {
    case custom
    case systemLiked
    case systemRecommended
}

struct PlaylistRecord: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String
    var description: String?
    var ownerUID: String
    var trackIds: [String]
    var isPublic: Bool = false
    var coverDriveID: String?
    var type: PlaylistType = .custom
    @ServerTimestamp var createdAt: Timestamp?
}

