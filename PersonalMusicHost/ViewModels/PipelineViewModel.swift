//
//  PipelineViewModel.swift
//  PersonalMusicHost
//

import Foundation
import SwiftUI
import Combine
import AVFoundation

@MainActor
class PipelineViewModel: ObservableObject {
    
    // Chế độ hoạt động
    @Published var isAlbumMode: Bool = false
    @Published var coverImageURL: URL?
    
    @Published var tracks: [AudioTrack] = []
    @Published var isProcessing: Bool = false
    
    // Giao diện Tiến trình & Logs
    @Published var progress: Double = 0.0
    @Published var currentTaskName: String = ""
    @Published var logs: [String] = []
    
    // Quản lý thông tin Album chung
    @Published var globalAlbumName: String = ""
    @Published var globalArtistName: String = ""
    @Published var globalReleaseYear: String = ""
    @Published var globalDescription: String = ""
    @Published var globalGenreId: String = ""
    
    // Thể loại tải từ Firebase
    @Published var availableGenres: [GenreRecord] = []
    
    init() {
        Task {
            try? await FirebaseDatabaseService.shared.seedDefaultGenresIfEmpty()
            if let genres = try? await FirebaseDatabaseService.shared.fetchGenres() {
                await MainActor.run {
                    self.availableGenres = genres
                }
            }
        }
    }
    
    func applyGlobalAlbumInfo() {
        for i in 0..<tracks.count {
            if !globalAlbumName.isEmpty { tracks[i].albumName = globalAlbumName }
            if !globalArtistName.isEmpty { tracks[i].artist = globalArtistName }
            if let year = Int(globalReleaseYear) { tracks[i].releaseYear = year }
            if !globalDescription.isEmpty { tracks[i].description = globalDescription }
            if !globalGenreId.isEmpty { tracks[i].genreId = globalGenreId }
        }
    }
    
    // Thêm biến lưu trữ đường dẫn file âm thanh gốc của toàn bộ Album
    @Published var albumSourceAudioURL: URL?
    
    @Published var outputDirectory: URL?
    @Published var isAACSelected: Bool = true
    @Published var isALACSelected: Bool = false
    @Published var saveToLocal: Bool = true
    @Published var uploadToDrive: Bool = false
    @Published var isPublic: Bool = true // Cho phép xuất bản thành nhạc public mặc định
    
    private let fileService = LocalFileService()
    private let audioService = AudioPipelineService()
    private let driveService = GoogleDriveService.shared
    
    func addLog(_ message: String) {
        let timeString = Date().formatted(date: .omitted, time: .standard)
        logs.append("[\(timeString)] \(message)")
        currentTaskName = message
    }
    
    // CHỌN ẢNH BÌA
    func selectCoverImage() {
        if let url = fileService.selectImageFile() {
            self.coverImageURL = url
            addLog("🖼️ Đã chọn ảnh bìa: \(url.lastPathComponent)")
        }
    }
    
