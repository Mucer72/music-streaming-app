//
//  SpotifyImportService.swift
//  PersonalMusicHost
//
//  Pipeline core:
//  1. searchCandidates — Tìm kiếm ứng viên audio từ YouTube Music và YouTube thường (Fallback)
//  2. scoreCandidates  — Thuật toán tính điểm trọng số chuẩn xác
//  3. downloadAudio    — Tải file audio .m4a chất lượng cao qua YtDlpService
//  4. tagAudioFile     — Nhúng metadata (Title, Artist, Album, Artwork) vào file .m4a
//

import Foundation
import AVFoundation

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

    func downloadAudio(candidate: AudioCandidate, onProgress: ((Double) -> Void)?) async throws -> URL

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
        do {
            let ytmCandidates = try await searchYouTubeMusicInnerTube(query: query)
            allCandidates.append(contentsOf: ytmCandidates)
        } catch {
            lastError = error
            print("⚠️ Lỗi lấy YouTube Music: \(error.localizedDescription)")
        }
        
        let bestScore = allCandidates.map { computeScore(candidate: $0, metadata: metadata) }.max() ?? 0
        let hasGoodYTMMatch = bestScore >= 0.7
        let needsDurationFix = allCandidates.contains { $0.durationSeconds == 0 }

        // 2. Fetch YouTube thường nếu: (a) Điểm YT Music quá thấp hoặc (b) Cần mượn thời lượng
        if !hasGoodYTMMatch || needsDurationFix {
            do {
                let ytCandidates = try await searchYouTubeInnerTube(query: query)
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

        // 4. Lọc bỏ các video YouTube thường nếu YT Music đã có kết quả tốt
        if hasGoodYTMMatch {
            allCandidates.removeAll { !$0.isYTMusic }
        }

        // 5. Lọc bỏ hoàn toàn các video dài quá 15 phút (tuyển tập / liên khúc)
        allCandidates.removeAll { $0.durationSeconds > 900 }

        if allCandidates.isEmpty {
            let msg = lastError?.localizedDescription ?? "Không tìm thấy kết quả phù hợp nào trên hệ thống."
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

    /// Tải file audio chất lượng cao qua YtDlpService (macOS) hoặc iOSAudioExtractionService (iOS)
    func downloadAudio(candidate: AudioCandidate, onProgress: ((Double) -> Void)? = nil) async throws -> URL {
        let fileName = "\(candidate.videoId)_raw.m4a"
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        #if os(macOS)
        if YtDlpService.shared.isInstalled {
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
        #elseif os(iOS)
        do {
            let localFile = try await iOSAudioExtractionService.shared.extractAndDownloadAudio(
                videoId: candidate.videoId,
                destinationURL: destination,
                directURL: candidate.streamURL?.absoluteString,
                onProgress: onProgress
            )
            print("✅ Tải trực tiếp bằng iOS On-Device Python thành công: \(localFile.path)")
            return localFile
        } catch {
            throw SpotifyImportError.downloadFailed("iOS On-Device Engine tải thất bại: \(error.localizedDescription)")
        }
        #else
        throw SpotifyImportError.downloadFailed("Nền tảng này không được hỗ trợ tải âm thanh.")
        #endif
    }

    // MARK: - 4. Tag Audio File

    /// Nhúng metadata và ảnh bìa vào file âm thanh sử dụng AVAssetExportSession.
    /// Tự động fallback an toàn về file gốc nếu thiết bị không hỗ trợ nhúng atom.
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

        // 1. Thử export với Passthrough trước (Tốc độ siêu nhanh, không re-encode)
        if let passthroughSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) {
            passthroughSession.outputURL = outputURL
            passthroughSession.outputFileType = .m4a
            passthroughSession.metadata = metadataItems
            await passthroughSession.export()
            
            if passthroughSession.status == .completed && FileManager.default.fileExists(atPath: outputURL.path) {
                return outputURL
            } else {
                print("⚠️ Passthrough thất bại: \(passthroughSession.error?.localizedDescription ?? "unknown")")
            }
        }

        // 2. Fallback: Thử export với AppleM4A preset (AAC chuẩn Apple, chậm hơn vì phải re-encode)
        try? FileManager.default.removeItem(at: outputURL)
        if let transcodeSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) {
            transcodeSession.outputURL = outputURL
            transcodeSession.outputFileType = .m4a
            transcodeSession.metadata = metadataItems
            await transcodeSession.export()
            
            if transcodeSession.status == .completed && FileManager.default.fileExists(atPath: outputURL.path) {
                return outputURL
            } else {
                print("⚠️ AVAssetExportPresetAppleM4A thất bại: \(transcodeSession.error?.localizedDescription ?? "unknown")")
            }
        }

        // 3. Fallback an toàn: Trả về file gốc
        print("⚠️ Sử dụng file nguồn đã tải về...")
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

        let tTokens = tokenize(targetTitleClean)
        let cTokens = tokenize(candTitleClean)
        let aTokens = tokenize(targetArtistClean)
        let uTokens = tokenize(candUploaderClean)

        // 1. Khớp tiêu đề bài hát (0.00 -> 0.40)
        if candTitleClean == targetTitleClean {
            score += 0.40
        } else if !tTokens.isEmpty {
            // Tránh substring containment cho chuỗi ngắn; dùng token overlap
            if tTokens.isSubset(of: cTokens) {
                score += 0.38
            } else {
                let overlap = Double(tTokens.intersection(cTokens).count) / Double(tTokens.count)
                score += overlap * 0.35
            }
        }

        // 2. Khớp tên nghệ sĩ (0.00 -> 0.35)
        if candUploaderClean == targetArtistClean || candUploaderClean.contains(targetArtistClean) {
            score += 0.35
        } else if !aTokens.isEmpty {
            let combinedCandTokens = uTokens.union(cTokens)
            if aTokens.isSubset(of: combinedCandTokens) {
                score += 0.32
            } else {
                let overlap = Double(aTokens.intersection(combinedCandTokens).count) / Double(aTokens.count)
                score += overlap * 0.30
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
        if candidate.durationSeconds > 600 {
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
            .replacingOccurrences(of: "[^a-z0-9\\sàáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ]", with: " ", options: .regularExpression)
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
                    "clientVersion": "1.20240101.01.00",
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
            
            if let firstArtist = filteredTexts.first(where: { !self.isDurationString($0) }) {
                artist = firstArtist
            }
            
            if let durText = allRunsText.first(where: { self.isDurationString($0) }) {
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

    /// Kiểm tra xem chuỗi có phải format thời lượng mm:ss hoặc hh:mm:ss không
    private func isDurationString(_ text: String) -> Bool {
        let pattern = #"^\d{1,2}:\d{2}(?::\d{2})?$"#
        return text.range(of: pattern, options: .regularExpression) != nil
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
                    "clientVersion": "2.20240101.01.00",
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
}
