//
//  SpotifyMetadataService.swift
//  PersonalMusicHost
//
//  Lấy metadata track từ Spotify sử dụng oEmbed API chính thức kết hợp OpenGraph fallback.
//  - Parse Spotify Track ID từ mọi định dạng URL (quốc tế /intl-*/, spotify.link, spotify:track:)
//  - Gọi Spotify oEmbed API để lấy title, artist, thumbnail URL chính thức không cần token
//  - Tải ảnh bìa trực tiếp về bộ nhớ đệm
//  - Map genre hint từ category/title nếu có thông tin
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
            return "URL Spotify không hợp lệ. Hãy đảm bảo đường link bắt đầu bằng open.spotify.com/track/…"
        case .oEmbedFetchFailed(let msg):
            return "Không thể lấy metadata từ Spotify: \(msg)"
        case .trackIDNotFound:
            return "Không tìm thấy Track ID trong URL Spotify được cung cấp."
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
        // 1. Giải quyết chuyển hướng nếu là link rút gọn (ví dụ: spotify.link/...)
        let resolvedURL = await resolveRedirectIfNeeded(url: spotifyURL)

        // 2. Trích xuất Track ID từ URL
        let trackID = try extractTrackID(from: resolvedURL)

        // 3. Chuẩn bị URL chuẩn hoá của Spotify Track
        let canonicalTrackURLString = "https://open.spotify.com/track/\(trackID)"
        guard let canonicalTrackURL = URL(string: canonicalTrackURLString) else {
            throw SpotifyMetadataError.invalidSpotifyURL
        }

        // 4. Lấy dữ liệu từ Spotify oEmbed API chính thức
        var oEmbedTitle: String?
        var oEmbedAuthor: String?
        var oEmbedCoverURL: URL?

        if let oembedEndpoint = URL(string: "https://open.spotify.com/oembed?url=\(canonicalTrackURLString)") {
            var oembedRequest = URLRequest(url: oembedEndpoint)
            oembedRequest.timeoutInterval = 10
            oembedRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

            if let (data, response) = try? await URLSession.shared.data(for: oembedRequest),
               let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                oEmbedTitle = json["title"] as? String
                oEmbedAuthor = json["author_name"] as? String
                if let thumbStr = json["thumbnail_url"] as? String {
                    oEmbedCoverURL = URL(string: thumbStr)
                }
            }
        }

        // 5. Lấy OpenGraph HTML để lấy Album và dữ liệu chi tiết hơn
        var parsedArtist = oEmbedAuthor ?? ""
        var parsedTitle = oEmbedTitle ?? ""
        var parsedAlbum = ""
        var ogCoverURL: URL?

        var htmlRequest = URLRequest(url: canonicalTrackURL)
        htmlRequest.timeoutInterval = 10
        htmlRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        if let (data, response) = try? await URLSession.shared.data(for: htmlRequest),
           let httpResponse = response as? HTTPURLResponse,
           (200...299).contains(httpResponse.statusCode),
           let html = String(data: data, encoding: .utf8) {

            let ogTitle = extractMetaTag(property: "og:title", from: html)
            let ogDescription = extractMetaTag(property: "og:description", from: html)
            let ogImage = extractMetaTag(property: "og:image", from: html)

            if let ogImage = ogImage, let url = URL(string: ogImage) {
                ogCoverURL = url
            }

            if let ogTitle = ogTitle, !ogTitle.isEmpty {
                parsedTitle = ogTitle
            }

            if let description = ogDescription, !description.isEmpty {
                // description format: "Rick Astley · Whenever You Need Somebody · Song · 1987"
                let parts = description.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count >= 1 && parsedArtist.isEmpty {
                    parsedArtist = parts[0]
                }
                if parts.count >= 4 {
                    parsedAlbum = parts[1]
                } else if parts.count == 3 && Int(parts[2]) == nil {
                    parsedAlbum = parts[1]
                }
            }
        }

        // 6. Xử lý trường hợp Title từ oEmbed có dạng "Artist - Title" hoặc "Title - Song by Artist"
        if parsedArtist.isEmpty && parsedTitle.contains(" - ") {
            let titleParts = parsedTitle.components(separatedBy: " - ")
            if titleParts.count >= 2 {
                parsedArtist = titleParts[0].trimmingCharacters(in: .whitespaces)
                parsedTitle = titleParts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
            }
        }

        if parsedTitle.isEmpty { parsedTitle = "Unknown Title" }
        if parsedArtist.isEmpty { parsedArtist = "Unknown Artist" }
        if parsedAlbum.isEmpty { parsedAlbum = parsedTitle }

        // 7. Tải ảnh bìa
        let finalCoverURL = oEmbedCoverURL ?? ogCoverURL
        let coverData = await fetchCoverImage(from: finalCoverURL)

        return SpotifyTrackMetadata(
            spotifyTrackID: trackID,
            title: parsedTitle,
            artist: parsedArtist,
            album: parsedAlbum,
            coverURL: finalCoverURL,
            coverImageData: coverData,
            spotifyGenreHint: nil,
            isrc: nil
        )
    }

    // MARK: - Private Helpers

    /// Mở rộng link rút gọn nếu có (như spotify.link/...)
    private func resolveRedirectIfNeeded(url: URL) async -> URL {
        guard url.host?.contains("spotify.link") == true else { return url }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        if let (_, response) = try? await URLSession.shared.data(for: request),
           let resolved = response.url {
            return resolved
        }
        return url
    }

    /// Trích xuất Track ID từ URL Spotify mọi định dạng:
    /// - https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh
    /// - https://open.spotify.com/intl-vi/track/4iV5W9uYEdYUVa79Axb7Rh?si=...
    /// - spotify:track:4iV5W9uYEdYUVa79Axb7Rh
    private func extractTrackID(from url: URL) throws -> String {
        let urlString = url.absoluteString
        let pattern = #"(?:open\.spotify\.com/(?:[a-zA-Z-]+/)?track/|spotify:track:)([A-Za-z0-9]{22})"#
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
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        return try? await URLSession.shared.data(for: request).0
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
