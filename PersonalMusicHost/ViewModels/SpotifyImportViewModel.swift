//
//  SpotifyImportViewModel.swift
//  PersonalMusicHost
//
//  Điều phối toàn bộ luồng Spotify Import:
//  fetch metadata → search → score → download → tag → upload → Firestore
//
//  Upload logic tái sử dụng 100% từ GoogleDriveService và FirebaseDatabaseService.
//

import Foundation
import SwiftUI
import Combine
import AVFoundation

@MainActor
class SpotifyImportViewModel: ObservableObject {

    // MARK: - Published State

    @Published var spotifyURLText: String = ""
    @Published var importState: SpotifyImportState = .idle

    // Kết quả trung gian
    @Published var fetchedMetadata: SpotifyTrackMetadata?
    @Published var candidates: [AudioCandidate] = []
    @Published var selectedCandidate: AudioCandidate?
    @Published var taggedFileURL: URL?
    
    // Config upload
    @Published var selectedGenreId: String = ""
    @Published var availableGenres: [GenreRecord] = []
    @Published var isPublic: Bool = true

    // Tiến trình & log
    @Published var progress: Double = 0.0
    @Published var logs: [String] = []
    @Published var errorMessage: String?

    // MARK: - Dependencies

    private let metadataService: SpotifyMetadataServiceProtocol
    private let importService: SpotifyImportServiceProtocol
    private let driveService = GoogleDriveService.shared
    private let databaseService = FirebaseDatabaseService.shared

    // MARK: - Init

    nonisolated init(
        metadataService: SpotifyMetadataServiceProtocol = SpotifyMetadataService(),
        importService: SpotifyImportServiceProtocol = SpotifyImportService()
    ) {
        self.metadataService = metadataService
        self.importService = importService


        // Tải danh sách genres từ Firestore
        Task { @MainActor in
            if let genres = try? await FirebaseDatabaseService.shared.fetchGenres() {
                self.availableGenres = genres
            }
        }
    }

    // MARK: - Public Actions

    /// Bước 1: Người dùng bấm "Fetch" → Lấy metadata → Tìm kiếm → Tính điểm
    func startImport() {
        guard !spotifyURLText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let urlString = spotifyURLText.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: urlString) else {
            setFailed("URL không hợp lệ.")
            return
        }

