//
//  PersonalMusicHostApp.swift
//  PersonalMusicHost
//
//  Created by TwentyMikeyOne on 23/6/26.
//

import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct PersonalMusicHostApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    
    init() {
        FirebaseApp.configure()
        let clientID = AppEnvironment.googleClientID
        GoogleDriveService.shared.configure(clientID: clientID)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 464, maxWidth: 1600, minHeight: 600, maxHeight: 1000)
                .environmentObject(authViewModel)
                .environment(\.locale, Locale(identifier: appLanguage))
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
        .windowResizability(.contentSize)
    }
}

