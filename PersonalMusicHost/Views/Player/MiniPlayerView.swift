//
//  MiniPlayerView.swift
//  PersonalMusicHost
//
//  Compact player bar shown at the bottom of the dashboard when the queue
//  is active but the full Turntable player is collapsed.
//  Tap to expand back to the full player.
//

import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var viewModel: PlayerViewModel

    var body: some View {
        HStack(spacing: 16) {
            SecureDriveImage(fileID: viewModel.playingTrack?.coverDriveID)
                .frame(width: 48, height: 48)
                .cornerRadius(6)
                .shadow(radius: 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.playingTrack?.title ?? "No track playing")
                    .font(.headline).lineLimit(1)
                Text(viewModel.playingTrack?.artist ?? "")
                    .font(.subheadline).foregroundColor(.secondary).lineLimit(1)
            }

            Spacer()

            Button(action: { viewModel.prevTrack() }) {
                Image(systemName: "backward.fill").font(.title2).foregroundColor(.primary)
            }.buttonStyle(.plain)

            Button(action: { viewModel.togglePlayPause() }) {
                Image(systemName: viewModel.playerEngine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title).foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)

            Button(action: { viewModel.nextTrack() }) {
                Image(systemName: "forward.fill").font(.title2).foregroundColor(.primary)
            }.buttonStyle(.plain)

            Button(action: { viewModel.closePlayer() }) {
                Image(systemName: "xmark").font(.title3).foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 12)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .overlay(
            GeometryReader { geo in
                let duration = viewModel.playerEngine.duration
                let currentTime = viewModel.playerEngine.currentTime
                let ratio = duration > 0 ? min(max(currentTime / duration, 0), 1) : 0

                ZStack(alignment: .bottomLeading) {
                    Color.clear
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: geo.size.width * CGFloat(ratio), height: 3)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring()) {
                viewModel.isPlayerExpanded = true
            }
        }
    }
}
