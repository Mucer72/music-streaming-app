//
//  FirebaseDatabaseService.swift
//  PersonalMusicHost
//
//  Created by TwentyMikeyOne on 27/6/26.
//

import FirebaseFirestore
import Foundation
import FirebaseAuth

@MainActor
class FirebaseDatabaseService {
    static let shared = FirebaseDatabaseService()
    private let db = Firestore.firestore()

    // Hàm lưu bài hát lên Firestore
    func saveTrack(_ track: TrackRecord) async throws {
        // Tạo một Document mới với ID tự sinh trong collection "tracks"
        let docRef = db.collection("tracks").document()

        // Dùng thư viện FirestoreSwift để tự động mã hoá (encode) struct thành JSON
        try docRef.setData(from: track)

        print(
            "✅ Đã lưu Metadata lên Firestore. Document ID: \(docRef.documentID)"
        )
    }

    // 1. Tải toàn bộ danh sách bài hát
    func fetchAllTracks() async throws -> [TrackRecord] {
        // Giả sử collection của bạn tên là "tracks"
        let snapshot = try await db.collection("tracks")
            .order(by: "albumId")
            .order(by: "trackNumber")
            .getDocuments()

        return try snapshot.documents.compactMap { document in
            try document.data(as: TrackRecord.self)
        }
    }

    // 2. Cập nhật thông tin (Sửa)
    func updateTrack(_ track: TrackRecord) async throws {
        guard let trackId = track.id else {
            throw NSError(
                domain: "Firestore",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Track has no ID"]
            )
        }
        try db.collection("tracks").document(trackId).setData(
            from: track,
            merge: true
        )
    }

    // 3. Xoá dòng dữ liệu (Xoá)
    func deleteTrack(trackId: String) async throws {
        try await db.collection("tracks").document(trackId).delete()
    }
    
    // Tăng lượt nghe của bài hát
    func incrementStreamCount(trackId: String) async throws {
        let docRef = db.collection("tracks").document(trackId)
        try await docRef.updateData([
            "streamCount": FieldValue.increment(Int64(1))
        ])
    }

    // Hàm tải dữ liệu phân trang, hỗ trợ Sắp xếp và Tìm kiếm Server-side
    func fetchPaginatedTracks(
        limit: Int,
        after document: DocumentSnapshot?,
        sortBy: String,
        searchText: String
    ) async throws -> (tracks: [TrackRecord], lastDoc: DocumentSnapshot?) {

        // 1. Luôn khai báo biến query là kiểu 'Query' (dùng kiểu ngầm định của Swift)
        var query: Query = db.collection("tracks")

        // Lọc bài hát theo người dùng hiện tại
        guard let currentUID = FirebaseAuthService.shared.currentUID ?? Auth.auth().currentUser?.uid else {
            return ([], nil)
        }
        query = query.whereField("contributor", isEqualTo: currentUID)

        // 2. XỬ LÝ TÌM KIẾM
        if !searchText.isEmpty {
            query =
                query
                .whereField("title", isGreaterThanOrEqualTo: searchText)
                .whereField("title", isLessThan: searchText + "\u{f8ff}")
                .order(by: "title")
        } else {
            // 3. XỬ LÝ SẮP XẾP
            query = query.order(by: sortBy)
            if sortBy == "albumId" {
                query = query.order(by: "trackNumber")
            }
        }

        // 4. PHÂN TRANG
        query = query.limit(to: limit)

        if let lastDoc = document {
            query = query.start(afterDocument: lastDoc)
        }

        // --- CHỖ NÀY LÀ NƠI DỄ GÂY CRASH NHẤT ---
        // Đảm bảo không dùng .collection("tracks") thêm lần nào nữa ở đây
        let snapshot = try await query.getDocuments()

        let tracks = snapshot.documents.compactMap { document -> TrackRecord? in
            do {
                return try document.data(as: TrackRecord.self)
            } catch {
                // In ra chính xác ID của document nào đang bị lỗi cấu trúc để lên Console xoá/sửa
                print(
                    "❌ Phát hiện Document lỗi Mapping! ID: \(document.documentID), Chi tiết: \(error)"
                )
                return nil  // Bỏ qua bài lỗi, không làm sập cả list
            }
        }

        return (tracks, snapshot.documents.last)
    }

