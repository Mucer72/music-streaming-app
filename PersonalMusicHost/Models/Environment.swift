//
//  Environment.swift
//  PersonalMusicHost
//
//  Created by TwentyMikeyOne on 25/6/26.
//

import Foundation

public enum AppEnvironment {
    // Định nghĩa các lỗi có thể xảy ra khi đọc file config
    enum Keys {
        static let googleClientID = "GOOGLE_CLIENT_ID"
        static let driveRootFolderName = "DRIVE_ROOT_FOLDER_NAME"
    }
    
    // Đọc Client ID một cách an toàn
    static let googleClientID: String = {
        // 1. Thử đọc từ Info.plist (nếu đã được cấu hình từ xcconfig)
        if let clientIDProperty = Bundle.main.object(forInfoDictionaryKey: Keys.googleClientID) as? String,
           !clientIDProperty.isEmpty,
           !clientIDProperty.hasPrefix("$(") {
            return clientIDProperty
        }
        
        // 2. Fallback: Đọc trực tiếp từ tệp GoogleService-Info.plist trong Bundle
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path),
           let clientID = dict["CLIENT_ID"] as? String,
           !clientID.isEmpty {
            return clientID
        }
        
        fatalError("❌ Không tìm thấy GOOGLE_CLIENT_ID trong Info.plist hoặc GoogleService-Info.plist")
    }()
    
    // Đọc tên thư mục gốc, nếu không có trong file config thì mặc định là "music stream storage"
    static let driveRootFolderName: String = {
        guard let folderName = Bundle.main.object(forInfoDictionaryKey: Keys.driveRootFolderName) as? String else {
            return "music stream storage"
        }
        return folderName
    }()
    
    // Danh sách các định dạng file âm thanh được ứng dụng hỗ trợ
    // Có thể dễ dàng thêm mới các định dạng Audiophile tại đây
    static let supportedAudioExtensions: [String] = [
        "m4a", "flac", "mp3", "wav", "alac", "aiff", 
        "dsf", "dsd", "dff", "ape", "ogg", "wma", "aac"
    ]
}
