//
//  SpotifyImportService.swift
//  PersonalMusicHost
//
//  Pipeline core:
//  1. searchCandidates    — Tìm kiếm trên các nguồn được cấu hình (Piped,…)
//  2. scoreCandidates     — Thuật toán tính điểm trọng số để chọn ứng viên tốt nhất
//  3. downloadAudio       — Tải file .m4a về thư mục tạm bằng URLSession
//  4. tagAudioFile        — Nhúng metadata + ảnh bìa bằng AVFoundation (passthrough, không transcode)
//

import Foundation
import AVFoundation
import CryptoKit

// MARK: - Error Definitions

enum SpotifyImportError: Error, LocalizedError {
    case invalidURL
    case noMatchFound
    case noActiveEndpoints
    case searchFailed(String)
    case downloadFailed(String)
    case uploadFailed(String)
    case databaseError(String)
    case invalidMetadata
    case processingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL không hợp lệ"
        case .noMatchFound: return "Không tìm thấy bài hát phù hợp"
        case .noActiveEndpoints: return "Không có server nào hoạt động"
        case .searchFailed(let msg): return "Lỗi tìm kiếm: \(msg)"
        case .downloadFailed(let msg): return "Lỗi tải xuống: \(msg)"
        case .uploadFailed(let msg): return "Lỗi tải lên: \(msg)"
        case .databaseError(let msg): return "Lỗi CSDL: \(msg)"
        case .invalidMetadata: return "Metadata không hợp lệ"
        case .processingError(let msg): return "Lỗi xử lý: \(msg)"
        }
    }
}

// MARK: - Protocol

protocol SpotifyImportServiceProtocol {
    func searchCandidates(
        query: String,
        metadata: SpotifyTrackMetadata
    ) async throws -> [AudioCandidate]

    func scoreCandidates(
        from candidates: [AudioCandidate],
        metadata: SpotifyTrackMetadata
    ) -> [AudioCandidate]

    func downloadAudio(candidate: AudioCandidate) async throws -> URL

    func tagAudioFile(
        at sourceURL: URL,
        with metadata: SpotifyTrackMetadata
    ) async throws -> URL
}

// MARK: - Service

final class SpotifyImportService: SpotifyImportServiceProtocol {
    private let scoreThreshold: Double = 0.45

    // Các từ khoá bị phạt nặng nếu xuất hiện trong ứng viên mà không có trong metadata gốc
    private let penaltyKeywords = [
        "cover", "remix", "live", "slowed", "reverb", "karaoke",
        "instrumental", "acoustic", "nightcore", "speed up", "1 hour", "1h", "1 giờ",
        "tuyển tập", "tổng hợp", "những bài hát hay nhất", "album", "mashup", "top hits",
        "playlist", "liên khúc", "lk ", "lofi", "lo-fi", "tập ", "audio lyrics video"
    ]


    // MARK: - 1. Search Candidates

    /// Tìm kiếm ứng viên từ YouTube Music và YouTube thường (Fallback)
    func searchCandidates(
        query: String,
        metadata: SpotifyTrackMetadata
    ) async throws -> [AudioCandidate] {
        var allCandidates: [AudioCandidate] = []
        var lastError: Error?

        // 1. Tìm kiếm trên YouTube Music trước tiên
        var ytmCandidates: [AudioCandidate] = []
        do {
            ytmCandidates = try await searchYouTubeMusicInnerTube(query: query)
            allCandidates.append(contentsOf: ytmCandidates)
        } catch {
            lastError = error
            print("⚠️ Lỗi lấy YouTube Music: \(error.localizedDescription)")
        }
        
        let bestScore = allCandidates.map { computeScore(candidate: $0, metadata: metadata) }.max() ?? 0
        let hasGoodYTMMatch = bestScore >= 0.7
        let needsDurationFix = allCandidates.contains { $0.durationSeconds == 0 }

        // 2. Fetch YouTube thường nếu: (a) Điểm YT Music quá thấp (để làm fallback cho UI) hoặc (b) Cần để sửa lỗi duration = 0
        var ytCandidates: [AudioCandidate] = []
        if !hasGoodYTMMatch || needsDurationFix {
            do {
                ytCandidates = try await searchYouTubeInnerTube(query: query)
                allCandidates.append(contentsOf: ytCandidates)
            } catch {
                print("⚠️ Lỗi lấy YouTube thường: \(error.localizedDescription)")
            }
        }
        
        // 3. Chuẩn hoá thời lượng an toàn
        for i in 0..<allCandidates.count {
            if allCandidates[i].durationSeconds == 0 {
                let currentTokens = tokenize(allCandidates[i].title)
                if let match = allCandidates.first(where: {
                    $0.durationSeconds >= 60 && $0.durationSeconds <= 600 &&
                    jaccardSimilarity(a: currentTokens, b: tokenize($0.title)) >= 0.3
                }) {
                    let updated = AudioCandidate(
                        videoId: allCandidates[i].videoId,
                        isYTMusic: allCandidates[i].isYTMusic,
                        title: allCandidates[i].title,
                        uploaderName: allCandidates[i].uploaderName,
                        durationSeconds: match.durationSeconds,
                        streamURL: allCandidates[i].streamURL
                    )
                    allCandidates[i] = updated
                }
            }
        }

        // 4. Lọc bỏ các video YouTube thường nếu YT Music đã có kết quả tốt (đã mượn YT thường để sửa duration xong)
        if hasGoodYTMMatch {
            allCandidates.removeAll { !$0.isYTMusic }
        }

        // 5. Lọc bỏ hoàn toàn các video dài quá 15 phút (tuyển tập / liên khúc / 1-hour loops)
        allCandidates.removeAll { $0.durationSeconds > 900 }

        if allCandidates.isEmpty {
            let msg = lastError?.localizedDescription ?? "Không tìm thấy kết quả nào"
            throw SpotifyImportError.searchFailed(msg)
        }

        return allCandidates
    }

