//
//  TrackMetadataItem.swift
//  PersonalMusicHost
//
//  Created by AI.
//

import Foundation

struct TrackMetadataItem: Identifiable, Codable, Equatable {
    var id: String {
        return "\(artistName)-\(trackName)"
    }
    
    let trackName: String
    let artistName: String
    let collectionName: String? // Album name
    let trackTimeMillis: Int?
    let artworkUrl100: String?
    
    var durationFormatted: String {
        guard let millis = trackTimeMillis else { return "0:00" }
        let totalSeconds = millis / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var coverURL: URL? {
        guard let urlString = artworkUrl100?.replacingOccurrences(of: "100x100bb.jpg", with: "600x600bb.jpg") else {
            return nil
        }
        return URL(string: urlString)
    }
}
