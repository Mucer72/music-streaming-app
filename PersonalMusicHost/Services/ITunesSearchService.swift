//
//  ITunesSearchService.swift
//  PersonalMusicHost
//
//  Created by AI.
//

import Foundation

enum SearchServiceError: Error {
    case invalidURL
    case invalidResponse
    case decodingError
}

class ITunesSearchService: SearchServiceProtocol {
    
    struct SearchResponse: Codable {
        let results: [TrackMetadataItem]
    }
    
    func search(query: String) async throws -> [TrackMetadataItem] {
        guard !query.isEmpty else { return [] }
        
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://itunes.apple.com/search?term=\(encodedQuery)&entity=song&limit=15&country=VN"
        
        guard let url = URL(string: urlString) else {
            throw SearchServiceError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw SearchServiceError.invalidResponse
        }
        
        do {
            let searchResponse = try JSONDecoder().decode(SearchResponse.self, from: data)
            return searchResponse.results
        } catch {
            throw SearchServiceError.decodingError
        }
    }
}