    // MARK: - 2. Score & Select

    /// Tính điểm cho từng ứng viên và sắp xếp giảm dần theo điểm.
    func scoreCandidates(
        from candidates: [AudioCandidate],
        metadata: SpotifyTrackMetadata
    ) -> [AudioCandidate] {
        var scored = candidates.map { candidate -> AudioCandidate in
            var c = candidate
            c.score = computeScore(candidate: candidate, metadata: metadata)
            return c
        }
        scored.sort { $0.score > $1.score }
        return scored
    }

    // MARK: - 3. Download Audio

    /// Lấy direct stream URL từ Piped và tải file về thư mục tạm.
    /// Ưu tiên stream m4a/audio-mp4 để tránh transcode sau này.
    func downloadAudio(candidate: AudioCandidate) async throws -> URL {
        #if os(macOS)
        if YtDlpService.shared.isInstalled {
            let fileName = "\(candidate.videoId)_raw.m4a"
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            do {
                let localFile = try await YtDlpService.shared.downloadAudio(
                    videoId: candidate.videoId,
                    destinationURL: destination,
                    directURL: candidate.streamURL?.absoluteString
                )
                print("✅ Tải trực tiếp bằng Native yt-dlp thành công: \(localFile.path)")
                return localFile
            } catch {
                throw SpotifyImportError.downloadFailed("Native yt-dlp tải thất bại: \(error.localizedDescription)")
            }
        } else {
            throw SpotifyImportError.downloadFailed("yt-dlp chưa được cài đặt trên macOS.")
        }
        #else
        throw SpotifyImportError.downloadFailed("Chức năng tải chỉ hỗ trợ trên macOS (thông qua yt-dlp).")
        #endif
    }

    // MARK: - 4. Tag Audio File

    /// Nhúng metadata và ảnh bìa vào file âm thanh sử dụng AVAssetExportSession.
    /// Tự động fallback an toàn về file gốc nếu thiết bị không hỗ trợ nhúng atom để đảm bảo 100% upload thành công.
    func tagAudioFile(
        at sourceURL: URL,
        with metadata: SpotifyTrackMetadata
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let outputFileName = "\(metadata.spotifyTrackID)_tagged.m4a"
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(outputFileName)
        try? FileManager.default.removeItem(at: outputURL)

        // Chuẩn bị danh sách metadata items theo chuẩn Apple
        var metadataItems: [AVMetadataItem] = []

        // Title
        let titleItem = AVMutableMetadataItem()
        titleItem.keySpace = .common
        titleItem.key = AVMetadataKey.commonKeyTitle as NSString
        titleItem.value = metadata.title as NSString
        metadataItems.append(titleItem)

        // Artist
        let artistItem = AVMutableMetadataItem()
        artistItem.keySpace = .common
        artistItem.key = AVMetadataKey.commonKeyArtist as NSString
        artistItem.value = metadata.artist as NSString
        metadataItems.append(artistItem)

        // Album
        if !metadata.album.isEmpty {
            let albumItem = AVMutableMetadataItem()
            albumItem.keySpace = .common
            albumItem.key = AVMetadataKey.commonKeyAlbumName as NSString
            albumItem.value = metadata.album as NSString
            metadataItems.append(albumItem)
        }

        // Artwork
        if let coverData = metadata.coverImageData {
            let artworkItem = AVMutableMetadataItem()
            artworkItem.keySpace = .common
            artworkItem.key = AVMetadataKey.commonKeyArtwork as NSString
            artworkItem.value = coverData as NSData
            metadataItems.append(artworkItem)
        }

        // 1. Thử export với AppleM4A preset (tự động trích xuất âm thanh từ MP4/M4A/Video và transcode sang AAC chuẩn của Apple)
        if let transcodeSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) {
            transcodeSession.outputURL = outputURL
            transcodeSession.outputFileType = .m4a
            transcodeSession.metadata = metadataItems
            await transcodeSession.export()
            
            if transcodeSession.status == .completed {
                return outputURL
            } else {
                print("⚠️ AVAssetExportPresetAppleM4A thất bại: \(transcodeSession.error?.localizedDescription ?? "unknown")")
            }
        }

