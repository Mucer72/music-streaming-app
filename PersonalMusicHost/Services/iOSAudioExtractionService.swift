//
//  iOSAudioExtractionService.swift
//  PersonalMusicHost
//
//  Quản lý trích xuất và tải stream âm thanh trên iOS / iPadOS bằng On-Device Python Engine (YoutubeDL-iOS + FFmpeg-iOS).
//  Chạy 100% cục bộ trên IP mạng thiết bị, không bao giờ bị chặn Botguard từ Data Center.
//

#if os(iOS)
import Foundation
import PythonSupport
import PythonKit
import YoutubeDL

enum iOSAudioExtractionError: LocalizedError {
    case runtimeNotReady
    case extractionFailed(String)
    case streamNotFound
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .runtimeNotReady:
            return "Python Engine chưa sẵn sàng trên iOS."
        case .extractionFailed(let msg):
            return "Lỗi trích xuất Python: \(msg)"
        case .streamNotFound:
            return "Không tìm thấy URL âm thanh phù hợp từ video."
        case .downloadFailed(let msg):
            return "Lỗi tải âm thanh trên iOS: \(msg)"
        }
    }
}

final class iOSAudioExtractionService {
    static let shared = iOSAudioExtractionService()

    private let youtubeDL = YoutubeDL()
    private var isInitialized = false

    /// Đảm bảo Python module (yt_dlp) đã được tải về và khởi tạo sẵn sàng
    func initializeIfNeeded() async throws {
        if isInitialized && FileManager.default.fileExists(atPath: YoutubeDL.pythonModuleURL.path) {
            return
        }

        // Tải yt-dlp module nếu chưa có trong thư mục Application Support
        if !FileManager.default.fileExists(atPath: YoutubeDL.pythonModuleURL.path) {
            print("⏳ [iOSAudioExtractionService] Đang tải yt-dlp module mới nhất về thiết bị...")
            try await YoutubeDL.downloadPythonModule()
            print("✅ [iOSAudioExtractionService] Tải yt-dlp module hoàn tất!")
        }

        // Khởi tạo Python runtime
        PythonSupport.initialize()
        isInitialized = true
        print("✅ [iOSAudioExtractionService] Python Engine đã sẵn sàng trên iOS.")
    }

    /// Trích xuất direct stream URL (.m4a/aac) và tải về destinationURL trên iOS
    func extractAndDownloadAudio(
        videoId: String,
        destinationURL: URL,
        directURL: String? = nil,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> URL {
        guard let targetURL = URL(string: directURL ?? "https://www.youtube.com/watch?v=\(videoId)") else {
            throw iOSAudioExtractionError.streamNotFound
        }

        return try await Task.detached(priority: .userInitiated) { () -> URL in
            try await self.initializeIfNeeded()
            
            do {
                let (formats, _) = try await self.youtubeDL.extractInfo(url: targetURL)

                // Ưu tiên chọn stream audio m4a/aac
                let audioFormat = formats.first(where: { $0.isAudioOnly && $0.ext == "m4a" })
                    ?? formats.first(where: { $0.isAudioOnly })
                    ?? formats.first

                guard let selectedFormat = audioFormat,
                      let request = selectedFormat.urlRequest else {
                    throw iOSAudioExtractionError.streamNotFound
                }

                print("🎵 [iOSAudioExtractionService] Bắt đầu tải stream: \(selectedFormat.ext) (abr: \(selectedFormat.abr ?? 0))")

                let finalURL: URL
                do {
                    // Cố gắng tải phân mảnh tốc độ cao trước
                    finalURL = try await ChunkedDownloader.shared.download(
                        request: request,
                        destinationURL: destinationURL,
                        onProgress: onProgress
                    )
                } catch {
                    print("⚠️ [iOSAudioExtractionService] Tải phân mảnh thất bại: \(error.localizedDescription). Chuyển sang tải truyền thống...")
                    // Fallback: Tải nguyên khối truyền thống
                    finalURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                        let delegate = IOSDownloadDelegate(
                            destinationURL: destinationURL,
                            onProgress: onProgress,
                            continuation: continuation
                        )
                        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
                        let task = session.downloadTask(with: request)
                        task.resume()
                    }
                }

                print("✅ [iOSAudioExtractionService] Tải thành công file audio về: \(finalURL.path)")
                return finalURL
            } catch let error as iOSAudioExtractionError {
                throw error
            } catch {
                throw iOSAudioExtractionError.downloadFailed(error.localizedDescription)
            }
        }.value
    }
}

