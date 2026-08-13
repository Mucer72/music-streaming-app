//
//  SecureDriveImage.swift
//  PersonalMusicHost
//
//  Created by TwentyMikeyOne on 30/6/26.
//

import SwiftUI
#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

// Bộ nhớ đệm tĩnh lưu trữ hình ảnh đã tải để tránh tải lại nhiều lần
class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, PlatformImage>()
    
    // Giới hạn số lượng file cache để tránh tràn RAM (tuỳ chọn)
    init() {
        cache.countLimit = 100 
    }

    func get(forKey key: String) -> PlatformImage? {
        return cache.object(forKey: key as NSString)
    }

    func set(_ image: PlatformImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}

struct SecureDriveImage: View {
    let fileID: String?
    
    @State private var image: PlatformImage? = nil
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let image = image {
                #if os(macOS)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                #else
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                #endif
            } else if isLoading {
                ProgressView().controlSize(.small)
            } else {
                // Ảnh mặc định khi không có Cover hoặc lỗi
                ZStack {
                    Color.gray.opacity(0.2)
                    Image(systemName: "music.note")
                        .foregroundColor(.gray)
                        .font(.title)
                }
            }
        }
        .task(id: fileID) {
            await loadImage()
        }
    }
    
    @MainActor
    private func loadImage() async {
        guard let fileID = fileID, !fileID.isEmpty else {
            image = nil
            return
        }
        
        // 1. Kiểm tra trong Cache trước khi tải
        if let cachedImage = ImageCache.shared.get(forKey: fileID) {
            self.image = cachedImage
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            guard let url = URL(string: "https://drive.google.com/uc?export=download&id=\(fileID)") else { return }
            
            let request = URLRequest(url: url)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
               let downloadedImage = PlatformImage(data: data) {
                // 2. Lưu vào Cache sau khi tải thành công
                ImageCache.shared.set(downloadedImage, forKey: fileID)
                self.image = downloadedImage
            }
        } catch {
            print("Tải ảnh bìa bị huỷ hoặc lỗi: \(error.localizedDescription)")
        }
    }
}