        Task {
            defer { if importState == .fetchingMetadata { importState = .idle } }

            // Nếu không phải là link Spotify -> Bypass Search (Dùng yt-dlp lấy metadata trực tiếp)
            if !urlString.lowercased().contains("spotify") {
                await handleDirectLinkBypass(urlString: urlString)
                return
            }

            // --- Fetch Metadata (Luồng Spotify bình thường) ---
            importState = .fetchingMetadata
            progress = 0.1
            addLog("🎵 Đang lấy thông tin từ Spotify...")

            let metadata: SpotifyTrackMetadata
            do {
                metadata = try await metadataService.fetchMetadata(from: url)
                fetchedMetadata = metadata
                addLog("✅ Lấy được: \"\(metadata.title)\" — \(metadata.artist)")
            } catch {
                setFailed("Lấy metadata thất bại: \(error.localizedDescription)")
                return
            }

            // --- Auto-match Genre ---
            autoMatchGenre(from: metadata)

            // --- Search Candidates ---
            importState = .searching
            progress = 0.25
            addLog("🔍 Đang tìm kiếm bài hát tương đương...")

            let searchQuery = "\(metadata.artist) \(metadata.title) official audio"
            let found: [AudioCandidate]
            do {
                found = try await importService.searchCandidates(
                    query: searchQuery,
                    metadata: metadata
                )
                candidates = found
                addLog("📋 Tìm thấy \(found.count) ứng viên, đang tính điểm...")
            } catch {
                setFailed("Tìm kiếm thất bại: \(error.localizedDescription)")
                return
            }

            // --- Score & Select ---
            importState = .scoring
            progress = 0.4

            let scoredCandidates = importService.scoreCandidates(
                from: found,
                metadata: metadata
            )
            
            self.candidates = scoredCandidates

            guard let best = scoredCandidates.first, best.score >= 0.2 else {
                setFailed(SpotifyImportError.noMatchFound.localizedDescription ?? "Không tìm thấy bài phù hợp")
                return
            }

            selectedCandidate = best
            addLog("🏆 Chọn mặc định: \"\(best.title)\" (score: \(String(format: "%.2f", best.score)))")
            importState = .readyToUpload
            progress = 0.5
            addLog("⏸️ Chờ xác nhận (bạn có thể tải lên ngay)...")
        }
    }

    /// Xử lý Bypass Search cho link trực tiếp (Bandcamp, Mixcloud, Audiomack, YouTube...)
    private func handleDirectLinkBypass(urlString: String) async {
        importState = .fetchingMetadata
        progress = 0.2
        addLog("🔗 Đang trích xuất dữ liệu trực tiếp bằng yt-dlp...")
        
        do {
            let json = try await YtDlpService.shared.extractMetadata(from: urlString)
            let title = json["title"] as? String ?? "Unknown Title"
            let artist = json["uploader"] as? String ?? json["channel"] as? String ?? "Unknown Artist"
            let duration = json["duration"] as? Double ?? 0.0
            let thumbUrlString = json["thumbnail"] as? String
            
            var thumbData: Data? = nil
            if let tStr = thumbUrlString, let tUrl = URL(string: tStr) {
                thumbData = try? Data(contentsOf: tUrl)
            }
            
            // Tạo Metadata giả
            let mockMetadata = SpotifyTrackMetadata(
                spotifyTrackID: UUID().uuidString.prefix(12).lowercased(),
                title: title,
                artist: artist,
                album: "Direct Link",
                coverURL: thumbUrlString != nil ? URL(string: thumbUrlString!) : nil,
                coverImageData: thumbData,
                spotifyGenreHint: nil,
                isrc: nil
            )
            self.fetchedMetadata = mockMetadata
            
            // Tạo Candidate duy nhất
            let candidateId = json["id"] as? String ?? UUID().uuidString
            let candidate = AudioCandidate(
                videoId: candidateId,
                isYTMusic: true,
                title: title,
                uploaderName: artist,
                durationSeconds: Int(duration),
                streamURL: URL(string: urlString) // Sử dụng streamURL làm nguồn chứa original urlString
            )
            
            self.candidates = [candidate]
            self.selectedCandidate = candidate
            
            addLog("✅ Trích xuất thành công: \(title) - \(artist)")
            importState = .readyToUpload
            progress = 0.5
        } catch {
            setFailed("Lỗi trích xuất yt-dlp: \(error.localizedDescription)")
        }
    }

    /// Bước 2: Người dùng xác nhận → Download → Tag → Upload → Firestore
    func confirmAndUpload() {
        guard let metadata = fetchedMetadata,
              let candidate = selectedCandidate else { return }

        Task {
            defer {
                if importState == .uploading || importState == .tagging || importState == .downloading {
                    importState = .idle
                }
            }

            // --- Download ---
            importState = .downloading
            progress = 0.55
            addLog("⬇️ Đang tải audio: \"\(candidate.title)\"...")

            var rawURL: URL?
            do {
                rawURL = try await importService.downloadAudio(candidate: candidate)
                addLog("✅ Tải xong: \(rawURL!.lastPathComponent)")
            } catch let err {
                setFailed("Tải audio thất bại: \(err.localizedDescription)")
                return
            }

            guard let finalRawURL = rawURL else { return }

            // --- Tag ---
            importState = .tagging
            progress = 0.65
            addLog("🏷️ Đang chuẩn bị và gắn metadata...")

            var finalTaggedURL: URL = finalRawURL
            do {
                let tagged = try await importService.tagAudioFile(at: finalRawURL, with: metadata)
                finalTaggedURL = tagged
                taggedFileURL = tagged
                addLog("✅ Đã xử lý audio: \(tagged.lastPathComponent)")
                if tagged != finalRawURL {
                    try? FileManager.default.removeItem(at: finalRawURL)
                }
            } catch {
                addLog("⚠️ Gắn metadata atom gặp lỗi (\(error.localizedDescription)), tiếp tục dùng file audio tải về...")
                finalTaggedURL = finalRawURL
                taggedFileURL = finalRawURL
            }

            // Tính duration và kiểm tra size từ file đã tag/xử lý
            let durationSeconds = await computeDuration(of: finalTaggedURL)
            let attr = try? FileManager.default.attributesOfItem(atPath: finalTaggedURL.path)
            let fileSize = attr?[.size] as? UInt64 ?? 0
            addLog("📊 File info: \(durationSeconds)s, \(fileSize) bytes")

            // --- Upload Cover ---
            importState = .uploading
            progress = 0.70
            var uploadedCoverDriveID: String = ""

            if let coverData = metadata.coverImageData {
                addLog("🖼️ Đang upload ảnh bìa lên Drive...")
                do {
                    uploadedCoverDriveID = try await uploadCoverData(
                        coverData,
                        fileName: "\(metadata.spotifyTrackID)_cover.jpg"
                    )
                    addLog("✅ Ảnh bìa đã upload: \(uploadedCoverDriveID)")
                } catch {
                    addLog("⚠️ Lỗi upload ảnh bìa (tiếp tục không có cover): \(error.localizedDescription)")
                }
            }

            // --- Upload Audio ---
            progress = 0.80
            addLog("☁️ Đang upload audio lên Google Drive...")

            let audioFileID: String
            do {
                audioFileID = try await uploadAudioFile(finalTaggedURL)
                addLog("✅ Audio đã upload, Drive ID: \(audioFileID)")
            } catch {
                setFailed("Upload audio thất bại: \(error.localizedDescription)")
                return
            }

            // --- Save to Firestore ---
            progress = 0.92
            addLog("💾 Đang đồng bộ Firestore...")

            do {
                try await saveToFirestore(
                    metadata: metadata,
                    durationSeconds: durationSeconds,
                    audioFileID: audioFileID,
                    coverDriveID: uploadedCoverDriveID.isEmpty ? nil : uploadedCoverDriveID
                )
                addLog("✅ Lưu database thành công!")
            } catch {
                setFailed("Lưu Firestore thất bại: \(error.localizedDescription)")
                return
            }

            // Cleanup temp file
            try? FileManager.default.removeItem(at: finalTaggedURL)

            progress = 1.0
            importState = .completed
            addLog("🎉 IMPORT HOÀN TẤT! Bài hát đã có trong thư viện.")
            NotificationCenter.default.post(name: .init("LibraryNeedsRefresh"), object: nil)
        }
    }

    /// Reset về trạng thái ban đầu để import bài tiếp theo.
    func reset() {
        spotifyURLText = ""
        importState = .idle
        fetchedMetadata = nil
        candidates = []
        selectedCandidate = nil
        taggedFileURL = nil
        progress = 0.0
        logs = []
        errorMessage = nil
        selectedGenreId = ""
    }

    // MARK: - Logging

    func addLog(_ message: String) {
        let timeString = Date().formatted(date: .omitted, time: .standard)
        logs.append("[\(timeString)] \(message)")
    }

    // MARK: - Private Helpers

    private func setFailed(_ message: String) {
        importState = .failed(message)
        errorMessage = message
        addLog("❌ \(message)")
    }

    /// Tự động so khớp genre từ Spotify hint với danh sách genres trong DB.
    private func autoMatchGenre(from metadata: SpotifyTrackMetadata) {
        guard let hint = metadata.spotifyGenreHint,
              let mappedName = SpotifyMetadataService.mapSpotifyGenreHint(hint) else {
            return
        }
        // Fuzzy match với danh sách genre trong Firestore
        let matched = availableGenres.first { genre in
            genre.name.lowercased().contains(mappedName.lowercased()) ||
            mappedName.lowercased().contains(genre.name.lowercased())
        }
        if let matchedGenre = matched, let genreID = matchedGenre.id {
            selectedGenreId = genreID
            addLog("🎸 Tự động chọn thể loại: \(matchedGenre.name)")
        }
    }

    /// Đọc thời lượng thực của file âm thanh đã được tag.
    private func computeDuration(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return 0.0 }
        return CMTimeGetSeconds(duration)
    }

    /// Upload cover từ Data (không cần file tạm trên disk).
    private func uploadCoverData(_ data: Data, fileName: String) async throws -> String {
        // Ghi tạm ra file để dùng uploadImageFile hiện có
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let rootID = try await driveService.getOrCreateFolder(
            name: AppEnvironment.driveRootFolderName
        )
        let coversFolderID = try await driveService.getOrCreateFolder(
            name: "covers",
            parentID: rootID
        )
        let fileID = try await driveService.uploadImageFile(
            fileURL: tempURL,
            folderID: coversFolderID
        )
        try await driveService.setPublicPermission(fileID: fileID)
        return fileID
    }

    /// Upload audio file lên thư mục "fine quality" trong Drive root.
    private func uploadAudioFile(_ url: URL) async throws -> String {
        let rootID = try await driveService.getOrCreateFolder(
            name: AppEnvironment.driveRootFolderName
        )
        let subFolderID = try await driveService.getOrCreateFolder(
            name: "fine quality",
            parentID: rootID
        )
        let fileID = try await driveService.uploadAudioFile(
            fileURL: url,
            folderID: subFolderID
        )
        try await driveService.setPublicPermission(fileID: fileID)
        return fileID
    }

    /// Lưu TrackRecord vào Firestore.
    private func saveToFirestore(
        metadata: SpotifyTrackMetadata,
        durationSeconds: Double,
        audioFileID: String,
        coverDriveID: String?
    ) async throws {
        guard let uid = FirebaseAuthService.shared.currentUID else {
            throw NSError(
                domain: "SpotifyImport",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Chưa đăng nhập."]
            )
        }

        let record = TrackRecord(
            id: nil,
            title: metadata.title,
            artist: metadata.artist,
            duration: durationSeconds,
            albumId: metadata.album,
            trackNumber: 1,
            releaseYear: nil,
            description: nil,
            streamCount: 0,
            coverDriveID: coverDriveID,
            genreId: selectedGenreId.isEmpty ? nil : selectedGenreId,
            contributor: uid,
            isPublic: isPublic,
            googleDriveALACID: nil,
            googleDriveAACID: audioFileID,
            createdAt: nil
        )
        try await databaseService.saveTrack(record)
    }
    
}
