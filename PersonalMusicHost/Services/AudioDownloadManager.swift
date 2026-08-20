//
//  AudioDownloadManager.swift
//  PersonalMusicHost
//
//  Created by AI.
//

import Foundation
import AVFoundation

enum AudioDownloadError: Error {
    case extractionFailed
    case embeddingFailed
}

class AudioDownloadManager {
    static let shared = AudioDownloadManager()
    
    func processAndDownload(track: TrackMetadataItem) async throws -> URL {
        let query = "ytsearch1:\(track.artistName) - \(track.trackName) official audio"
        
        let tempDir = FileManager.default.temporaryDirectory
        let rawFileName = UUID().uuidString + ".m4a"
        let rawURL = tempDir.appendingPathComponent(rawFileName)
        
        // Trích xuất file thô bằng yt-dlp
        #if os(macOS)
        let downloadedFile = try await YtDlpService.shared.downloadAudio(videoId: "", destinationURL: rawURL, directURL: query)
        #else
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let downloadedFile = try await iOSAudioExtractionService.shared.extractAndDownloadAudio(videoId: "", destinationURL: rawURL, directURL: encodedQuery)
        #endif
        
        // Chuẩn bị destination URL trong thư mục Documents
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let safeTrackName = track.trackName.replacingOccurrences(of: "/", with: "-")
        let safeArtistName = track.artistName.replacingOccurrences(of: "/", with: "-")
        let finalURL = documentsDir.appendingPathComponent("\(safeArtistName) - \(safeTrackName).m4a")
        
        // Nhúng metadata và xuất ra
        try await embedMetadata(track: track, sourceURL: downloadedFile, destinationURL: finalURL)
        
        // Xóa file thô
        try? FileManager.default.removeItem(at: downloadedFile)
        
        return finalURL
    }
    
    private func embedMetadata(track: TrackMetadataItem, sourceURL: URL, destinationURL: URL) async throws {
        let asset = AVAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw AudioDownloadError.embeddingFailed
        }
        
        var metadata: [AVMetadataItem] = []
        
        func createMetadataItem(identifier: AVMetadataIdentifier, value: Any) -> AVMetadataItem {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value as? NSCopying & NSObjectProtocol
            item.dataType = "com.apple.metadata.datatype.UTF-8"
            return item
        }
        
        metadata.append(createMetadataItem(identifier: .commonIdentifierTitle, value: track.trackName))
        metadata.append(createMetadataItem(identifier: .commonIdentifierArtist, value: track.artistName))
        
        if let albumName = track.collectionName {
            metadata.append(createMetadataItem(identifier: .commonIdentifierAlbumName, value: albumName))
        }
        
        if let coverURL = track.coverURL {
            do {
                let (coverData, _) = try await URLSession.shared.data(from: coverURL)
                let item = AVMutableMetadataItem()
                item.identifier = .commonIdentifierArtwork
                item.value = coverData as NSData
                item.dataType = "com.apple.metadata.datatype.JPEG"
                metadata.append(item)
            } catch {
                print("Lỗi tải ảnh bìa: \(error)")
            }
        }
        
        exportSession.metadata = metadata
        exportSession.outputFileType = .m4a
        exportSession.outputURL = destinationURL
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        await exportSession.export()
        
        if exportSession.status != .completed {
            throw AudioDownloadError.embeddingFailed
        }
    }
}
