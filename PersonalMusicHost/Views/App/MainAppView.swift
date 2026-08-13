//
//  MainAppView.swift
//  PersonalMusicHost
//
//  Root app shell. Owns the NavigationStack and injects all ViewModels
//  as EnvironmentObjects for the navigation hierarchy.
//

import SwiftUI

#if os(macOS)
struct MainAppView: View {
    @ObservedObject private var driveService = GoogleDriveService.shared
    @EnvironmentObject var authViewModel: AuthViewModel

    @StateObject private var playerViewModel   = PlayerViewModel()
    @StateObject private var databaseViewModel = DatabaseViewModel()
    @StateObject private var pipelineViewModel = PipelineViewModel()

    var body: some View {
        NavigationStack {
            MusicDashboardView()
                .environmentObject(playerViewModel)
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .profile:
                        ProfileView()
                            .environmentObject(authViewModel)
                    case .ingestion:
                        IngestionView()
                            .environmentObject(pipelineViewModel)
                            .environmentObject(authViewModel)
                    case .database:
                        DatabaseManagementView()
                            .environmentObject(databaseViewModel)
                    case .userProfile(let uid):
                        ProfileView(uid: uid)
                            .environmentObject(authViewModel)
                    }
                }
        }
    }
}
#endif
