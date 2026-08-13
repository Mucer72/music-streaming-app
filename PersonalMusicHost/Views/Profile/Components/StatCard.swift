//
//  StatCard.swift
//  PersonalMusicHost
//
//  Profile stat card showing a count with an icon and label.
//  Used in ProfileView to display Tracks, Albums, and Respect stats.
//

import SwiftUI

struct StatCard: View {
    var title: LocalizedStringKey
    var count: Int
    var icon: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title).foregroundColor(.blue)

            Text("\(count)")
                .font(.title2).fontWeight(.bold)

            Text(title)
                .font(.subheadline).foregroundColor(.secondary)
        }
        .frame(width: 100, height: 100)
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor))
        #else
        .background(Color(.secondarySystemBackground))
        #endif
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}
