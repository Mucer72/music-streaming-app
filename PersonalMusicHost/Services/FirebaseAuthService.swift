//
//  FirebaseAuthService.swift
//  PersonalMusicHost
//
//  Created by TwentyMikeyOne on 27/6/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

@MainActor
class FirebaseAuthService: ObservableObject {
    static let shared = FirebaseAuthService()
    
    @Published var isAuthenticated = false
    @Published var currentUID: String?
    
    private let db = Firestore.firestore()
    
    // Đăng nhập Firebase bằng cặp Token từ Google
    func signInWithGoogle(idToken: String, accessToken: String) async throws {
        let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                       accessToken: accessToken)
        
        // Xác thực với Firebase
        let authResult = try await Auth.auth().signIn(with: credential)
        let user = authResult.user
        
        self.currentUID = user.uid
        self.isAuthenticated = true
        
        // Đồng bộ dữ liệu lên Firestore
        try await syncUserData(user: user)
    }
    
    // Tạo hoặc cập nhật thông tin User trên Firestore
    private func syncUserData(user: User) async throws {
        let userRef = db.collection("users").document(user.uid)
        
        let docSnapshot = try await userRef.getDocument()
        
        var userData: [String: Any] = [
            "uid": user.uid,
            "email": user.email ?? "",
            "displayName": user.displayName ?? "",
            "photoURL": user.photoURL?.absoluteString ?? ""
        ]
        
        if !docSnapshot.exists {
            // Lần đầu đăng nhập: Tạo mới kèm createdAt và respectCount = 0
            userData["createdAt"] = FieldValue.serverTimestamp()
            userData["respectCount"] = 0
            try await userRef.setData(userData)
            print("✅ Đã tạo hồ sơ User mới trên Firestore.")
        } else {
            // Các lần sau: Cập nhật email, displayName, photoURL
            try await userRef.setData(userData, merge: true)
            print("✅ Đã đồng bộ đăng nhập Firebase và cập nhật thông tin User.")
        }
    }
    
    func signOut() {
        try? Auth.auth().signOut()
        self.currentUID = nil
        self.isAuthenticated = false
    }
}