        // 2. Thử export với Passthrough
        try? FileManager.default.removeItem(at: outputURL)
        if let passthroughSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) {
            passthroughSession.outputURL = outputURL
            passthroughSession.outputFileType = .m4a
            passthroughSession.metadata = metadataItems
            await passthroughSession.export()
            
            if passthroughSession.status == .completed {
                return outputURL
            } else {
                print("⚠️ Passthrough thất bại: \(passthroughSession.error?.localizedDescription ?? "unknown")")
            }
        }

        // 3. Fallback an toàn tuyệt đối: Trả về file gốc để upload Drive thành công 100%
        print("⚠️ Không thể gắn metadata atom cục bộ vào file này, sử dụng file gốc để tải lên Drive...")
        return sourceURL
    }

    // MARK: - Private: Scoring Algorithm

    /// Tính điểm tương đồng chuẩn xác (0.0 – 1.0) ưu tiên bản gốc và loại bỏ bài rác/tuyển tập
    private func computeScore(candidate: AudioCandidate, metadata: SpotifyTrackMetadata) -> Double {
        var score: Double = 0.0
        let targetTitleClean = cleanSearchString(metadata.title)
        let targetArtistClean = cleanSearchString(metadata.artist)
        let candTitleClean = cleanSearchString(candidate.title)
        let candUploaderClean = cleanSearchString(candidate.uploaderName)

        // 1. Khớp tiêu đề bài hát (0.00 -> 0.40)
        if candTitleClean == targetTitleClean || candTitleClean.contains(targetTitleClean) || targetTitleClean.contains(candTitleClean) {
            score += 0.40
        } else {
            let tTokens = tokenize(targetTitleClean)
            let cTokens = tokenize(candTitleClean)
            if !tTokens.isEmpty {
                let overlap = Double(tTokens.intersection(cTokens).count) / Double(tTokens.count)
                score += overlap * 0.40
            }
        }

        // 2. Khớp tên nghệ sĩ (0.00 -> 0.35)
        if candUploaderClean.contains(targetArtistClean) || candTitleClean.contains(targetArtistClean) {
            score += 0.35
        } else {
            let aTokens = tokenize(targetArtistClean)
            let cAllTokens = tokenize("\(candUploaderClean) \(candTitleClean)")
            if !aTokens.isEmpty {
                let overlap = Double(aTokens.intersection(cAllTokens).count) / Double(aTokens.count)
                score += overlap * 0.35
            }
        }

        // 3. Chỉ dấu bản phát hành chính thức (0.00 -> 0.15)
        let candFullText = "\(candidate.title) \(candidate.uploaderName)".lowercased()
        if candidate.uploaderName.hasSuffix(" - Topic") ||
           candFullText.contains("official audio") ||
           candFullText.contains("official music video") ||
           candFullText.contains("official mv") ||
           candFullText.contains("official visualizer") {
            score += 0.15
        }

        // 4. Ưu tiên nguồn từ YouTube Music vì là bài hát chính thức
        if candidate.isYTMusic {
            score += 0.20
        }
        // 5. Kiểm tra thời lượng hợp lý của một bài hát
        if candidate.durationSeconds > 600 { // > 10 phút -> video tuyển tập/mashup dài
            score -= 0.60
        } else if candidate.durationSeconds >= 120 && candidate.durationSeconds <= 420 {
            score += 0.05
        }

        // 6. Phạt nặng từ khoá rác (Cover, Live, Remix, Tuyển tập...)
        let targetFullText = "\(metadata.title) \(metadata.artist)".lowercased()
        for keyword in penaltyKeywords {
            if candFullText.contains(keyword) && !targetFullText.contains(keyword) {
                score -= 0.45
                break
            }
        }

        return max(0.0, min(1.0, score))
    }

    private func cleanSearchString(_ text: String) -> String {
        var str = text.lowercased()
        str = str.replacingOccurrences(of: "\\([^)]*\\)", with: " ", options: .regularExpression)
        str = str.replacingOccurrences(of: "\\[[^]]*\\]", with: " ", options: .regularExpression)
        str = str.replacingOccurrences(of: "[^a-z0-9\\sàáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ]", with: " ", options: .regularExpression)
        let tokens = str.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return tokens.joined(separator: " ")
    }

    /// Tách chuỗi thành tập hợp token lowercase, bỏ ký tự đặc biệt.
    private func tokenize(_ text: String) -> Set<String> {
        let cleaned = text.lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
        let tokens = cleaned.components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count > 1 }
        return Set(tokens)
    }

    /// Hệ số Jaccard: |A ∩ B| / |A ∪ B|
    private func jaccardSimilarity(a: Set<String>, b: Set<String>) -> Double {
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        guard union > 0 else { return 0.0 }
        return Double(intersection) / Double(union)
    }

    // MARK: - Private: YouTube Music (WEB_REMIX)

    /// Tìm kiếm video trên YouTube Music qua InnerTube API (không cần API key).
    private func searchYouTubeMusicInnerTube(query: String) async throws -> [AudioCandidate] {
        guard let url = URL(string: "https://music.youtube.com/youtubei/v1/search?prettyPrint=false") else {
            throw SpotifyImportError.searchFailed("YT Music URL không hợp lệ")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB_REMIX",
                    "clientVersion": "1.20231214.00.00",
                    "hl": "en"
                ]
            ],
            "query": query
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw SpotifyImportError.searchFailed("YouTube Music HTTP \(statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SpotifyImportError.searchFailed("Không parse được JSON từ YouTube Music")
        }

        let items = extractMusicResponsiveItems(from: json)
        print("🎬 YT Music: tìm thấy \(items.count) items")

        guard !items.isEmpty else {
            throw SpotifyImportError.searchFailed("Không tìm thấy kết quả từ YouTube Music")
        }

        return items.prefix(15).compactMap { item -> AudioCandidate? in
            guard let playlistItemData = item["playlistItemData"] as? [String: Any],
                  let videoId = playlistItemData["videoId"] as? String, !videoId.isEmpty else { return nil }
            
            var title = "Unknown"
            var artist = ""
            var durationSeconds = 0
            
            var allRunsText: [String] = []
            if let flexColumns = item["flexColumns"] as? [[String: Any]] {
                // Title (flexColumns[0])
                if flexColumns.count > 0,
                   let renderer = flexColumns[0]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
                   let textObj = renderer["text"] as? [String: Any],
                   let runs = textObj["runs"] as? [[String: Any]] {
                    title = runs.compactMap { $0["text"] as? String }.joined()
                }
                
                // Collect all texts across remaining flexColumns
                for col in flexColumns.dropFirst() {
                    if let renderer = col["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
                       let textObj = renderer["text"] as? [String: Any],
                       let runs = textObj["runs"] as? [[String: Any]] {
                        let texts = runs.compactMap { $0["text"] as? String }
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { $0 != "•" && !$0.isEmpty }
                        allRunsText.append(contentsOf: texts)
                    }
                }
            }
            
            // Check fixedColumns for duration as well
            if let fixedColumns = item["fixedColumns"] as? [[String: Any]] {
                for col in fixedColumns {
                    if let renderer = col["musicResponsiveListItemFixedColumnRenderer"] as? [String: Any],
                       let textObj = renderer["text"] as? [String: Any],
                       let runs = textObj["runs"] as? [[String: Any]] {
                        let texts = runs.compactMap { $0["text"] as? String }
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { $0 != "•" && !$0.isEmpty }
                        allRunsText.append(contentsOf: texts)
                    }
                }
            }

            // Trích xuất artist và duration chính xác
            let filteredTexts = allRunsText.filter { text in
                let lower = text.lowercased()
                return lower != "song" && lower != "video" && lower != "artist" && lower != "album" && lower != "single" && !lower.contains("views") && !lower.contains("plays") && !lower.contains("audience")
            }
            
            if let firstArtist = filteredTexts.first(where: { !$0.contains(":") }) {
                artist = firstArtist
            }
            
            if let durText = allRunsText.first(where: { $0.contains(":") }) {
                durationSeconds = parseDurationString(durText)
            }

            // Gắn hậu tố " - Topic" để các hàm tính điểm và giao diện hiểu đây là track âm thanh chính thức
            return AudioCandidate(
                videoId: videoId,
                isYTMusic: true,
                title: title,
                uploaderName: artist.isEmpty ? "YouTube Music" : (artist + " - Topic"),
                durationSeconds: durationSeconds,
                streamURL: nil
            )
        }
    }

    /// Duyệt đệ quy JSON để tìm tất cả object có key "musicResponsiveListItemRenderer"
    private func extractMusicResponsiveItems(from object: Any, depth: Int = 0) -> [[String: Any]] {
        guard depth < 20 else { return [] }
        var results: [[String: Any]] = []

        if let dict = object as? [String: Any] {
            if let renderer = dict["musicResponsiveListItemRenderer"] as? [String: Any] {
                results.append(renderer)
            }
            for value in dict.values {
                results.append(contentsOf: extractMusicResponsiveItems(from: value, depth: depth + 1))
            }
        } else if let array = object as? [Any] {
            for item in array {
                results.append(contentsOf: extractMusicResponsiveItems(from: item, depth: depth + 1))
            }
        }
        return results
    }

    /// Parse "3:45" hoặc "1:03:45" → seconds
    private func parseDurationString(_ text: String) -> Int {
        let parts = text.components(separatedBy: ":").compactMap { Int($0) }
        switch parts.count {
        case 2: return parts[0] * 60 + parts[1]
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return 0
        }
    }

    /// Tìm kiếm video trên YouTube thường qua InnerTube API (client: WEB) để lấy chính xác thời lượng mm:ss
    private func searchYouTubeInnerTube(query: String) async throws -> [AudioCandidate] {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/search?prettyPrint=false") else {
            return []
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB",
                    "clientVersion": "2.20231214.00.00",
                    "hl": "en"
                ]
            ],
            "query": query
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let renderers = extractVideoRenderers(from: json)
        return renderers.prefix(10).compactMap { item -> AudioCandidate? in
            guard let videoId = item["videoId"] as? String, !videoId.isEmpty else { return nil }
            
            var title = "Unknown"
            if let titleObj = item["title"] as? [String: Any],
               let runs = titleObj["runs"] as? [[String: Any]],
               let first = runs.first?["text"] as? String {
                title = first
            }
            
            var uploader = "YouTube"
            if let ownerObj = item["ownerText"] as? [String: Any],
               let runs = ownerObj["runs"] as? [[String: Any]],
               let first = runs.first?["text"] as? String {
                uploader = first
            }
            
            var durationSeconds = 0
            if let lenObj = item["lengthText"] as? [String: Any],
               let durStr = lenObj["simpleText"] as? String {
                durationSeconds = parseDurationString(durStr)
            }
            
            return AudioCandidate(
                videoId: videoId,
                isYTMusic: false,
                title: title,
                uploaderName: uploader,
                durationSeconds: durationSeconds,
                streamURL: nil
            )
        }
    }

    private func extractVideoRenderers(from object: Any, depth: Int = 0) -> [[String: Any]] {
        guard depth < 20 else { return [] }
        var results: [[String: Any]] = []

        if let dict = object as? [String: Any] {
            if let renderer = dict["videoRenderer"] as? [String: Any] {
                results.append(renderer)
            }
            for value in dict.values {
                results.append(contentsOf: extractVideoRenderers(from: value, depth: depth + 1))
            }
        } else if let array = object as? [Any] {
            for item in array {
                results.append(contentsOf: extractVideoRenderers(from: item, depth: depth + 1))
            }
        }
        return results
    }


    // MARK: - Resolve Stream URL

    // Phân giải stream URL dựa theo nguồn

    /// Lấy direct stream URL qua Backend cá nhân trên Vercel (chạy yt-dlp) kèm Cookies động từ thiết bị

    /// Tải trực tiếp file audio qua Fly.io Proxy (chạy yt-dlp + Stream Proxy với IP không bị botguard)

    /// Lấy stream URL từ Cobalt API, luân chuyển qua nhiều s

    /// Lấy stream URL từ Piped API: GET {baseURL}/streams/{videoId}

    /// Lấy stream URL từ Invidious API: GET {baseURL}/api/v1/videos/{videoId}

    // MARK: - Private: Fallback Logic

    /// Xử lý phương án dự phòng khi Piped thất bạ
    
    // MARK: - Private: SoundCloud Search & Stream

    // MARK: - Private: Zing MP3 Integration

    private let zingVersion = "1.6.34"
    private let zingBaseURL = "https://zingmp3.vn"
    private let zingSecretKey = "2aa2d1c561e809b267f3638c4a307aab"
    private let zingApiKey = "88265e23d4284f25963e6eedac8fbfa3"
}
