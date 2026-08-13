//
//  TurntableCDView.swift
//  PersonalMusicHost
//
//  Full-screen vinyl turntable player view. Displays the spinning album art,
//  progress ring, scrub gesture, and playback mode controls.
//

import SwiftUI

struct TurntableCDView: View {
    @EnvironmentObject var viewModel: PlayerViewModel

    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0
    @State private var dragStartTime: TimeInterval = 0
    @State private var lastTouchAngle: Double = 0

    var body: some View {
        let isFocusedTrackPlaying = viewModel.playingTrack?.id == viewModel.focusedTrack?.id
        let isBuffering = isFocusedTrackPlaying && viewModel.playerEngine.isBuffering
        let isSpinning = isFocusedTrackPlaying && viewModel.playerEngine.isPlaying && !isBuffering

        let displayTime = isScrubbing ? scrubTime : (isFocusedTrackPlaying ? viewModel.playerEngine.currentTime : 0)
        let duration = isFocusedTrackPlaying && viewModel.playerEngine.duration > 0 ? viewModel.playerEngine.duration : 0

        // Each second of music advances the disc 15 degrees (slower, smoother rotation)
        let rotationDegrees = isFocusedTrackPlaying ? (displayTime * 15) : 0

        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height) - 100

            VStack {
                // Top controls: collapse + playback mode
                HStack {
                    Button(action: {
                        withAnimation(.spring()) { viewModel.collapsePlayer() }
                    }) {
                        Image(systemName: "chevron.down")
                            .font(.title3).foregroundColor(.secondary)
                            .frame(width: 44, height: 44)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Close player")

                    Spacer()

                    Button(action: {
                        withAnimation {
                            switch viewModel.playbackMode {
                            case .queue:   viewModel.playbackMode = .loopAll
                            case .loopAll: viewModel.playbackMode = .loopOne
                            case .loopOne: viewModel.playbackMode = .random
                            case .random:  viewModel.playbackMode = .queue
                            }
                        }
                    }) {
                        Image(systemName: playbackModeIcon(for: viewModel.playbackMode))
                            .font(.title3)
                            .foregroundColor(viewModel.playbackMode == .queue ? .secondary : .blue)
                            .frame(width: 44, height: 44)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(playbackModeTooltip(for: viewModel.playbackMode))
                }
                .frame(width: size)

                ZStack {
                    // 1. Album art cover (spinning)
                    SecureDriveImage(fileID: viewModel.focusedTrack?.coverDriveID)
                        .clipShape(Circle())
                        .frame(width: size - 20, height: size - 20)
                        .rotationEffect(.degrees(rotationDegrees))
                        .animation(isScrubbing ? .interactiveSpring() : nil, value: rotationDegrees)

                    // 2. Buffering overlay
                    if isBuffering {
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .frame(width: size - 20, height: size - 20)
                    }

                    // 3. Centre spindle
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: size * 0.25, height: size * 0.25)
                        .shadow(color: .black.opacity(0.3), radius: 10)

                    // 4. Progress rings
                    if isFocusedTrackPlaying {
                        if isBuffering {
                            InfiniteLoadingRing(size: size)
                        } else {
                            let bufferRatio = duration > 0
                                ? min(max(viewModel.playerEngine.bufferedTime / duration, 0), 1) : 0
                            Circle()
                                .trim(from: 0, to: CGFloat(bufferRatio))
                                .stroke(Color.gray.opacity(0.5),
                                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: size, height: size)
                                .animation(.easeInOut(duration: 0.5), value: bufferRatio)

                            let progressRatio = duration > 0
                                ? min(max(displayTime / duration, 0), 1) : 0
                            Circle()
                                .trim(from: 0, to: CGFloat(progressRatio))
                                .stroke(Color.blue,
                                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: size, height: size)
                        }
                    }

                    // 5. Full Disc Angular Drag Gesture for natural circular scrubbing
                    if isFocusedTrackPlaying && !isBuffering {
                        Color.white.opacity(0.001)
                            .frame(width: size, height: size)
                            .gesture(
                                DragGesture(minimumDistance: 5)
                                    .onChanged { value in
                                        let center = CGPoint(x: size / 2, y: size / 2)
                                        let dx = value.location.x - center.x
                                        let dy = value.location.y - center.y
                                        let currentTouchAngle = Double(atan2(dy, dx))
                                        
                                        if !isScrubbing {
                                            isScrubbing = true
                                            scrubTime = viewModel.playerEngine.currentTime
                                            lastTouchAngle = currentTouchAngle
                                        } else {
                                            var angleDelta = currentTouchAngle - lastTouchAngle
                                            // Handle wrapping around -pi and pi
                                            if angleDelta > .pi {
                                                angleDelta -= 2 * .pi
                                            } else if angleDelta < -.pi {
                                                angleDelta += 2 * .pi
                                            }
                                            
                                            let deltaDegrees = angleDelta * 180 / .pi
                                            let deltaTime = deltaDegrees / 15 // 15 degrees = 1 second of audio
                                            
                                            scrubTime = min(max(scrubTime + deltaTime, 0), duration)
                                            lastTouchAngle = currentTouchAngle
                                        }
                                    }
                                    .onEnded { _ in
                                        viewModel.playerEngine.seek(to: scrubTime)
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            isScrubbing = false
                                        }
                                    }
                            )
                    }

                    // 6. Play/Pause button (placed on top of everything so it's fully interactive)
                    Button(action: {
                        if isFocusedTrackPlaying {
                            viewModel.togglePlayPause()
                        } else if let track = viewModel.focusedTrack {
                            viewModel.playTrack(track)
                        }
                    }) {
                        ZStack {
                            Color.white.opacity(0.001)
                            Image(systemName: isSpinning ? "pause.fill" : "play.fill")
                                .font(.system(size: size * 0.09))
                                .foregroundColor(.primary)
                                .offset(x: isSpinning ? 0 : 3)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: size * 0.4, height: size * 0.4)
                    .contentShape(Circle())
                }
                .frame(width: size, height: size)

                // Time display
                HStack {
                    Text(formatTime(displayTime))
                    Spacer()
                    Text("-" + formatTime(max(duration - displayTime, 0)))
                }
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: size, height: 44)
                .opacity(isFocusedTrackPlaying ? 1 : 0)
            }
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard !time.isNaN, !time.isInfinite else { return "00:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func playbackModeIcon(for mode: PlaybackMode) -> String {
        switch mode {
        case .queue:   return "repeat"
        case .loopAll: return "repeat"
        case .loopOne: return "repeat.1"
        case .random:  return "shuffle"
        }
    }

    private func playbackModeTooltip(for mode: PlaybackMode) -> LocalizedStringKey {
        switch mode {
        case .queue:   return "Play in order"
        case .loopAll: return "Repeat all"
        case .loopOne: return "Repeat current track"
        case .random:  return "Shuffle"
        }
    }
}

// MARK: - Infinite Loading Ring
struct InfiniteLoadingRing: View {
    var size: CGFloat
    @State private var isSpinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.6)
            .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .frame(width: size, height: size)
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isSpinning)
            .onAppear {
                DispatchQueue.main.async { isSpinning = true }
            }
    }
}


