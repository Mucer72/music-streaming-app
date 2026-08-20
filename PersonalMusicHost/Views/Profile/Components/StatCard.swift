//
//  StatCard.swift
//  PersonalMusicHost
//
//  Profile stat card showing a count with an icon and label.
//  Used in ProfileView to display Tracks, Albums, and Respect stats.
//  Supports optional interactive tap action.
//

import SwiftUI

struct StatCard: View {
    var title: LocalizedStringKey
    var count: Int
    var icon: String
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action = action {
                Button(action: action) {
                    cardContent
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.caption)
                                .foregroundColor(.blue.opacity(0.8))
                                .padding(6)
                        }
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
    }

    private var cardContent: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2).foregroundColor(.blue)

            Text("\(count)")
                .font(.title2).fontWeight(.bold)

            Text(title)
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(minWidth: 95, minHeight: 95)
        .padding(8)
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor))
        #else
        .background(Color(.secondarySystemBackground))
        #endif
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}
