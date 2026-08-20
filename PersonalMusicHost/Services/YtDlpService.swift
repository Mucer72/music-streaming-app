//
//  YtDlpService.swift
//  PersonalMusicHost
//
//  Quản lý trích xuất và tải stream âm thanh YouTube / YT Music qua yt-dlp cục bộ.
//  Chạy 100% Native trên macOS với IP nhà mạng thực tế, không bao giờ bị chặn Botguard.
//

import Foundation

enum YtDlpError: LocalizedError {
    case notInstalled
    case executionFailed(String)
    case streamNotFound

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "yt-dlp chưa được cài đặt tại /opt/homebrew/bin/yt-dlp hoặc /usr/local/bin/yt-dlp"
        case .executionFailed(let msg):
            return msg
        case .streamNotFound:
            return "Không tìm thấy direct stream URL từ yt-dlp"
        }
    }
}

final class YtDlpService {
    static let shared = YtDlpService()

    private let ytDlpPaths = [
        "/opt/homebrew/bin/yt-dlp",
        "/usr/local/bin/yt-dlp",
        "/usr/bin/yt-dlp"
    ]

    var isInstalled: Bool {
        return executablePath != nil
    }

    private var executablePath: String? {
        for path in ytDlpPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Khởi tạo environment đầy đủ để Process() tìm thấy Python 3.10+, deno và ffmpeg
    private var processEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let customPaths = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let existing = env["PATH"] {
            env["PATH"] = "\(customPaths):\(existing)"
        } else {
            env["PATH"] = customPaths
        }
        env["HOME"] = NSHomeDirectory()
        return env
    }

    /// Tải file audio trực tiếp (.m4a) về đĩa thông qua yt-dlp (đảm bảo chuẩn AAC/M4A playable trên Apple)
    func downloadAudio(videoId: String, destinationURL: URL, directURL: String? = nil) async throws -> URL {
        #if os(macOS)
        guard let binPath = executablePath else {
            throw YtDlpError.notInstalled
        }

        let targetURL = directURL ?? "https://www.youtube.com/watch?v=\(videoId)"
        let tempDir = FileManager.default.temporaryDirectory
        let outTemplate = tempDir.appendingPathComponent("\(videoId)_temp.%(ext)s").path
        let env = self.processEnvironment

        return try await Task.detached(priority: .userInitiated) { () -> URL in
            return try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binPath)
                process.environment = env
                process.arguments = [
                    "-f", "bestaudio[ext=m4a]/bestaudio/best",
                    "-x",
                    "--audio-format", "m4a",
                    "--audio-quality", "0",
                    "--no-warnings",
                    "--quiet",
                    "-o", outTemplate,
                    targetURL
                ]

                let errPipe = Pipe()
                let outPipe = Pipe()
                process.standardError = errPipe
                process.standardOutput = outPipe

                do {
                    try process.run()

                    // Đọc toàn bộ output và error buffer trước khi waitUntilExit() để tránh Pipe Deadlock (buffer > 64KB)
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let _ = outPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        // Tìm file vừa tải (ưu tiên .m4a đã được extract)
                        let possibleExtensions = ["m4a", "mp4", "webm", "opus", "mp3"]
                        var foundURL: URL?

                        for ext in possibleExtensions {
                            let candidatePath = tempDir.appendingPathComponent("\(videoId)_temp.\(ext)")
                            if FileManager.default.fileExists(atPath: candidatePath.path) {
                                foundURL = candidatePath
                                break
                            }
                        }

                        guard let finalDownloaded = foundURL else {
                            continuation.resume(throwing: YtDlpError.streamNotFound)
                            return
                        }

                        // Di chuyển tới destinationURL
                        try? FileManager.default.removeItem(at: destinationURL)
                        try FileManager.default.moveItem(at: finalDownloaded, to: destinationURL)
                        continuation.resume(returning: destinationURL)
                    } else {
                        let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown yt-dlp error"
                        continuation.resume(throwing: YtDlpError.executionFailed(errMsg.isEmpty ? "yt-dlp thoát với mã lỗi \(process.terminationStatus)" : errMsg))
                    }
                } catch {
                    continuation.resume(throwing: YtDlpError.executionFailed(error.localizedDescription))
                }
            }
        }.value
        #else
        throw YtDlpError.notInstalled
        #endif
    }

    /// Lấy metadata trực tiếp từ link bất kỳ thông qua yt-dlp --dump-json (Không bị deadlock buffer)
    func extractMetadata(from urlString: String) async throws -> [String: Any] {
        #if os(macOS)
        guard let binPath = executablePath else {
            throw YtDlpError.notInstalled
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binPath)
            process.environment = self.processEnvironment
            process.arguments = [
                "--dump-json",
                "--no-warnings",
                "--quiet",
                urlString
            ]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()

                // Đọc toàn bộ output trước khi chờ thoát để tránh đầy 64KB pipe buffer
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        continuation.resume(returning: json)
                    } else {
                        continuation.resume(throwing: YtDlpError.executionFailed("Không thể parse JSON từ yt-dlp output"))
                    }
                } else {
                    let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown yt-dlp error"
                    continuation.resume(throwing: YtDlpError.executionFailed(errMsg.isEmpty ? "yt-dlp extract metadata thất bại (\(process.terminationStatus))" : errMsg))
                }
            } catch {
                continuation.resume(throwing: YtDlpError.executionFailed(error.localizedDescription))
            }
        }
        #else
        throw YtDlpError.notInstalled
        #endif
    }

    /// Trích xuất direct audio stream URL (.m4a/opus) nhanh chóng cho Preview phát nhạc
    func extractStreamURL(videoId: String) async throws -> URL {
        #if os(macOS)
        guard let binPath = executablePath else {
            throw YtDlpError.notInstalled
        }

        let youtubeURL = "https://www.youtube.com/watch?v=\(videoId)"
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binPath)
            process.environment = self.processEnvironment
            process.arguments = [
                "-g", "-f", "bestaudio[ext=m4a]/bestaudio/best",
                "--no-warnings",
                youtubeURL
            ]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()

                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       let url = URL(string: output) {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: YtDlpError.streamNotFound)
                    }
                } else {
                    let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown yt-dlp error"
                    continuation.resume(throwing: YtDlpError.executionFailed(errMsg.isEmpty ? "yt-dlp stream lookup thất bại" : errMsg))
                }
            } catch {
                continuation.resume(throwing: YtDlpError.executionFailed(error.localizedDescription))
            }
        }
        #else
        throw YtDlpError.notInstalled
        #endif
    }
}
