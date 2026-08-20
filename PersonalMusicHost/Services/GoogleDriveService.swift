//
//  GoogleDriveService.swift
//  PersonalMusicHost
//
//  Created by TwentyMikeyOne on 24/6/26.
//

import Foundation
import GoogleSignIn
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
import Combine

enum DriveError: LocalizedError {
    case notSignedIn
    case uploadFailed(String)
    case folderCreationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in to Google Drive."
        case .uploadFailed(let msg): return "Upload failed: \(msg)"
        case .folderCreationFailed(let msg): return "Folder creation failed: \(msg)"
        }
    }
}

// Bọc @MainActor vì service này sẽ cập nhật các biến @Published lên giao diện
@MainActor
class GoogleDriveService: ObservableObject {
    // Singleton pattern để gọi từ mọi nơi
    static let shared = GoogleDriveService()
    
    @Published var isSignedIn = false
    @Published var currentUser: GIDGoogleUser?
    
    // Scope cực kỳ quan trọng: Chỉ cho phép đọc/ghi các file do chính app này tạo ra
    private let driveScope = "https://www.googleapis.com/auth/drive.file"
    
    // Khởi tạo cấu hình với Client ID
    func configure(clientID: String) {
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
    }
    
    // Gọi màn hình đăng nhập
    func signIn() async throws {
        #if os(macOS)
        guard let presentingAnchor = NSApplication.shared.windows.first else {
            throw DriveError.notSignedIn
        }
        #else
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let presentingAnchor = windowScene.windows.first?.rootViewController else {
            throw DriveError.notSignedIn
        }
        #endif
        
        // 1. Lấy thông tin từ Google
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presentingAnchor,
            hint: nil,
            additionalScopes: [driveScope]
        )
        
        self.currentUser = result.user
        self.isSignedIn = true
        
        // 2. Trích xuất Token
        guard let idToken = result.user.idToken?.tokenString else {
            throw DriveError.notSignedIn
        }
        let accessToken = result.user.accessToken.tokenString
        
        // 3. Ném Token sang Firebase Auth
        try await FirebaseAuthService.shared.signInWithGoogle(idToken: idToken, accessToken: accessToken)
        
