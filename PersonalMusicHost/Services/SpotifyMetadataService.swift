//
//  SpotifyMetadataService.swift
//  PersonalMusicHost
//
//  Lấy metadata track từ Spotify sử dụng oEmbed API (không cần credentials).
//  - Parse Spotify Track ID từ URL
//  - Gọi oEmbed để lấy title, artist, album, thumbnail URL
//  - Tải ảnh bìa về bộ nhớ đệm
//  - Map genre hint từ Spotify nếu có thông tin
//

import Foundation
import AVFoundation

// MARK: - Protocol

protocol SpotifyMetadataServiceProtocol {
    func fetchMetadata(from spotifyURL: URL) async throws -> SpotifyTrackMetadata
}

// MARK: - Errors

enum SpotifyMetadataError: LocalizedError {
    case invalidSpotifyURL
    case oEmbedFetchFailed(String)
    case trackIDNotFound
    case coverFetchFailed

    var errorDescription: String? {
        switch self {
        case .invalidSpotifyURL:
            return "URL Spotify không hợp lệ. Hãy đảm bảo bắt đầu bằng open.spotify.com/track/…"
        case .oEmbedFetchFailed(let msg):
            return "Không thể lấy metadata từ Spotify oEmbed: \(msg)"
        case .trackIDNotFound:
            return "Không tìm thấy Track ID trong URL Spotify."
        case .coverFetchFailed:
            return "Không thể tải ảnh bìa từ Spotify."
        }
    }
}

// MARK: - Service

final class SpotifyMetadataService: SpotifyMetadataServiceProtocol {

    // MARK: - Public API

    /// Lấy metadata từ một URL Spotify track.
    func fetchMetadata(from spotifyURL: URL) async throws -> SpotifyTrackMetadata {
        // 1. Trích xuất Track ID từ URL
        let trackID = try extractTrackID(from: spotifyURL)

        // 2. Tải HTML trang web
        var request = URLRequest(url: spotifyURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw SpotifyMetadataError.oEmbedFetchFailed("Không thể tải trang Spotify")
        }

        // 3. Trích xuất meta tags
        let title = extractMetaTag(property: "og:title", from: html) ?? ""
        let description = extractMetaTag(property: "og:description", from: html) ?? ""
        let imageURLStr = extractMetaTag(property: "og:image", from: html) ?? ""
        
        // description format: "Rick Astley · Whenever You Need Somebody · Song · 1987"
        var parsedArtist = "Unknown Artist"
        var parsedAlbum = ""
        
        let parts = description.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count >= 1 {
            parsedArtist = parts[0]
        }
        if parts.count >= 4 { // Artist, Album, Type, Year
            parsedAlbum = parts[1]
        } else if parts.count == 3 {
            // Might be Artist, Type, Year (if it's a single)
            if Int(parts[2]) == nil {
                parsedAlbum = parts[1]
            }
        }
        
        if parsedArtist.isEmpty { parsedArtist = "Unknown Artist" }
        if parsedAlbum.isEmpty { parsedAlbum = title } // fallback album is title
        
        // 4. Tải ảnh bìa
        let coverURL = URL(string: imageURLStr)
        let coverData = await fetchCoverImage(from: coverURL)
        
        return SpotifyTrackMetadata(
            spotifyTrackID: trackID,
            title: title.isEmpty ? "Unknown Title" : title,
            artist: parsedArtist,
            album: parsedAlbum,
            coverURL: coverURL,
            coverImageData: coverData,
            spotifyGenreHint: nil,
            isrc: nil
        )
    }

    // MARK: - Private Helpers

    /// Trích xuất Track ID từ URL dạng:
    /// https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh?si=...
    private func extractTrackID(from url: URL) throws -> String {
        let urlString = url.absoluteString
        // Pattern: /track/{22-char-base62-id}
        let pattern = #"(?:open\.spotify\.com/track/)([A-Za-z0-9]{22})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: urlString,
                range: NSRange(urlString.startIndex..., in: urlString)
              ),
              let range = Range(match.range(at: 1), in: urlString) else {
            throw SpotifyMetadataError.trackIDNotFound
        }
        return String(urlString[range])
    }

    /// Tải ảnh bìa về dạng Data. Không throw — trả về nil nếu thất bại.
    private func fetchCoverImage(from url: URL?) async -> Data? {
        guard let url = url else { return nil }
        return try? await URLSession.shared.data(from: url).0
    }

    private func extractMetaTag(property: String, from html: String) -> String? {
        let pattern1 = "<meta\\s+property=\"\(property)\"\\s+content=\"([^\"]+)\""
        if let regex = try? NSRegularExpression(pattern: pattern1, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return decodeHTMLEntities(String(html[range]))
        }
        
        let pattern2 = "<meta\\s+content=\"([^\"]+)\"\\s+property=\"\(property)\""
        if let regex = try? NSRegularExpression(pattern: pattern2, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return decodeHTMLEntities(String(html[range]))
        }
        
        return nil
    }
    
    private func decodeHTMLEntities(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
    }

    // MARK: - Genre Mapping (từ Spotify category hint)

    /// Map từ Spotify genre string sang GenreRecord ID trong Firestore.
    /// Kết quả là tên genre để fuzzy-match với danh sách genre trong DB.
    static func mapSpotifyGenreHint(_ hint: String?) -> String? {
        guard let hint = hint?.lowercased() else { return nil }

        let mapping: [(keywords: [String], genreName: String)] = [
            (["pop"], "Pop"),
            (["rock", "indie rock", "alternative"], "Rock"),
            (["hip hop", "rap", "trap"], "Hip-Hop"),
            (["r&b", "rnb", "soul"], "R&B"),
            (["jazz"], "Jazz"),
            (["classical", "orchestral", "symphony"], "Classical"),
            (["electronic", "edm", "dance", "house", "techno"], "Electronic"),
            (["metal", "heavy metal", "death metal"], "Metal"),
            (["country"], "Country"),
            (["folk", "acoustic"], "Folk"),
            (["blues"], "Blues"),
            (["reggae"], "Reggae"),
            (["latin", "salsa", "bossa nova"], "Latin"),
            (["k-pop", "kpop"], "K-Pop"),
        ]

        for entry in mapping {
            for keyword in entry.keywords {
                if hint.contains(keyword) {
                    return entry.genreName
                }
            }
        }
        return nil
    }
}
