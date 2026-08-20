//
//  SpotifyImportViewModel.swift
//  PersonalMusicHost
//
//  Điều phối toàn bộ luồng Spotify Import:
//  fetch metadata → search → score → download → tag → upload Drive → Firestore
//
//  Upload logic tái sử dụng từ GoogleDriveService và FirebaseDatabaseService.
//

import Foundation
import SwiftUI
import Combine
import AVFoundation
import FirebaseAuth

@MainActor
class SpotifyImportViewModel: ObservableObject {

    // MARK: - Published State

    @Published var spotifyURLText: String = ""
    @Published var importState: SpotifyImportState = .idle

    // Kết quả trung gian
    @Published var fetchedMetadata: SpotifyTrackMetadata?
    @Published var searchResults: [TrackMetadataItem] = [] // Kết quả tìm kiếm trực tiếp
    @Published var candidates: [AudioCandidate] = []
    @Published var selectedCandidate: AudioCandidate?
    @Published var taggedFileURL: URL?
    
    // Config upload
    @Published var selectedGenreId: String = ""
    @Published var availableGenres: [GenreRecord] = []
    @Published var isPublic: Bool = true

    // Tiến trình & log
    @Published var progress: Double = 0.0
    @Published var downloadPercentage: Double = 0.0
    @Published var logs: [String] = []
    @Published var errorMessage: String?

    // MARK: - Dependencies

    private let metadataService: SpotifyMetadataServiceProtocol
    private let importService: SpotifyImportServiceProtocol
    private let searchService = ITunesSearchService()
    private let driveService = GoogleDriveService.shared
    private let databaseService = FirebaseDatabaseService.shared

    // MARK: - Init

    init(
        metadataService: SpotifyMetadataServiceProtocol? = nil,
        importService: SpotifyImportServiceProtocol? = nil
    ) {
        self.metadataService = metadataService ?? SpotifyMetadataService()
        self.importService = importService ?? SpotifyImportService()

        // Tải danh sách genres từ Firestore
        Task {
            if let genres = try? await FirebaseDatabaseService.shared.fetchGenres() {
                self.availableGenres = genres
                if self.selectedGenreId.isEmpty, let first = genres.first?.id {
                    self.selectedGenreId = first
                }
            }
        }
    }

    // MARK: - Public Actions

    /// Bước 1: Người dùng bấm "Fetch" → Lấy metadata → Tìm kiếm → Tính điểm
    func startImport() {
        let trimmed = spotifyURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let url = URL(string: trimmed) else {
            setFailed("URL không hợp lệ.")
            return
        }

        Task {
            defer {
                if importState == .fetchingMetadata {
                    importState = .idle
                }
            }

            // Nếu là URL, xử lý luồng Link
            if trimmed.lowercased().hasPrefix("http") {
                if !trimmed.lowercased().contains("spotify") {
                    await handleDirectLinkBypass(urlString: trimmed)
                    return
                }
            } else {
                // Nếu không phải URL, coi như là từ khóa tìm kiếm
                await handleTextSearch(query: trimmed)
                return
            }

            // --- Fetch Metadata (Luồng Spotify chính thức) ---
            importState = .fetchingMetadata
            progress = 0.15
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

            // --- Search Candidates (Tìm trực tiếp trên YouTube Music) ---
            importState = .searching
            progress = 0.35
            addLog("🔍 Đang tìm kiếm trên YouTube Music...")

            let searchQuery = "\(metadata.artist) \(metadata.title)"
            let found: [AudioCandidate]
            do {
                found = try await importService.searchCandidates(
                    query: searchQuery,
                    metadata: metadata
                )
                candidates = found
                addLog("📋 Tìm thấy \(found.count) ứng viên, đang xếp hạng...")
            } catch {
                setFailed("Tìm kiếm thất bại: \(error.localizedDescription)")
                return
            }

            // --- Score & Select ---
            importState = .scoring
            progress = 0.50

            let scoredCandidates = importService.scoreCandidates(
                from: found,
                metadata: metadata
            )
            
            self.candidates = scoredCandidates

            guard let best = scoredCandidates.first, best.score >= 0.2 else {
                setFailed(SpotifyImportError.noMatchFound.localizedDescription)
                return
            }

            selectedCandidate = best
            addLog("🏆 Chọn tối ưu: \"\(best.title)\" (điểm: \(String(format: "%.2f", best.score)))")
            importState = .readyToUpload
            progress = 0.55
            addLog("⏸️ Sẵn sàng! Bạn có thể xem lại thông tin và bấm Import.")
        }
    }
    
    /// Xử lý tìm kiếm trực tiếp từ từ khóa (Sử dụng iTunes API)
    private func handleTextSearch(query: String) async {
        importState = .fetchingMetadata
        progress = 0.1
        addLog("🔍 Đang tìm kiếm bài hát trên Apple Music/iTunes: \"\(query)\"...")
        do {
            let results = try await searchService.search(query: query)
            if results.isEmpty {
                setFailed("Không tìm thấy kết quả nào cho \"\(query)\".")
            } else {
                self.searchResults = results
                addLog("✅ Đã tìm thấy \(results.count) kết quả. Vui lòng chọn một bài hát.")
                importState = .idle // Trả về idle để user chọn kết quả
            }
        } catch {
            setFailed("Lỗi tìm kiếm: \(error.localizedDescription)")
        }
    }
    
