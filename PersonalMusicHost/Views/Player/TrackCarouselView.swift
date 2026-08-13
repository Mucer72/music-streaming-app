//
//  TrackCarouselView.swift
//  PersonalMusicHost
//
//  Horizontal carousel showing the current playback queue.
//  Supports tap-to-focus, context-menu removal, and drag-to-reorder.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Carousel Item
struct TrackCarouselItemView: View {
    let track: TrackRecord
    let isFocused: Bool
    let isLiked: Bool
    let onLikeToggle: () -> Void

    var body: some View {
        let coverSize: CGFloat  = isFocused ? 130 : 100
        let coverRadius: CGFloat = isFocused ? 12  : 8
        let shadowRadius: CGFloat = isFocused ? 10 : 4
        let titleWidth: CGFloat = isFocused ? 150 : 110
        let titleFont: Font     = isFocused ? .headline : .subheadline

        return VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                SecureDriveImage(fileID: track.coverDriveID)
                    .frame(width: coverSize, height: coverSize)
                    .cornerRadius(coverRadius)
                    .shadow(
                        color: isFocused ? Color.blue.opacity(0.4) : Color.black.opacity(0.2),
                        radius: shadowRadius
                    )
                    .scaleEffect(isFocused ? 1.0 : 0.95)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isFocused)
                
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: isFocused ? 11 : 9, weight: .bold))
                    .foregroundColor(isLiked ? .pink : .white)
                    .frame(width: isFocused ? 24 : 18, height: isFocused ? 24 : 18)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Circle())
                    .padding(.trailing, isFocused ? 10 : 8)
                    .padding(.bottom, isFocused ? 10 : 8)
                    .onTapGesture {
                        onLikeToggle()
                    }
            }

            Text(track.title)
                .font(titleFont).lineLimit(1).frame(width: titleWidth)

            Text(track.artist)
                .font(.caption).foregroundColor(.secondary).lineLimit(1).frame(width: titleWidth)
        }
    }
}

// MARK: - Carousel Container
struct TrackCarouselView: View {
    @EnvironmentObject var viewModel: PlayerViewModel
    @State private var draggedTrack: TrackRecord?

    @ViewBuilder
    private func trackContextMenu(for track: TrackRecord) -> some View {
        Button(role: .destructive) {
            if let index = viewModel.playlist.firstIndex(where: { $0.id == track.id }) {
                withAnimation {
                    viewModel.removeFromPlaylist(at: IndexSet(integer: index))
                }
            }
        } label: {
            Label("Remove from Queue", systemImage: "trash")
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollViewReader { proxy in
                LazyHStack(spacing: 20) {
                    ForEach(viewModel.playlist, id: \.id) { track in
                        let isFocused = track.id == viewModel.focusedTrack?.id
                        let isLiked = viewModel.likedTrackIds.contains(track.id ?? "")

                        TrackCarouselItemView(
                            track: track,
                            isFocused: isFocused,
                            isLiked: isLiked,
                            onLikeToggle: {
                                viewModel.toggleLike(for: track)
                            }
                        )
                            .onTapGesture {
                                withAnimation { viewModel.focusedTrack = track }
                            }
                            .contextMenu { trackContextMenu(for: track) }
                            .onDrag {
                                self.draggedTrack = track
                                return NSItemProvider(
                                    object: (track.id ?? UUID().uuidString) as NSString
                                )
                            } preview: {
                                Color.clear.frame(width: 0, height: 0)
                            }
                            .onDrop(
                                of: [.plainText],
                                delegate: TrackDropDelegate(
                                    item: track,
                                    viewModel: viewModel,
                                    draggedTrack: $draggedTrack
                                )
                            )
                            .id(track.id ?? "")
                    }
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 10)
                .onChange(of: viewModel.focusedTrack?.id) { _, newFocusId in
                    if let id = newFocusId {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeInOut) { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                }
            }
        }
        .frame(height: 220)
    }
}

// MARK: - Drop Delegate (reorder logic)
struct TrackDropDelegate: DropDelegate {
    let item: TrackRecord
    var viewModel: PlayerViewModel
    @Binding var draggedTrack: TrackRecord?

    func performDrop(info: DropInfo) -> Bool {
        draggedTrack = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedTrack, dragged.id != item.id else { return }
        guard
            let fromIndex = viewModel.playlist.firstIndex(where: { $0.id == dragged.id }),
            let toIndex   = viewModel.playlist.firstIndex(where: { $0.id == item.id })
        else { return }

        if fromIndex != toIndex {
            withAnimation(.default) {
                viewModel.playlist.move(
                    fromOffsets: IndexSet(integer: fromIndex),
                    toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
                )
            }
        }
    }
}
