//
//  Untitled.swift
//  PersonalMusicHost
//
//  Created by TwentyMikeyOne on 28/6/26.
//

//
//  AuthViewModel.swift
//  PersonalMusicHost
//

import Foundation
import SwiftUI
import GoogleSignIn
import FirebaseAuth
import Combine

enum AuthStatus {
    case undetermined  // Đang quét Keychain khi vừa bật app
    case signedOut     // Chưa đăng nhập / Hết phiên
    case signedIn      // Đã đăng nhập thành công cả Google & Firebase
}

@MainActor
class AuthViewModel: ObservableObject {
    @Published var status: AuthStatus = .undetermined
    @Published var userEmail: String = ""
    
    init() {
        // Tự động kiểm tra và khôi phục phiên đăng nhập cũ khi bật app
        restorePreviousSession()
    }
    
    /// Khôi phục phiên đăng nhập từ Keychain và tái đồng bộ Token lên Firebase
    func restorePreviousSession() {
        Task {
            do {
                // 1. Khôi phục phiên Google Sign-In cũ từ Keychain
                let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
                
                // 2. Trích xuất cặp Token mới nhất từ Google để kiểm tra tính hợp lệ
                guard let idToken = user.idToken?.tokenString else {
                    throw NSError(domain: "AuthError", code: 401,
                                  userInfo: [NSLocalizedDescriptionKey: "Không lấy được ID Token mới từ Google."])
                }
                let accessToken = user.accessToken.tokenString
                
                // 3. Ép FirebaseAuthService sử dụng cặp Token này để đăng nhập lại Firebase
                // Việc này giúp đồng bộ lại 'currentUID' phục vụ cho các logic DB sau này
                try await FirebaseAuthService.shared.signInWithGoogle(idToken: idToken, accessToken: accessToken)
                
                // 4. Khi cả hai bước xác thực song phương đều vượt qua suôn sẻ:
                self.userEmail = user.profile?.email ?? ""
                self.status = .signedIn
                print("✅ [Auth] Tự động khôi phục chuỗi xác thực thành công: \(self.userEmail)")
                
            } catch {
                // Nếu Google hết hạn HOẶC Firebase từ chối Token -> Đăng xuất sạch sẽ, đẩy về LoginView
                print("ℹ️ [Auth] Phiên làm việc cũ đã hết hạn hoặc không hợp lệ: \(error.localizedDescription)")
                signOut()
            }
        }
    }
    
    // Hàm xử lý Đăng nhập thành công (Dành cho luồng đăng nhập chủ động từ LoginView)
    func signInWithGoogle() {
        if let currentUser = GIDSignIn.sharedInstance.currentUser {
            self.userEmail = currentUser.profile?.email ?? ""
            self.status = .signedIn
        }
    }
    
    // Hàm xử lý Đăng xuất triệt để và cưỡng chế điều hướng UI
    func signOut() {
        // Xoá session Google
        GIDSignIn.sharedInstance.signOut()
        
        // Xoá session Firebase bên Service chung
        FirebaseAuthService.shared.signOut()
        
        // Đưa UI về màn hình đăng nhập ngay lập tức với hiệu ứng mượt mà
        withAnimation {
            self.userEmail = ""
            self.status = .signedOut
        }
        print("🔒 [Auth] Hệ thống đã cưỡng chế đăng xuất an toàn.")
    }
}
