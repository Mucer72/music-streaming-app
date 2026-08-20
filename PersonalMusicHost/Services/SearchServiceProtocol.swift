//
//  SearchServiceProtocol.swift
//  PersonalMusicHost
//
//  Created by AI.
//

import Foundation

protocol SearchServiceProtocol {
    func search(query: String) async throws -> [TrackMetadataItem]
}