    // 1. CHỌN NHIỀU FILE ÂM THANH CHO ALBUM HOẶC BÀI LẺ
    func selectFiles() async {
        if isAlbumMode {
            addLog("📁 Vui lòng chọn Thư mục chứa Album...")
            guard let folderURL = fileService.selectFolder() else { return }
            
            addLog("🔍 Đang quét thư mục: \(folderURL.lastPathComponent)")
            let scanResult = fileService.scanFolderForAlbum(at: folderURL)
            
            guard !scanResult.audioFiles.isEmpty else {
                addLog("⚠️ Không tìm thấy file âm thanh nào trong thư mục. Huỷ nạp Album.")
                return
            }
            
            // Nếu có ảnh cover, tự động set
            if let coverURL = scanResult.coverImage {
                self.coverImageURL = coverURL
                addLog("🖼️ Đã tìm thấy ảnh bìa: \(coverURL.lastPathComponent)")
            }
            
            if let cueURL = scanResult.cueFile {
                addLog("📄 Đã tìm thấy file .cue, tiến hành parse...")
                await parseCueFile(cueURL: cueURL, selectedAudioURLs: scanResult.audioFiles)
            } else {
                addLog("📂 Tải Album từ \(scanResult.audioFiles.count) file rời...")
                tracks.removeAll()
                
                var counter = 1
                for url in scanResult.audioFiles {
                    var newTrack = AudioTrack(sourceURL: url)
                    do {
                        newTrack = try await audioService.extractMetadata(from: url)
                    } catch {
                        // Bỏ qua lỗi metadata nếu có
                    }
                    
                    // Nếu không có trackNumber từ metadata, gán số thứ tự duyệt file
                    if newTrack.trackNumber == 0 {
                        newTrack.trackNumber = counter
                    }
                    counter += 1
                    
                    tracks.append(newTrack)
                }
                
                // Nếu không có tên album từ metadata, lấy tên thư mục làm tên album mặc định
                let defaultAlbumName = folderURL.lastPathComponent
                for i in 0..<tracks.count {
                    if tracks[i].albumName.isEmpty {
                        tracks[i].albumName = defaultAlbumName
                    }
                }
                
                // Sắp xếp lại danh sách theo trackNumber
                tracks.sort { $0.trackNumber < $1.trackNumber }
            }
            
            // Tự động điền thông tin Album chung từ track đầu tiên
            if let firstTrack = tracks.first {
                globalAlbumName = firstTrack.albumName.isEmpty ? folderURL.lastPathComponent : firstTrack.albumName
                globalArtistName = firstTrack.artist
                if let year = firstTrack.releaseYear {
                    globalReleaseYear = String(year)
                } else {
                    globalReleaseYear = ""
                }
            }
            
            addLog("✅ Đã nạp xong \(tracks.count) bài hát vào hàng đợi.")
            
        } else {
            // Chế độ bài lẻ giữ nguyên...
            let urls = fileService.selectAudioFiles()
            guard !urls.isEmpty else { return }
            addLog("📂 Đang tải dữ liệu \(urls.count) file...")
            Task {
                var counter = 1
                for url in urls {
                    var newTrack = AudioTrack(sourceURL: url)
                    if let trackData = try? await audioService.extractMetadata(from: url) {
                        newTrack = trackData
                    }
                    if newTrack.trackNumber == 0 {
                        newTrack.trackNumber = counter
                    }
                    tracks.append(newTrack)
                    counter += 1
                }
            }
        }
    }
    
    // 2. BỘ PHÂN TÍCH CUE ĐA FILE VÀ TRÍCH XUẤT TIMESTAMPS
    private func parseCueFile(cueURL: URL, selectedAudioURLs: [URL]) async {
        addLog("⚙️ Đang bóc tách cấu trúc đĩa và phân bổ mốc thời gian...")
        do {
            let content = try String(contentsOf: cueURL, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            
            var currentAlbum = "Unknown Album"
            var currentArtist = "Unknown Artist"
            var trackCounter = 1
            
            // Chỉ mục quản lý file âm thanh nguồn (0: Side A, 1: Side B, 2: Side C, 3: Side D)
            var currentFileIndex = -1
            
            tracks.removeAll()
            
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                
                // Phát hiện dòng chuyển đổi mặt đĩa / tệp âm thanh nguồn
                if trimmed.hasPrefix("FILE") {
                    currentFileIndex += 1
                    continue
                }
                
                if trimmed.hasPrefix("PERFORMER") && tracks.isEmpty {
                    currentArtist = extractCueQuotes(trimmed)
                } else if trimmed.hasPrefix("TITLE") && tracks.isEmpty {
                    currentAlbum = extractCueQuotes(trimmed)
                } else if trimmed.hasPrefix("TRACK") && trimmed.contains("AUDIO") {
                    
                    // Kiểm tra an toàn để tránh tràn mảng nếu số lượng file chọn ít hơn cấu trúc CUE
                    guard let fallbackURL = selectedAudioURLs.first else {
                        addLog("❌ Lỗi: Không có file âm thanh nào được chọn để ánh xạ!")
                        continue
                    }
                    let fileURL = (currentFileIndex < selectedAudioURLs.count && currentFileIndex >= 0)
                    ? selectedAudioURLs[currentFileIndex]
                    : fallbackURL
                    
                    var newTrack = AudioTrack(sourceURL: fileURL) // Đã map đúng file âm thanh của từng Side!
                    newTrack.albumName = currentAlbum
                    newTrack.artist = currentArtist
                    newTrack.trackNumber = trackCounter
                    
                    tracks.append(newTrack)
                    trackCounter += 1
                    
                } else if trimmed.hasPrefix("TITLE") && !tracks.isEmpty {
                    tracks[tracks.count - 1].title = extractCueQuotes(trimmed)
                } else if trimmed.hasPrefix("INDEX 01") && !tracks.isEmpty {
                    
                    // SỬA TẠI ĐÂY: Chặt chuỗi bằng khoảng trắng và lấy phần tử cuối cùng
                    if let timestamp = trimmed.components(separatedBy: .whitespaces).last {
                        let seconds = parseCueTimestampToSeconds(timestamp)
                        tracks[tracks.count - 1].startTime = seconds
                        
                        // Tính toán thời lượng bài hát trước đó (nếu cùng chung một mặt đĩa)
                        if tracks.count > 1 {
                            let prevIdx = tracks.count - 2
                            if tracks[prevIdx].sourceURL == tracks[tracks.count - 1].sourceURL {
                                tracks[prevIdx].duration = seconds - tracks[prevIdx].startTime
                            }
                        }
                    }
                }
            }
            
            // XỬ LÝ ĐẶC BIỆT: Tính thời lượng cho các bài cuối cùng của mỗi mặt đĩa
            for i in 0..<tracks.count {
                if tracks[i].duration == 0.0 {
                    // Mượn AVURLAsset đọc độ dài tổng của file lớn để trừ đi mốc bắt đầu
                    let asset = AVURLAsset(url: tracks[i].sourceURL)
                    let totalSeconds = await CMTimeGetSeconds(try asset.load(.duration))
                    tracks[i].duration = totalSeconds - tracks[i].startTime
                }
            }
            
            addLog("✅ Nạp hoàn tất \(tracks.count) bài hát. Đã đồng bộ phân phối đĩa nguồn.")
        } catch {
            addLog("❌ Lỗi cấu trúc file CUE: \(error.localizedDescription)")
        }
    }
    