    // 1. Lấy Top 10 bài hát được nghe nhiều nhất
    func fetchTopStreamedTracks(limit: Int = 10) async throws -> [TrackRecord] {
        let snapshot = try await db.collection("tracks")
            .order(by: "streamCount", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap {
            try? $0.data(as: TrackRecord.self)
        }
    }

    // Lấy danh sách Bài hát cho Dashboard (Nhạc của mình + Nhạc Public)
    func fetchDashboardTracks() async throws -> [TrackRecord] {
        let uid = FirebaseAuthService.shared.currentUID ?? Auth.auth().currentUser?.uid ?? ""
        let filter = Filter.orFilter([
            Filter.whereField("contributor", isEqualTo: uid),
            Filter.whereField("isPublic", isEqualTo: true)
        ])
        let snapshot = try await db.collection("tracks")
            .whereFilter(filter)
            .order(by: "albumId")
            .order(by: "trackNumber")
            .getDocuments()
        return snapshot.documents.compactMap {
            try? $0.data(as: TrackRecord.self)
        }
    }
    
    // Lấy danh sách Album cho Dashboard (Nhạc của mình + Nhạc Public)
    func fetchDashboardAlbums() async throws -> [AlbumRecord] {
        let uid = FirebaseAuthService.shared.currentUID ?? Auth.auth().currentUser?.uid ?? ""
        let filter = Filter.orFilter([
            Filter.whereField("contributor", isEqualTo: uid),
            Filter.whereField("isPublic", isEqualTo: true)
        ])
        let snapshot = try await db.collection("albums")
            .whereFilter(filter)
            .order(by: "releaseYear", descending: true)
            .getDocuments()
        return snapshot.documents.compactMap {
            try? $0.data(as: AlbumRecord.self)
        }
    }
    
    // 2. Lấy toàn bộ danh sách Album của người dùng hiện tại (Dùng cho quản lý Database)
    func fetchAllAlbums() async throws -> [AlbumRecord] {
        guard let currentUID = FirebaseAuthService.shared.currentUID ?? Auth.auth().currentUser?.uid else {
            return []
        }
        
        let snapshot = try await db.collection("albums")
            .whereField("contributor", isEqualTo: currentUID)
            .order(by: "releaseYear", descending: true)
            .getDocuments()
        return snapshot.documents.compactMap {
            try? $0.data(as: AlbumRecord.self)
        }
    }

    // 3. Lấy tất cả bài hát thuộc về một Album cụ thể
    func fetchTracks(forAlbumId albumId: String) async throws -> [TrackRecord] {
        let snapshot = try await db.collection("tracks")
            .whereField("albumId", isEqualTo: albumId)
            .order(by: "trackNumber")
            .getDocuments()
        return snapshot.documents.compactMap {
            try? $0.data(as: TrackRecord.self)
        }
    }
    
    // Hàm lưu Album lên Firestore và trả về Document ID vừa tạo
        func saveAlbum(_ album: AlbumRecord) async throws -> String {
            let docRef = db.collection("albums").document()
            try docRef.setData(from: album)
            print("✅ Đã tạo tài liệu Album mới. Document ID: \(docRef.documentID)")
            return docRef.documentID
        }
        
    // 4. Xoá Album
    func deleteAlbum(albumId: String) async throws {
        try await db.collection("albums").document(albumId).delete()
    }
    
    // 5. Cập nhật Album
    func updateAlbum(_ album: AlbumRecord) async throws {
        guard let albumId = album.id else { return }
        try db.collection("albums").document(albumId).setData(from: album, merge: true)
    }
    
    // MARK: - User Profile Methods
    
    // Lấy thông tin UserRecord
    func fetchUserRecord(uid: String) async throws -> UserRecord {
        let docRef = db.collection("users").document(uid)
        return try await docRef.getDocument().data(as: UserRecord.self)
    }
    
    // Đếm số lượng bài hát đã upload của user
    func countUserTracks(uid: String) async throws -> Int {
        let query = db.collection("tracks").whereField("contributor", isEqualTo: uid)
        let countQuery = query.count
        let snapshot = try await countQuery.getAggregation(source: .server)
        return Int(truncating: snapshot.count)
    }
    
    // Đếm số lượng Album đã upload của user
    func countUserAlbums(uid: String) async throws -> Int {
        let query = db.collection("albums").whereField("contributor", isEqualTo: uid)
        let countQuery = query.count
        let snapshot = try await countQuery.getAggregation(source: .server)
        return Int(truncating: snapshot.count)
    }
    
    // MARK: - Genres
    
    // Tải danh sách Thể loại (Genres)
    func fetchGenres() async throws -> [GenreRecord] {
        let snapshot = try await db.collection("genres")
            .order(by: "order")
            .getDocuments()
        return snapshot.documents.compactMap {
            try? $0.data(as: GenreRecord.self)
        }
    }
    
    // Khởi tạo các Thể loại mặc định nếu Collection chưa có dữ liệu
    func seedDefaultGenresIfEmpty() async throws {
        let snapshot = try await db.collection("genres").limit(to: 1).getDocuments()
        if snapshot.isEmpty {
            let defaultGenres = [
                ("Pop", 1), ("Rock", 2), ("Acoustic", 3),
                ("EDM", 4), ("Lofi", 5), ("R&B", 6),
                ("Hip Hop", 7), ("Jazz", 8), ("Classical", 9)
            ]
            
            for genre in defaultGenres {
                let docRef = db.collection("genres").document()
                let record = GenreRecord(id: docRef.documentID, name: genre.0, order: genre.1)
                try docRef.setData(from: record)
            }
            print("✅ Đã khởi tạo danh sách Thể loại mặc định.")
        }
    }
    
    // MARK: - Likes & Respect
    
    // Kiểm tra xem user đã like bài hát chưa
    func checkIfUserLikedTrack(trackId: String, userId: String) async throws -> Bool {
        let likeId = "\(userId)_\(trackId)"
        let docRef = db.collection("likes").document(likeId)
        let doc = try await docRef.getDocument()
        return doc.exists
    }
    
    // Toggle Like (Like/Unlike) và tự động update Respect cho contributor
    // Trả về true nếu trạng thái mới là Liked, false nếu Unliked
    func toggleLikeTrack(track: TrackRecord, currentUserId: String) async throws -> Bool {
        guard let trackId = track.id else { return false }
        
        let likeId = "\(currentUserId)_\(trackId)"
        let likeRef = db.collection("likes").document(likeId)
        let contributorRef = db.collection("users").document(track.contributor)
        
        // Dùng Transaction để đảm bảo tính toàn vẹn dữ liệu
        return try await db.runTransaction({ (transaction, errorPointer) -> Any? in
            let likeDoc: DocumentSnapshot
            do {
                likeDoc = try transaction.getDocument(likeRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }
            
            if likeDoc.exists {
                // Đã like -> Unlike
                transaction.deleteDocument(likeRef)
                transaction.updateData(["respectCount": FieldValue.increment(Int64(-1))], forDocument: contributorRef)
                return false
            } else {
                // Chưa like -> Like
                let newLikeData: [String: Any] = [
                    "userId": currentUserId,
                    "trackId": trackId,
                    "itemType": LikeItemType.track.rawValue,
                    "contributorId": track.contributor,
                    "createdAt": FieldValue.serverTimestamp()
                ]
                
                transaction.setData(newLikeData, forDocument: likeRef)
                transaction.updateData(["respectCount": FieldValue.increment(Int64(1))], forDocument: contributorRef)
                return true
            }
        }) as? Bool ?? false
    }
    
    // Lấy danh sách các bài hát đã like của user
    func fetchLikedTracks(userId: String) async throws -> [TrackRecord] {
        // 1. Lấy danh sách LikeRecord
        let snapshot = try await db.collection("likes")
            .whereField("userId", isEqualTo: userId)
            .whereField("itemType", isEqualTo: LikeItemType.track.rawValue)
            .order(by: "createdAt", descending: true)
            .getDocuments()
            
        let likes = snapshot.documents.compactMap { try? $0.data(as: LikeRecord.self) }
        if likes.isEmpty { return [] }
        
        // 2. Lấy thông tin chi tiết từng track từ ID
        // Vì Firestore "in" query giới hạn tối đa 10 phần tử
        let trackIds = likes.map { $0.trackId }
        var fetchedTracks: [TrackRecord] = []
        
        let chunkSize = 10
        for i in stride(from: 0, to: trackIds.count, by: chunkSize) {
            let endIndex = min(i + chunkSize, trackIds.count)
            let chunk = Array(trackIds[i..<endIndex])
            
            let tracksSnapshot = try await db.collection("tracks")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            
            let tracks = tracksSnapshot.documents.compactMap { try? $0.data(as: TrackRecord.self) }
            fetchedTracks.append(contentsOf: tracks)
        }
        
        // 3. Sắp xếp lại theo thứ tự của Likes (mới -> cũ)
        let sortedTracks = fetchedTracks.sorted { track1, track2 in
            guard let id1 = track1.id, let id2 = track2.id else { return false }
            let index1 = trackIds.firstIndex(of: id1) ?? Int.max
            let index2 = trackIds.firstIndex(of: id2) ?? Int.max
            return index1 < index2
        }
        
        return sortedTracks
    }
    
    // MARK: - Playlists
    
    func createPlaylist(title: String, ownerUID: String) async throws -> String {
        let docRef = db.collection("playlists").document()
        let newPlaylist = PlaylistRecord(
            id: docRef.documentID,
            title: title,
            description: nil,
            ownerUID: ownerUID,
            trackIds: [],
            isPublic: true, // Mặc định public khi trống
            coverDriveID: nil,
            type: .custom
        )
        try docRef.setData(from: newPlaylist)
        return docRef.documentID
    }
    
    func fetchUserPlaylists(uid: String) async throws -> [PlaylistRecord] {
        let snapshot = try await db.collection("playlists")
            .whereField("ownerUID", isEqualTo: uid)
            .order(by: "createdAt", descending: true)
            .getDocuments()
            
        return snapshot.documents.compactMap { try? $0.data(as: PlaylistRecord.self) }
    }
    
    func addTrackToPlaylist(track: TrackRecord, playlistId: String) async throws {
        guard let trackId = track.id else { return }
        
        // 1. Thêm trackId vào mảng trackIds
        let playlistRef = db.collection("playlists").document(playlistId)
        try await playlistRef.updateData([
            "trackIds": FieldValue.arrayUnion([trackId])
        ])
        
        // 2. Cập nhật quyền riêng tư
        // "hãy để mặc định là public nếu tất cả các track đều là public, ngược lại, nếu chỉ cần có 1 track là private thì playlist đó sẽ là private"
        // Nếu bài hát được thêm vào là private (isPublic = false), tự động đổi Playlist thành Private.
        let isTrackPublic = track.isPublic ?? false
        if !isTrackPublic {
            try await playlistRef.updateData(["isPublic": false])
        }
        
        // Cập nhật lại cover ảnh cho playlist (nếu playlist chưa có cover hoặc muốn lấy cover bài mới nhất)
        if let cover = track.coverDriveID {
            try await playlistRef.updateData(["coverDriveID": cover])
        }
    }
    
    func removeTrackFromPlaylist(trackId: String, playlistId: String) async throws {
        let playlistRef = db.collection("playlists").document(playlistId)
        try await playlistRef.updateData([
            "trackIds": FieldValue.arrayRemove([trackId])
        ])
        
        // Cần kiểm tra lại toàn bộ tracks xem còn bài nào private không để set lại isPublic?
        // Theo yêu cầu đơn giản thì ta có thể bỏ qua hoặc check lại. Tạm thời chỉ xóa trackId khỏi mảng để giữ nhanh performance.
    }
    
    func fetchTracksForPlaylist(trackIds: [String]) async throws -> [TrackRecord] {
        if trackIds.isEmpty { return [] }
        var fetchedTracks: [TrackRecord] = []
        let chunkSize = 10
        
        for i in stride(from: 0, to: trackIds.count, by: chunkSize) {
            let endIndex = min(i + chunkSize, trackIds.count)
            let chunk = Array(trackIds[i..<endIndex])
            
            let tracksSnapshot = try await db.collection("tracks")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            
            let tracks = tracksSnapshot.documents.compactMap { try? $0.data(as: TrackRecord.self) }
            fetchedTracks.append(contentsOf: tracks)
        }
        
        // Giữ đúng thứ tự mảng trackIds
        let sortedTracks = fetchedTracks.sorted { track1, track2 in
            guard let id1 = track1.id, let id2 = track2.id else { return false }
            let index1 = trackIds.firstIndex(of: id1) ?? Int.max
            let index2 = trackIds.firstIndex(of: id2) ?? Int.max
            return index1 < index2
        }
        
        return sortedTracks
    }
    
    func deletePlaylists(ids: [String]) async throws {
        for id in ids {
            try await db.collection("playlists").document(id).delete()
        }
    }
    
    func updatePlaylist(_ playlist: PlaylistRecord) async throws {
        guard let id = playlist.id else { return }
        try db.collection("playlists").document(id).setData(from: playlist)
    }
}
