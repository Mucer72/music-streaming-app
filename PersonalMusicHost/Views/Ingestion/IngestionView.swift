//
//  IngestionView.swift
//  PersonalMusicHost
//
//  Upload & Convert screen. Orchestrates the pipeline control panels.
//  All individual panels live in Ingestion/Components/.
//

import SwiftUI
import GoogleSignIn

struct IngestionView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var viewModel: PipelineViewModel
    @ObservedObject private var driveService = GoogleDriveService.shared
    @State private var showLogs: Bool = false

    // Validation: all conditions must pass before the pipeline can start
    private var isStartDisabled: Bool {
        if viewModel.isProcessing { return true }
        if viewModel.tracks.isEmpty { return true }
        if !viewModel.isAACSelected && !viewModel.isALACSelected { return true }
        if !viewModel.saveToLocal && !viewModel.uploadToDrive { return true }
        if viewModel.saveToLocal && viewModel.outputDirectory == nil { return true }
        if viewModel.uploadToDrive && authViewModel.status != .signedIn { return true }
        if viewModel.isAlbumMode {
            if viewModel.globalGenreId.isEmpty { return true }
        } else {
            if viewModel.tracks.contains(where: { $0.genreId == nil || $0.genreId!.isEmpty }) {
                return true
            }
        }
        return false
    }

    var body: some View {
        VStack(spacing: 20) {
            // 1. Header + progress + start button
            IngestionHeaderView(showLogs: $showLogs, isStartDisabled: isStartDisabled)

            HStack(spacing: 20) {
                // 2. Left column: controls & queue
                VStack(spacing: 15) {
                    ControlPanelView()
                    if viewModel.isAlbumMode {
                        AlbumGlobalInfoView()
                    }
                    TrackListQueueView()
                }
                .frame(maxWidth: .infinity)

                // 3. Right column: logs (toggleable)
                if showLogs {
                    ConsoleView()
                        .frame(width: 350)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }

            // Link to Database Management
            NavigationLink(value: AppRoute.database) {
                HStack {
                    Image(systemName: "server.rack")
                    Text("Database Management").fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .background(Color.blue)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .animation(.easeInOut, value: showLogs)
        .padding(20)
    }
}
