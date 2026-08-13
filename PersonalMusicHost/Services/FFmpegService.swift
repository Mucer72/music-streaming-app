//
//  FFmpegService.swift
//  PersonalMusicHost
//

import Foundation

enum FFmpegError: LocalizedError {
    case conversionFailed(String)
    case notInstalled
    
    var errorDescription: String? {
        switch self {
        case .conversionFailed(let msg): return msg
        case .notInstalled: return "FFmpeg is not installed at /opt/homebrew/bin/ffmpeg"
        }
    }
}

class FFmpegService {
    static let shared = FFmpegService()
    
    // Đường dẫn tĩnh của ffmpeg và ffprobe cài qua Homebrew trên Apple Silicon
    private let ffmpegPath = "/opt/homebrew/bin/ffmpeg"
    private let ffprobePath = "/opt/homebrew/bin/ffprobe"
    
    private func checkFFmpegInstalled() -> Bool {
        return FileManager.default.fileExists(atPath: ffmpegPath)
    }
    
    /// Chuyển đổi bất kỳ định dạng âm thanh nào (vd: .dsf, .ape) sang .wav (PCM 16-bit 44.1kHz)
    func decodeToWav(sourceURL: URL) async throws -> URL {
        guard checkFFmpegInstalled() else {
            throw FFmpegError.notInstalled
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = sourceURL.deletingPathExtension().lastPathComponent
        let outputURL = tempDir.appendingPathComponent("\(fileName)_ffmpeg_temp.wav")
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpegPath)
            process.arguments = [
                "-y", // Cho phép ghi đè tự động
                "-i", sourceURL.path,
                "-ar", "44100",
                "-ac", "2",
                "-c:a", "pcm_s16le",
                outputURL.path
            ]
            
            let pipe = Pipe()
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 {
                    continuation.resume(returning: outputURL)
                } else {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errorStr = String(data: data, encoding: .utf8) ?? "Unknown Error"
                    continuation.resume(throwing: FFmpegError.conversionFailed(errorStr))
                }
            } catch {
                continuation.resume(throwing: FFmpegError.conversionFailed(error.localizedDescription))
            }
        }
    }
    
    /// Trích xuất metadata từ file không hỗ trợ bản địa bằng FFprobe
    func extractMetadata(from url: URL) async throws -> AudioTrack {
        var track = AudioTrack(sourceURL: url)
        track.title = url.deletingPathExtension().lastPathComponent
        
        guard FileManager.default.fileExists(atPath: ffprobePath) else {
            return track
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffprobePath)
            process.arguments = [
                "-v", "quiet",
                "-print_format", "json",
                "-show_format",
                url.path
            ]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let format = json["format"] as? [String: Any] {
                        
                        if let durationStr = format["duration"] as? String, let duration = Double(durationStr) {
                            track.duration = duration
                        }
                        
                        if let tags = format["tags"] as? [String: String] {
                            for (key, value) in tags {
                                let lowerKey = key.lowercased()
                                if lowerKey == "title" { track.title = value }
                                if lowerKey == "artist" { track.artist = value }
                                if lowerKey == "album" { track.albumName = value }
                                if lowerKey == "track" {
                                    if let numStr = value.components(separatedBy: "/").first, let num = Int(numStr) {
                                        track.trackNumber = num
                                    }
                                }
                                if lowerKey == "date" || lowerKey == "year" {
                                    if let year = Int(value.prefix(4)) {
                                        track.releaseYear = year
                                    }
                                }
                            }
                        }
                    }
                }
                continuation.resume(returning: track)
            } catch {
                continuation.resume(returning: track)
            }
        }
    }
}