    /// Khi người dùng chọn 1 kết quả từ danh sách tìm kiếm trực tiếp
    func selectSearchResult(_ track: TrackMetadataItem) {
        // Clear search results
        self.searchResults = []
        
        // Convert to SpotifyTrackMetadata format to reuse the pipeline
        var coverData: Data? = nil
        // Tạm thời lấy thumbnail data cho UI nhanh
        
        let mockMetadata = SpotifyTrackMetadata(
            spotifyTrackID: UUID().uuidString.prefix(12).lowercased(),
            title: track.trackName,
            artist: track.artistName,
            album: track.collectionName ?? "Unknown Album",
            coverURL: track.coverURL,
            coverImageData: nil, // Will be fetched later if needed, but we can rely on url
            spotifyGenreHint: nil,
            isrc: nil
        )
        
        self.fetchedMetadata = mockMetadata
        self.spotifyURLText = "\(track.artistName) - \(track.trackName)"
        
        // Immediately show loading state so UI doesn't look stuck
        importState = .fetchingMetadata
        progress = 0.2
        addLog("🖼️ Đang tải thông tin và ảnh bìa cho bài hát...")
        
        Task {
            // Tải ảnh bìa
            if let url = track.coverURL, let (data, _) = try? await URLSession.shared.data(from: url) {
                await MainActor.run {
                    self.fetchedMetadata = SpotifyTrackMetadata(
                        spotifyTrackID: mockMetadata.spotifyTrackID,
                        title: mockMetadata.title,
                        artist: mockMetadata.artist,
                        album: mockMetadata.album,
                        coverURL: mockMetadata.coverURL,
                        coverImageData: data,
                        spotifyGenreHint: mockMetadata.spotifyGenreHint,
                        isrc: mockMetadata.isrc
                    )
                }
            }
            
            // Tiếp tục luồng search ứng viên YouTube Music
            importState = .searching
            progress = 0.35
            addLog("🔍 Đang tìm bản âm thanh cho: \"\(track.trackName)\"...")

            let searchQuery = "\(track.artistName) \(track.trackName)"
            let found: [AudioCandidate]
            do {
                // Ensure fetchedMetadata is the latest with image data
                let currentMeta = self.fetchedMetadata ?? mockMetadata
                found = try await importService.searchCandidates(
                    query: searchQuery,
                    metadata: currentMeta
                )
                self.candidates = found
                addLog("📋 Tìm thấy \(found.count) ứng viên, đang xếp hạng...")
            } catch {
                setFailed("Tìm kiếm thất bại: \(error.localizedDescription)")
                return
            }

            importState = .scoring
            progress = 0.50

            let currentMeta = self.fetchedMetadata ?? mockMetadata
            let scoredCandidates = importService.scoreCandidates(
                from: found,
                metadata: currentMeta
            )
            
            self.candidates = scoredCandidates

            guard let best = scoredCandidates.first, best.score >= 0.2 else {
                setFailed(SpotifyImportError.noMatchFound.localizedDescription)
                return
            }

            self.selectedCandidate = best
            addLog("🏆 Chọn tối ưu: \"\(best.title)\" (điểm: \(String(format: "%.2f", best.score)))")
            importState = .readyToUpload
            progress = 0.55
            addLog("⏸️ Sẵn sàng! Bạn có thể xem lại thông tin và bấm Import.")
        }
    }