    // Hàm phụ trợ chuyển đổi MM:SS:FF sang giây
    private func parseCueTimestampToSeconds(_ timestamp: String) -> Double {
        // Dọn sạch mọi khoảng trắng thừa thãi có thể bám vào chuỗi
        let cleanTimestamp = timestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = cleanTimestamp.components(separatedBy: ":")
        
        guard components.count == 3,
              let minutes = Double(components[0]),
              let seconds = Double(components[1]),
              let frames = Double(components[2]) else { return 0.0 }
        
        // 1 giây chuẩn CD Audio gồm 75 frames
        return (minutes * 60.0) + seconds + (frames / 75.0)
    }
    
    func extractCueQuotes(_ line: String) -> String {
        let parts = line.components(separatedBy: "\"")
        return parts.count > 1 ? parts[1] : line
    }
    
    func selectOutputDirectory() {
        if let url = fileService.selectOutputDirectory() {
            outputDirectory = url
            addLog("📁 Đã chọn Workspace: \(url.lastPathComponent)")
        }
    }
    
    func startPipeline() {
            print("DEBUG: Nút đã được bấm! isProcessing ban đầu: \(isProcessing), số lượng track: \(tracks.count)")
            guard !tracks.isEmpty else { return }
            let workingDir = saveToLocal ? (outputDirectory ?? FileManager.default.temporaryDirectory) : FileManager.default.temporaryDirectory
            
            var formatsToProcess: [OutputFormat] = []
            if isAACSelected { formatsToProcess.append(.aac) }
            if isALACSelected { formatsToProcess.append(.alac) }
            
            isProcessing = true
            progress = 0.0
            logs.removeAll()
            addLog("🚀 Khởi động Pipeline...")
            
            Task {
                defer {
                    Task { @MainActor in self.isProcessing = false }
                }
                var uploadedCoverDriveID = ""
                
                // 1. TẢI ẢNH BÌA LÊN GOOGLE DRIVE (Giữ nguyên logic cũ)
                if let coverURL = coverImageURL, uploadToDrive {
                    addLog("🖼️ Đang đẩy ảnh bìa lên Drive...")
                    do {
                        let rootID = try await driveService.getOrCreateFolder(name: AppEnvironment.driveRootFolderName)
                        let coversFolderID = try await driveService.getOrCreateFolder(name: "covers", parentID: rootID)
                        uploadedCoverDriveID = try await driveService.uploadImageFile(fileURL: coverURL, folderID: coversFolderID)
                        try await driveService.setPublicPermission(fileID: uploadedCoverDriveID)
                        addLog("✅ Đã lưu ảnh bìa thành công vào thư mục 'covers'.")
                    } catch {
                        addLog("⚠️ Lỗi upload ảnh bìa: \(error.localizedDescription)")
                    }
                }
                
                // 🔥 2. TẠO ALBUM TRÊN FIRESTORE (Chỉ chèn thêm đoạn này)
                var generatedAlbumId: String? = nil
                
                if uploadToDrive, isAlbumMode, let uid = FirebaseAuthService.shared.currentUID, let firstTrack = tracks.first {
                    addLog("💿 Chế độ Album: Đang khởi tạo thông tin Album trên Database...")
                    let albumRecord = AlbumRecord(
                        id: nil,
                        title: firstTrack.albumName.isEmpty ? "Unknown Album" : firstTrack.albumName,
                        artist: firstTrack.artist.isEmpty ? "Unknown Artist" : firstTrack.artist,
                        releaseYear: Int(globalReleaseYear) ?? 2026,
                        description: globalDescription.isEmpty ? nil : globalDescription,
                        totalTracks: tracks.count,
                        coverDriveID: uploadedCoverDriveID,
                        genreId: globalGenreId.isEmpty ? nil : globalGenreId,
                        contributor: uid,
                        isPublic: self.isPublic,
                        createdAt: nil
                    )
                    
                    do {
                        generatedAlbumId = try await FirebaseDatabaseService.shared.saveAlbum(albumRecord)
                        addLog("✅ Khởi tạo Album thành công ID: \(generatedAlbumId ?? "")")
                    } catch {
                        addLog("❌ Lỗi đồng bộ cấu trúc Album: \(error.localizedDescription)")
                    }
                }
                
                // 3. VÒNG LẶP XỬ LÝ VÀ PHÂN TÁCH BÀI HÁT (Giữ nguyên 100% logic cũ)
                let totalSteps = tracks.count * formatsToProcess.count
                var completedSteps = 0
                
                for index in 0..<tracks.count {
                    let track = tracks[index]
                    addLog("⏳ Xử lý bài \(index + 1)/\(tracks.count): \(track.title)")
                    
                    do {
                        for format in formatsToProcess {
                            let outputURL = try await audioService.convert(track: track, format: format, outputDir: workingDir)
                            
                            if saveToLocal {
                                if format == .aac { tracks[index].localAAC_URL = outputURL }
                                else { tracks[index].localALAC_URL = outputURL }
                            }
                            
                            if uploadToDrive {
                                let fileID = try await uploadToCloud(localURL: outputURL, format: format)
                                if format == .aac { tracks[index].driveAAC_ID = fileID }
                                else { tracks[index].driveALAC_ID = fileID }
                            }
                            
                            completedSteps += 1
                            progress = Double(completedSteps) / Double(totalSteps)
                        }
                        
                        if uploadToDrive, let uid = FirebaseAuthService.shared.currentUID {
                            addLog("📝 Đồng bộ Database...")
                            let record = TrackRecord(
                                id: nil,
                                title: tracks[index].title,
                                artist: tracks[index].artist,
                                duration: tracks[index].duration,
                                // 🔥 Chỉ thay đổi đúng dòng này để gán ID Album
                                albumId: isAlbumMode ? generatedAlbumId : (tracks[index].albumName.isEmpty ? nil : tracks[index].albumName),
                                trackNumber: tracks[index].trackNumber,
                                releaseYear: tracks[index].releaseYear,
                                description: tracks[index].description,
                                streamCount: 0,
                                coverDriveID: uploadedCoverDriveID.isEmpty ? nil : uploadedCoverDriveID,
                                genreId: tracks[index].genreId,
                                contributor: uid,
                                isPublic: self.isPublic,
                                googleDriveALACID: tracks[index].driveALAC_ID,
                                googleDriveAACID: tracks[index].driveAAC_ID,
                                createdAt: nil
                            )
                            try await FirebaseDatabaseService.shared.saveTrack(record)
                        }
                        
                        if !saveToLocal {
                            if let aac = tracks[index].localAAC_URL { fileService.removeFileIfExists(at: aac) }
                            if let alac = tracks[index].localALAC_URL { fileService.removeFileIfExists(at: alac) }
                        }
                    } catch {
                        addLog("❌ Lỗi: \(error.localizedDescription)")
                        continue
                    }
                }
                await MainActor.run {
                    progress = 1.0
                    addLog("🎉 PIPELINE HOÀN TẤT!")
                    NotificationCenter.default.post(name: .init("LibraryNeedsRefresh"), object: nil)
                }
            }
        }
    
    func uploadToCloud(localURL: URL, format: OutputFormat) async throws -> String {
        let rootFolderName = AppEnvironment.driveRootFolderName
        let rootFolderID = try await driveService.getOrCreateFolder(name: rootFolderName)
        let subFolderName = (format == .aac) ? "fine quality" : "high quality"
        let subFolderID = try await driveService.getOrCreateFolder(name: subFolderName, parentID: rootFolderID)
        
        let fileID = try await driveService.uploadAudioFile(fileURL: localURL, folderID: subFolderID)
        try await driveService.setPublicPermission(fileID: fileID)
        return fileID
    }
}
