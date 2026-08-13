//
//  AppModels.swift
//  PersonalMusicHost
//
//  Created by TwentyMikeyOne on 24/6/26.
//

import Foundation

enum AppRoute: Hashable {
    case profile
    case ingestion
    case database
    case userProfile(String)
}

enum OutputFormat: String, CaseIterable {
    case aac = "AAC"
    case alac = "ALAC"
}
 
struct AudioTrack: Identifiable {
    let id = UUID()
    var sourceURL: URL
    var title: String = "Unknown Title"
    var artist: String = "Unknown Artist"
    var startTime: Double = 0.0
    var duration: Double = 0.0
    var albumName: String = "Unknown Album"
    var trackNumber: Int = 0
    var releaseYear: Int?
    var description: String?
    var genreId: String?
    
    var localAAC_URL: URL?
    var localALAC_URL: URL?
    
    var driveAAC_ID: String?
    var driveALAC_ID: String?
}

struct DriveUploadResult {
    let aacFileID: String
    let alacFileID: String
}
