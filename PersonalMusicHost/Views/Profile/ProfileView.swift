//
//  ProfileView.swift
//  PersonalMusicHost
//
//  User profile screen. Displays avatar, stats (Tracks/Albums/Respect),
//  cloud management actions, and sign-out button.
//

import SwiftUI
import FirebaseCore

struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    @StateObject private var databaseViewModel = DatabaseViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    @AppStorage("appLanguage") private var appLanguage: String = "en"

    @State private var isShowingDatabaseManager = false

    init(uid: String? = nil) {
        _viewModel = StateObject(wrappedValue: ProfileViewModel(targetUID: uid))
    }

    private var isOwnProfile: Bool {
        viewModel.targetUID == nil || viewModel.targetUID == FirebaseAuthService.shared.currentUID
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // MARK: - Header: Avatar & Info
                VStack(spacing: 16) {
                    if let photoURLString = viewModel.userRecord?.photoURL,
                       let url = URL(string: photoURLString) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 120, height: 120)
                        .clipShape(Circle()).shadow(radius: 5)
                    } else {
                        Image(systemName: "person.circle.fill")
                            .resizable().frame(width: 120, height: 120)
                            .foregroundColor(.gray).shadow(radius: 5)
                    }

                    VStack(spacing: 8) {
                        Text(viewModel.userRecord?.displayName ?? "Anonymous User")
                            .font(.title).fontWeight(.bold)

                        Text(viewModel.userRecord?.email ?? "")
                            .font(.subheadline).foregroundColor(.secondary)

                        if let joinDate = viewModel.userRecord?.createdAt?.dateValue() {
                            Text("Joined: \(joinDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.footnote).foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.top, 40)

                // MARK: - Stats (Interactive for own profile)
                HStack(spacing: 20) {
                    StatCard(
                        title: "Tracks",
                        count: viewModel.totalTracks,
                        icon: "music.note",
                        action: isOwnProfile ? {
                            databaseViewModel.managementMode = .track
                            isShowingDatabaseManager = true
                        } : nil
                    )
                    
                    StatCard(
                        title: "Albums",
                        count: viewModel.totalAlbums,
                        icon: "square.stack",
                        action: isOwnProfile ? {
                            databaseViewModel.managementMode = .album
                            isShowingDatabaseManager = true
                        } : nil
                    )
                    
                    StatCard(
                        title: "Respect",
                        count: viewModel.userRecord?.respectCount ?? 0,
                        icon: "heart.fill"
                    )
                }
                .padding(.horizontal)

                Spacer(minLength: 20)

                // MARK: - Actions (own profile only)
                if isOwnProfile {
                    VStack(spacing: 14) {
                        // Quick Button to open Database Management
                        Button(action: {
                            isShowingDatabaseManager = true
                        }) {
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Text("Quản lý dữ liệu & Bài hát")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            #if os(macOS)
                            .background(Color.secondary.opacity(0.12))
                            #else
                            .background(Color(.secondarySystemBackground))
                            #endif
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)

                        #if os(macOS)
                        HStack {
                            Text("Language")
                            Spacer()
                            Picker("", selection: $appLanguage) {
                                Text("English").tag("en")
                                Text("Tiếng Việt").tag("vi")
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(12)
                        #endif

                        Button(action: {
                            GoogleDriveService.shared.signOut()
                            authViewModel.signOut()
                        }) {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("Sign Out").fontWeight(.semibold)
                            }
                            .foregroundColor(.white).padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red).cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("Profile")
        .task { await viewModel.loadUserProfile() }
        .sheet(isPresented: $isShowingDatabaseManager) {
            NavigationStack {
                DatabaseManagementView()
                    .environmentObject(databaseViewModel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Đóng") {
                                isShowingDatabaseManager = false
                            }
                            .fontWeight(.semibold)
                        }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 700, minHeight: 550)
            #endif
        }
    }
}