        print("✅ Đăng nhập KÉP (Google + Firebase) thành công: \(result.user.profile?.email ?? "Unknown")")
    }
    
    // Đăng xuất
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        FirebaseAuthService.shared.signOut() // Bổ sung đăng xuất Firebase
        self.currentUser = nil
        self.isSignedIn = false
        print("Đã đăng xuất toàn bộ.")
    }
    
    // --------------------------------------------------------
    // QUẢN LÝ TOKEN & API
    // --------------------------------------------------------
    
    // Lấy Token hiện tại (Tự động refresh nếu hết hạn)
    func getValidAccessToken() async throws -> String {
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            throw NSError(domain: "GoogleDriveService", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Google sign-in session not found. Please sign in again."])
        }
        
        // 2. Thần dược của Google SDK: Tự động kiểm tra hạn và refresh token ngầm nếu cần
        let refreshedUser = try await currentUser.refreshTokensIfNeeded()
        
        // 3. Trả về chuỗi token mới tinh để nạp vào Header API
        return refreshedUser.accessToken.tokenString
    }
    
    // Tạo hoặc lấy ID của thư mục trên Drive
    func getOrCreateFolder(name: String, parentID: String? = nil) async throws -> String {
        let token = try await getValidAccessToken()
        
        // 1. Kiểm tra xem thư mục đã tồn tại chưa
        let escapedName = name.replacingOccurrences(of: "'", with: "\\'")
        var query = "mimeType='application/vnd.google-apps.folder' and name='\(escapedName)' and trashed=false"
        if let parentID = parentID {
            query += " and '\(parentID)' in parents"
        }
        
        let urlString = "https://www.googleapis.com/drive/v3/files?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&fields=files(id)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var searchReq = URLRequest(url: url)
        searchReq.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: searchReq)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let files = json["files"] as? [[String: Any]],
           let firstFile = files.first,
           let folderId = firstFile["id"] as? String {
            return folderId // Thư mục đã tồn tại
        }
        
        // 2. Nếu chưa có, tiến hành tạo mới
        guard let createUrl = URL(string: "https://www.googleapis.com/drive/v3/files") else { throw URLError(.badURL) }
        var createReq = URLRequest(url: createUrl)
        createReq.httpMethod = "POST"
        createReq.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        createReq.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder"
        ]
        if let parentID = parentID {
            body["parents"] = [parentID]
        }
        
        createReq.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let (createData, response) = try await URLSession.shared.data(for: createReq)
        let errorStr = String(data: createData, encoding: .utf8) ?? "Unknown"
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("❌ Lỗi tạo thư mục: \(errorStr)")
            throw DriveError.folderCreationFailed(errorStr)
        }
        
        if let json = try? JSONSerialization.jsonObject(with: createData) as? [String: Any],
           let newFolderId = json["id"] as? String {
            return newFolderId
        }
        
        throw DriveError.folderCreationFailed("Không thể parse ID thư mục từ response: \(errorStr)")
    }
    
    // Upload file âm thanh sử dụng giao thức Resumable Upload
    func uploadAudioFile(fileURL: URL, folderID: String) async throws -> String {
        let token = try await getValidAccessToken()
        let fileName = fileURL.lastPathComponent
        
        // --- PHASE 1: Yêu cầu mở phiên Upload (Request Resumable Session) ---
        guard let initUrl = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable") else { throw URLError(.badURL) }
        var initReq = URLRequest(url: initUrl)
        initReq.httpMethod = "POST"
        initReq.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        initReq.addValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        
        let metadata: [String: Any] = [
            "name": fileName,
            "parents": [folderID]
        ]
        initReq.httpBody = try? JSONSerialization.data(withJSONObject: metadata)
        
        let (_, initResponse) = try await URLSession.shared.data(for: initReq)
        guard let httpInitResponse = initResponse as? HTTPURLResponse,
              httpInitResponse.statusCode == 200,
              let uploadURIString = httpInitResponse.value(forHTTPHeaderField: "Location"),
              let uploadURI = URL(string: uploadURIString) else {
            throw DriveError.uploadFailed("Không thể khởi tạo phiên Resumable Upload.")
        }
        
        // --- PHASE 2: Bơm dữ liệu file (Upload File Data) ---
        var uploadReq = URLRequest(url: uploadURI)
        uploadReq.httpMethod = "PUT"
        // Tự động xác định Content-Type dựa trên phần mở rộng file
        let fileExtension = fileURL.pathExtension.lowercased()
        let resolvedMimeType: String
        switch fileExtension {
        case "m4a":
            resolvedMimeType = "audio/mp4"
        case "mp3":
            resolvedMimeType = "audio/mpeg"
        case "flac":
            resolvedMimeType = "audio/flac"
        case "wav":
            resolvedMimeType = "audio/wav"
        case "alac":
            resolvedMimeType = "audio/alac"
        case "aac":
            resolvedMimeType = "audio/aac"
        case "jpg", "jpeg":
            resolvedMimeType = "image/jpeg"
        case "png":
            resolvedMimeType = "image/png"
        default:
            resolvedMimeType = "application/octet-stream"
        }
        uploadReq.addValue(resolvedMimeType, forHTTPHeaderField: "Content-Type")
        // Bắt buộc phải có Content-Length đối với URLSession.shared.upload
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = attributes[.size] as? UInt64 ?? 0
        uploadReq.addValue("\(fileSize)", forHTTPHeaderField: "Content-Length")
        
        let (uploadData, uploadResponse) = try await URLSession.shared.upload(for: uploadReq, fromFile: fileURL)
        
        guard let httpUploadResponse = uploadResponse as? HTTPURLResponse,
              httpUploadResponse.statusCode == 200 || httpUploadResponse.statusCode == 201 else {
            throw DriveError.uploadFailed("Lỗi trong quá trình truyền dữ liệu file.")
        }
        
        if let json = try? JSONSerialization.jsonObject(with: uploadData) as? [String: Any],
           let fileId = json["id"] as? String {
            return fileId
        }
        
        throw DriveError.uploadFailed("Không lấy được ID file sau khi upload.")
    }
    
    // Thiết lập quyền truy cập file thành Public (Anyone with the link can view)
    func setPublicPermission(fileID: String) async throws {
        let token = try await getValidAccessToken()
        let urlString = "https://www.googleapis.com/drive/v3/files/\(fileID)/permissions"
        
        guard let url = URL(string: urlString) else {
            throw DriveError.uploadFailed("URL cấp quyền không hợp lệ.")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Cấu hình payload theo đúng chuẩn Google Drive API v3
        let body: [String: Any] = [
            "role": "reader",
            "type": "anyone"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw DriveError.uploadFailed("Không thể thiết lập quyền Public cho file: \(fileID)")
        }
    }
    
    func uploadImageData(imageData: Data, fileName: String = "cover_\(UUID().uuidString).jpg", mimeType: String = "image/jpeg", folderID: String) async throws -> String {
        guard let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let accessToken = try await getValidAccessToken()
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Type: application/json; charset=UTF-8\r\n\r\n".utf8))
        let metadata: [String: Any] = [
            "name": fileName,
            "parents": [folderID]
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [])
        body.append(metadataData)
        body.append(Data("\r\n".utf8))
        
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(imageData)
        body.append(Data("\r\n".utf8))
        body.append(Data("--\(boundary)--\r\n".utf8))
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorLog = String(data: data, encoding: .utf8) ?? "Lỗi không xác định"
            throw NSError(domain: "GoogleDriveService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Drive Upload Failed: \(errorLog)"])
        }
        
        if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
           let fileID = json["id"] as? String {
            return fileID
        }
        
        throw NSError(domain: "GoogleDriveService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Cannot parse response ID from Google"])
    }
    
    func uploadImageFile(fileURL: URL, folderID: String) async throws -> String {
        let fileExtension = fileURL.pathExtension.lowercased()
        let mimeType = (fileExtension == "png") ? "image/png" : "image/jpeg"
        let fileData = try Data(contentsOf: fileURL)
        return try await uploadImageData(
            imageData: fileData,
            fileName: fileURL.lastPathComponent,
            mimeType: mimeType,
            folderID: folderID
        )
    }
    
    // Hàm xoá file trên Google Drive dựa vào fileID
    func deleteFile(fileID: String) async throws {
        guard let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        let accessToken = try await getValidAccessToken()
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorLog = String(data: data, encoding: .utf8) ?? "Lỗi không xác định"
            throw NSError(domain: "GoogleDriveService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Cannot delete file: \(errorLog)"])
        }
    }
}

