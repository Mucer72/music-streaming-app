//
//  DashboardTopBar.swift
//  PersonalMusicHost
//
//  Top navigation bar for MusicDashboardView containing the title,
//  search field, and navigation buttons (upload / profile).
//

import SwiftUI

#if os(macOS)
struct DashboardTopBar: View {
    @Binding var searchText: String

    var body: some View {
        HStack {
            Text("Music Library").font(.title).bold()

            Spacer()

            // Search field
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.gray)
                TextField("Search songs, artists, albums...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                    }.buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.gray.opacity(0.15))
            .cornerRadius(8)
            .frame(maxWidth: 400)

            Spacer()

            HStack(spacing: 16) {
                NavigationLink(value: AppRoute.ingestion) {
                    Image(systemName: "icloud.and.arrow.up.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.blue)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                NavigationLink(value: AppRoute.profile) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.blue)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
}
#endif
