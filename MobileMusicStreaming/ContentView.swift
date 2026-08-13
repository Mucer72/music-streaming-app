//
//  ContentView.swift
//  MobileMusicStreaming
//
//  Created by TwentyMikeyOne on 14/7/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    
    var body: some View {
        switch authViewModel.status {
        case .undetermined:
            VStack(spacing: 15) {
                ProgressView()
                    .controlSize(.large)
                Text("Đang kiểm tra bảo mật...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
        case .signedOut:
            LoginView()
                .transition(.opacity)
            
        case .signedIn:
            MobileMainAppView()
                .transition(.opacity)
        }
    }
}

#Preview {
    ContentView()
}
