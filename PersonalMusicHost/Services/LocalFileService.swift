//
//  LocalFileService.swift
//  PersonalMusicHost
//
//  Created by TwentyMikeyOne on 24/6/26.
//

import AppKit
import UniformTypeIdentifiers

class LocalFileService {
    
    func selectAudioFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType.audio]
        
        if panel.runModal() == .OK {
            return panel.urls
        }
        return []
    }
    
    func selectFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Select Album Folder"
        
        if panel.runModal() == .OK {
            return panel.url
        }
        return nil
    }
    
    // Quét thư mục để tìm file nhạc, file .cue (nếu có), và file hình ảnh (nếu có)
    func scanFolderForAlbum(at url: URL) -> (audioFiles: [URL], cueFile: URL?, coverImage: URL?) {
        var audioFiles: [URL] = []
        var cueFile: URL? = nil
        var coverImage: URL? = nil
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            
            for fileURL in contents {
                let ext = fileURL.pathExtension.lowercased()
                
                // Audio files
                if let type = try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType, type.conforms(to: .audio) {
                    audioFiles.append(fileURL)
                } else if AppEnvironment.supportedAudioExtensions.contains(ext) {
                    audioFiles.append(fileURL)
                }
                
                // Cue file
                else if ext == "cue" {
                    cueFile = fileURL
                }
                
                // Image file
                else if ["jpg", "jpeg", "png"].contains(ext) {
                    if coverImage == nil { // Lấy hình đầu tiên tìm thấy
                        coverImage = fileURL
                    } else {
                        // Ưu tiên hình có tên cover, folder, front
                        let name = fileURL.deletingPathExtension().lastPathComponent.lowercased()
                        if ["cover", "folder", "front", "albumart"].contains(name) {
                            coverImage = fileURL
                        }
                    }
                }
            }
        } catch {
            print("Lỗi quét thư mục: \(error)")
        }
        
        // Sắp xếp file audio theo tên alphabet
        audioFiles.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        
        return (audioFiles, cueFile, coverImage)
    }
    
    func selectOutputDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Select Workspace"
        
        if panel.runModal() == .OK {
            return panel.url
        }
        return nil
    }
    
    func selectImageFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Select Cover Art for Album"
        panel.showsHiddenFiles = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        
        // Ép bộ lọc chỉ hiển thị file ảnh định dạng JPG hoặc PNG
        panel.allowedContentTypes = [.jpeg, .png]
        
        if panel.runModal() == .OK {
            return panel.url
        }
        return nil
    }
    
    func selectCueFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        // Restrict to only .cue files using UTType tag-based initializer (macOS 12+)
        if let cueType = UTType(tag: "cue", tagClass: .filenameExtension, conformingTo: nil) {
            panel.allowedContentTypes = [cueType]
        } else if let cueType = UTType(filenameExtension: "cue") {
            panel.allowedContentTypes = [cueType]
        } else {
            // As a last resort, set to an empty array to avoid deprecated APIs; panel will still allow manual typing but not filter.
            panel.allowedContentTypes = []
        }

        if panel.runModal() == .OK {
            return panel.url
        }
        return nil
    }
    
    func removeFileIfExists(at url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