// MARK: - Fallback Download Delegate
class IOSDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let destinationURL: URL
    private let onProgress: ((Double) -> Void)?
    private let continuation: CheckedContinuation<URL, Error>
    
    init(destinationURL: URL, onProgress: ((Double) -> Void)?, continuation: CheckedContinuation<URL, Error>) {
        self.destinationURL = destinationURL
        self.onProgress = onProgress
        self.continuation = continuation
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            onProgress?(progress)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: location, to: destinationURL)
            session.finishTasksAndInvalidate()
            continuation.resume(returning: destinationURL)
        } catch {
            session.finishTasksAndInvalidate()
            continuation.resume(throwing: error)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            session.finishTasksAndInvalidate()
            continuation.resume(throwing: error)
        }
    }
}
#endif


/// Lỗi do ChunkedDownloader quăng ra
enum ChunkedDownloaderError: Error, LocalizedError {
    case serverDoesNotSupportRange
    case invalidContentLength
    case downloadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .serverDoesNotSupportRange:
            return "Máy chủ không hỗ trợ tải phân mảnh."
        case .invalidContentLength:
            return "Không thể xác định dung lượng file từ máy chủ."
        case .downloadFailed(let msg):
            return "Tải mảnh thất bại: \(msg)"
        }
    }
}

/// Trình tải phân mảnh đa luồng (Multi-threaded Chunked Downloader)
/// Tối ưu hoá để vượt qua cơ chế bóp băng thông của YouTube.
actor ChunkedDownloader {
    
    static let shared = ChunkedDownloader()
    
    // Cấu hình tải
    private let chunkSize: Int64 = 2 * 1024 * 1024 // 2MB mỗi lát cắt
    private let maxConcurrentTasks = 4 // Số kết nối song song
    private let maxRetries = 2
    
    // Theo dõi tiến trình
    private var totalBytes: Int64 = 0
    private var downloadedBytes: Int64 = 0
    
    private init() {}
    
    /// Bắt đầu quá trình phân mảnh và tải file.
    /// Nếu máy chủ không hỗ trợ tải phân mảnh, hàm này sẽ ném lỗi `ChunkedDownloaderError`
    /// để caller có thể fallback sang phương pháp truyền thống.
    func download(
        request: URLRequest,
        destinationURL: URL,
        onProgress: ((Double) -> Void)?
    ) async throws -> URL {
        
        // Reset trạng thái
        self.totalBytes = 0
        self.downloadedBytes = 0
        
        // 1. Kiểm tra dung lượng và khả năng hỗ trợ Range (HEAD request)
        var headRequest = request
        headRequest.httpMethod = "HEAD"
        let (_, response) = try await URLSession.shared.data(for: headRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChunkedDownloaderError.invalidContentLength
        }
        
        // Kiểm tra Accept-Ranges hoặc Content-Length
        let acceptRanges = httpResponse.value(forHTTPHeaderField: "Accept-Ranges")
        let contentLengthStr = httpResponse.value(forHTTPHeaderField: "Content-Length")
        
        // Nếu không có Content-Length, không thể tính toán các khối
        guard let lengthStr = contentLengthStr, let length = Int64(lengthStr), length > 0 else {
            throw ChunkedDownloaderError.invalidContentLength
        }
        
        // YouTube đôi khi không trả về Accept-Ranges trong HEAD nhưng vẫn hỗ trợ. 
        // Tuy nhiên, nếu Content-Length tồn tại, chúng ta sẽ tin tưởng thử Range Request.
        self.totalBytes = length
        
        // Xoá file cũ nếu tồn tại để chuẩn bị ghi file mới
        try? FileManager.default.removeItem(at: destinationURL)
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil, attributes: nil)
        
        let fileHandle = try FileHandle(forWritingTo: destinationURL)
        defer {
            try? fileHandle.close()
        }
        
        // 2. Chia dung lượng thành các đoạn nhỏ (chunks)
        struct Chunk {
            let index: Int
            let startByte: Int64
            let endByte: Int64
        }
        
        var chunks: [Chunk] = []
        var currentStart: Int64 = 0
        var chunkIndex = 0
        
        while currentStart < totalBytes {
            let end = min(currentStart + chunkSize - 1, totalBytes - 1)
            chunks.append(Chunk(index: chunkIndex, startByte: currentStart, endByte: end))
            currentStart = end + 1
            chunkIndex += 1
        }
        
        // Báo cáo 0%
        onProgress?(0.0)
        
        // 3. Tải song song với giới hạn số luồng đồng thời
        // Sử dụng semaphore hoặc kĩ thuật nhóm task để giới hạn maxConcurrentTasks.
        try await withThrowingTaskGroup(of: (Chunk, Data).self) { group in
            var chunksToDownload = chunks
            
            // Hàm trợ giúp để tải 1 chunk (hỗ trợ tự động thử lại)
            func downloadChunk(chunk: Chunk, retriesLeft: Int) async throws -> (Chunk, Data) {
                var chunkRequest = request
                chunkRequest.httpMethod = "GET"
                let rangeHeader = "bytes=\(chunk.startByte)-\(chunk.endByte)"
                chunkRequest.setValue(rangeHeader, forHTTPHeaderField: "Range")
                
                do {
                    let (data, response) = try await URLSession.shared.data(for: chunkRequest)
                    guard let httpRes = response as? HTTPURLResponse, 
                          (200...299).contains(httpRes.statusCode) else {
                        throw ChunkedDownloaderError.downloadFailed("HTTP Status lỗi khi tải mảnh \(chunk.index)")
                    }
                    
                    // Nếu server trả về 200 thay vì 206, server KHÔNG hỗ trợ Range cho GET request.
                    if httpRes.statusCode == 200 && chunk.startByte != 0 {
                        throw ChunkedDownloaderError.serverDoesNotSupportRange
                    }
                    
                    return (chunk, data)
                } catch {
                    if retriesLeft > 0 {
                        print("⚠️ Lỗi tải mảnh \(chunk.index). Thử lại... (\(retriesLeft) lần thử còn lại)")
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                        return try await downloadChunk(chunk: chunk, retriesLeft: retriesLeft - 1)
                    } else {
                        throw error
                    }
                }
            }
            
            // Khởi động tối đa `maxConcurrentTasks` luồng cùng lúc
            for _ in 0..<min(maxConcurrentTasks, chunksToDownload.count) {
                let chunk = chunksToDownload.removeFirst()
                group.addTask {
                    return try await downloadChunk(chunk: chunk, retriesLeft: self.maxRetries)
                }
            }
            
            // Khi 1 luồng xong, nạp luồng tiếp theo và ghi dữ liệu ra đĩa ngay lập tức
            for try await (completedChunk, data) in group {
                // Ghi dữ liệu vào đúng vị trí trong file
                try fileHandle.seek(toOffset: UInt64(completedChunk.startByte))
                fileHandle.write(data)
                
                // Cập nhật tiến độ an toàn
                self.downloadedBytes += Int64(data.count)
                let progress = Double(self.downloadedBytes) / Double(self.totalBytes)
                onProgress?(progress)
                
                // Nếu còn chunk chưa tải, đưa thêm vào group
                if let nextChunk = chunksToDownload.first {
                    chunksToDownload.removeFirst()
                    group.addTask {
                        return try await downloadChunk(chunk: nextChunk, retriesLeft: self.maxRetries)
                    }
                }
            }
        }
        
        // Hoàn tất, trả về URL đã lưu
        return destinationURL
    }
}