    /// Xử lý Bypass Search cho link trực tiếp (YouTube, SoundCloud, Direct URLs...)
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
                thumbData = try? await URLSession.shared.data(from: tUrl).0
            }
            
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
            
            let candidateId = json["id"] as? String ?? UUID().uuidString
            let candidate = AudioCandidate(
                videoId: candidateId,
                isYTMusic: true,
                title: title,
                uploaderName: artist,
                durationSeconds: Int(duration),
                streamURL: URL(string: urlString)
            )
            
            self.candidates = [candidate]
            self.selectedCandidate = candidate
            
            addLog("✅ Trích xuất thành công: \(title) - \(artist)")
            importState = .readyToUpload
            progress = 0.55
        } catch {
            setFailed("Lỗi trích xuất yt-dlp: \(error.localizedDescription)")
        }
    }

    /// Bước 2: Người dùng xác nhận → Download → Tag → Upload → Firestore
    func confirmAndUpload() {
        guard let metadata = fetchedMetadata,
              let candidate = selectedCandidate else { return }

        Task {
            var tempFilesToCleanup: [URL] = []
            defer {
                for fileURL in tempFilesToCleanup {
                    try? FileManager.default.removeItem(at: fileURL)
                }
                if importState == .uploading || importState == .tagging || importState == .downloading {
                    importState = .idle
                }
            }

            // --- Download ---
            importState = .downloading
            progress = 0.60
            downloadPercentage = 0.0
            addLog("⬇️ Đang tải audio chất lượng cao: \"\(candidate.title)\"...")
            addLog("⏳ Quá trình tải có thể mất từ 10-30 giây, vui lòng chờ...")

            var rawURL: URL?
            do {
                rawURL = try await importService.downloadAudio(candidate: candidate) { percent in
                    Task { @MainActor in
                        self.downloadPercentage = percent
                    }
                }
                if let raw = rawURL {
                    tempFilesToCleanup.append(raw)
                    addLog("✅ Tải xong: \(raw.lastPathComponent)")
                }
            } catch let err {
                setFailed("Tải audio thất bại: \(err.localizedDescription)")
                return
            }

            guard let finalRawURL = rawURL else { return }

            // --- Tag Metadata ---
            importState = .tagging
            progress = 0.70
            addLog("🏷️ Đang gắn tag metadata & artwork...")

            var finalTaggedURL: URL = finalRawURL
            do {
                let tagged = try await importService.tagAudioFile(at: finalRawURL, with: metadata)
                finalTaggedURL = tagged
                taggedFileURL = tagged
                if tagged != finalRawURL {
                    tempFilesToCleanup.append(tagged)
                }
                addLog("✅ Đã xử lý audio: \(tagged.lastPathComponent)")
            } catch {
                addLog("⚠️ Gắn metadata atom cảnh báo: \(error.localizedDescription), tiếp tục với file tải về...")
                finalTaggedURL = finalRawURL
                taggedFileURL = finalRawURL
            }

            // Tính duration thực tế từ file đã xử lý
            let durationSeconds = await computeDuration(of: finalTaggedURL)
            let attr = try? FileManager.default.attributesOfItem(atPath: finalTaggedURL.path)
            let fileSize = attr?[.size] as? UInt64 ?? 0
            addLog("📊 Thời lượng: \(String(format: "%.1f", durationSeconds))s (\(fileSize / 1024) KB)")

            // --- Upload Cover Image ---
            importState = .uploading
            progress = 0.78
            var uploadedCoverDriveID: String = ""

            if let coverData = metadata.coverImageData {
                addLog("🖼️ Đang upload ảnh bìa lên Google Drive...")
                do {
                    uploadedCoverDriveID = try await uploadCoverData(
                        coverData,
                        fileName: "\(metadata.spotifyTrackID)_cover.jpg"
                    )
                    addLog("✅ Ảnh bìa đã upload: \(uploadedCoverDriveID)")
                } catch {
                    addLog("⚠️ Upload ảnh bìa thất bại (tiếp tục không có ảnh bìa): \(error.localizedDescription)")
                }
            }

            // --- Upload Audio ---
            progress = 0.86
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
            progress = 0.94
            addLog("💾 Đang đồng bộ dữ liệu vào Firestore...")

            do {
                try await saveToFirestore(
                    metadata: metadata,
                    durationSeconds: durationSeconds,
                    audioFileID: audioFileID,
                    coverDriveID: uploadedCoverDriveID.isEmpty ? nil : uploadedCoverDriveID
                )
                addLog("✅ Lưu Firestore thành công!")
            } catch {
                setFailed("Lưu Firestore thất bại: \(error.localizedDescription)")
                return
            }

            progress = 1.0
            importState = .completed
            addLog("🎉 IMPORT HOÀN TẤT! Bài hát đã sẵn sàng để phát trong thư viện.")
            NotificationCenter.default.post(name: .init("LibraryNeedsRefresh"), object: nil)
        }
    }

    /// Reset về trạng thái ban đầu để import bài tiếp theo.
    func reset() {
        spotifyURLText = ""
        importState = .idle
        fetchedMetadata = nil
        searchResults = []
        candidates = []
        selectedCandidate = nil
        taggedFileURL = nil
        progress = 0.0
        logs = []
        errorMessage = nil
        if let first = availableGenres.first?.id {
            selectedGenreId = first
        }
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
        let matched = availableGenres.first { genre in
            genre.name.lowercased().contains(mappedName.lowercased()) ||
            mappedName.lowercased().contains(genre.name.lowercased())
        }
        if let matchedGenre = matched, let genreID = matchedGenre.id {
            selectedGenreId = genreID
            addLog("🎸 Tự động chọn thể loại: \(matchedGenre.name)")
        }
    }

    /// Đọc thời lượng thực của file âm thanh.
    private func computeDuration(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return 0.0 }
        return CMTimeGetSeconds(duration)
    }

    /// Upload cover từ Data.
    private func uploadCoverData(_ data: Data, fileName: String) async throws -> String {
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

    /// Lưu TrackRecord vào Firestore (chuẩn hoá albumId: nil cho single track).
    private func saveToFirestore(
        metadata: SpotifyTrackMetadata,
        durationSeconds: Double,
        audioFileID: String,
        coverDriveID: String?
    ) async throws {
        guard let uid = FirebaseAuthService.shared.currentUID ?? Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "SpotifyImport",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Bạn chưa đăng nhập."]
            )
        }

        let record = TrackRecord(
            id: nil,
            title: metadata.title,
            artist: metadata.artist,
            duration: durationSeconds,
            albumId: metadata.album.isEmpty ? "Single" : metadata.album,
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
