//
//  ContentView.swift
//  PersonalMusicHost
//
//  Created by TwentyMikeyOne on 23/6/26.
//

//
//  ContentView.swift
//  PersonalMusicHost
//

import SwiftUI

struct ContentView: View {
    // Lấy AuthViewModel từ môi trường ra sử dụng
    @EnvironmentObject var authViewModel: AuthViewModel
    
    var body: some View {
        switch authViewModel.status {
        case .undetermined:
            // Màn hình chờ khi app đang lục tìm Keychain (Tránh hiện tượng nhấp nháy màn hình Login)
            VStack(spacing: 15) {
                ProgressView()
                    .controlSize(.large)
                Text("Verifying security...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
        case .signedOut:
            // Nếu chưa đăng nhập -> Hiện màn hình Login của bạn
            LoginView()
                .transition(.opacity) // Hiệu ứng mượt mà khi đổi màn hình
            
        case .signedIn:
            // Đã đăng nhập -> Vào thẳng màn hình Dashboard chính (chứa IngestionView hoặc Database View)
            MainAppView()
                .transition(.opacity)
        }
    }
}
