//
//  SpotifyModels.swift
//  PersonalMusicHost
//
//  Data models for the Spotify Import Pipeline.
//  - SpotifyTrackMetadata: enriched track info fetched via Spotify oEmbed
//  - AudioCandidate:       candidate from Piped/alternative search API
//  - SpotifyImportState:   state machine enum for the import screen
//

import Foundation

// MARK: - Spotify Metadata

/// Siêu dữ liệu track được trích xuất từ Spotify oEmbed API.
/// `durationSeconds` được tính từ file audio đã tải về (AVAsset), không phải từ Spotify.
struct SpotifyTrackMetadata {
    let spotifyTrackID: String    // ID dạng "4iV5W9uYEdYUVa79Axb7Rh"
    let title: String
    let artist: String
    let album: String
    let coverURL: URL?
    let coverImageData: Data?     // Dữ liệu ảnh bìa đã tải sẵn về bộ nhớ
    let spotifyGenreHint: String? // Gợi ý genre từ Spotify (nếu có, dùng để auto-match)
    let isrc: String?             // Mã ISRC nếu có (optional)
}

// MARK: - Search Candidate

/// Kết quả tìm kiếm từ một nguồn audio thay thế (Piped, SoundCloud,…).
struct AudioCandidate: Identifiable {
    let id = UUID()
    let videoId: String                     // ID video/track trên nguồn đó
    let isYTMusic: Bool
    let title: String
    let uploaderName: String
    let durationSeconds: Int
    let streamURL: URL?                     // Direct audio stream URL (m4a/aac)
    var score: Double = 0.0                 // Điểm tương đồng sau khi scoring
}

// MARK: - Import State Machine

/// Các trạng thái của màn hình Spotify Import.
enum SpotifyImportState: Equatable {
    case idle                               // Chờ người dùng nhập URL
    case fetchingMetadata                   // Đang gọi Spotify oEmbed API
    case searching                          // Đang tìm kiếm trên nguồn thay thế
    case scoring                            // Đang tính điểm và chọn ứng viên tốt nhất
    case downloading                        // Đang tải file audio
    case tagging                            // Đang nhúng metadata vào file
    case readyToUpload                      // File đã sẵn sàng, chờ xác nhận upload
    case uploading                          // Đang upload lên Drive + Firestore
    case completed                          // Hoàn thành
    case failed(String)                     // Thất bại kèm thông điệp lỗi

    static func == (lhs: SpotifyImportState, rhs: SpotifyImportState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.fetchingMetadata, .fetchingMetadata),
             (.searching, .searching), (.scoring, .scoring),
             (.downloading, .downloading), (.tagging, .tagging),
             (.readyToUpload, .readyToUpload), (.uploading, .uploading),
             (.completed, .completed):
            return true
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}
