//
//  LoginView.swift
//  PersonalMusicHost
//
//  Authentication screen with Google Sign-In button.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @ObservedObject private var driveService = GoogleDriveService.shared
    @State private var isLoggingIn = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                Image(systemName: "music.note.network")
                    .resizable().scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.white).shadow(radius: 10)

                VStack(spacing: 8) {
                    Text("CROSS-PLATFORM MUSIC")
                        .font(.largeTitle).fontWeight(.black)
                        .foregroundColor(.white).tracking(2)

                    Text("Personal music hosting & streaming ecosystem")
                        .font(.headline).foregroundColor(.white.opacity(0.8))
                }

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red).padding()
                        .background(Color.white.opacity(0.9)).cornerRadius(8)
                }

                Button(action: {
                    Task {
                        isLoggingIn = true
                        errorMessage = nil
                        do {
                            try await driveService.signIn()
                            await MainActor.run { authViewModel.status = .signedIn }
                        } catch {
                            errorMessage = String(localized: "Login failed: \(error.localizedDescription)")
                        }
                        isLoggingIn = false
                    }
                }) {
                    HStack {
                        if isLoggingIn {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "google")
                        }
                        Text("Continue with Google")
                            .font(.title3).fontWeight(.bold)
                    }
                    .padding(.horizontal, 40).padding(.vertical, 15)
                    .background(Color.white).foregroundColor(.black)
                    .cornerRadius(30)
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                }
                .buttonStyle(.plain)
                .disabled(isLoggingIn)
            }
        }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 600)
        #endif
    }
}
