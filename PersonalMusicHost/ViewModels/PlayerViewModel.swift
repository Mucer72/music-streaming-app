//
//  PlayerViewModel.swift
//  PersonalMusicHost
//
//  Created by TwentyMikeyOne on 28/6/26.
//

import Combine
import Foundation
import SwiftUI
import MediaPlayer

enum PlaybackMode: String {
    case queue
    case loopAll
    case loopOne
    case random
}

@MainActor
class PlayerViewModel: ObservableObject {
    @Published var tracks: [TrackRecord] = []
    @Published var playlist: [TrackRecord] = []
    @Published var albums: [AlbumRecord] = []
    @Published var topTracks: [TrackRecord] = []
    @Published var likedTracks: [TrackRecord] = []
    @Published var likedTrackIds: Set<String> = []
    @Published var playingTrack: TrackRecord?
    @Published var focusedTrack: TrackRecord?
    @Published var isLoading = false
    @Published var availableGenres: [GenreRecord] = []
    
    @Published var isPlayerExpanded: Bool = false

    @Published var searchText: String = ""

    @Published var playerEngine = AudioPlayerEngine()

    private let dbService = FirebaseDatabaseService.shared
    private let driveService = GoogleDriveService.shared

    private var cancellables = Set<AnyCancellable>()
    private var streamCountIncrementedForCurrentTrack = false
    
    @Published var playbackMode: PlaybackMode = .queue {
        didSet {
            preloadNextTrack()
        }
    }
    private var queuedTrack: TrackRecord?
    
    @Published var usersCache: [String: UserRecord] = [:]

    // MARK: - In-Memory Caches (giảm Firestore Reads)
    /// Cache tracks theo albumId: albumId → [TrackRecord]
    private var albumTracksCache: [String: [TrackRecord]] = [:]
    /// Cache tracks theo playlist: trackIds.joined() → [TrackRecord]
    private var playlistTracksCache: [String: [TrackRecord]] = [:]

    func fetchUser(uid: String) {
        if usersCache[uid] != nil { return }
        Task {
            do {
                let user = try await dbService.fetchUserRecord(uid: uid)
                DispatchQueue.main.async {
                    self.usersCache[uid] = user
                }
            } catch {
                print("❌ Lỗi tải user \(uid): \(error.localizedDescription)")
            }
        }
    }

    // Lọc bài hát theo SearchText
    var filteredTracks: [TrackRecord] {
        if searchText.isEmpty { return tracks }
        return tracks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.artist.localizedCaseInsensitiveContains(searchText)
        }
    }

    // Lọc Album theo SearchText
    var filteredAlbums: [AlbumRecord] {
        if searchText.isEmpty { return albums }
        return albums.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.artist.localizedCaseInsensitiveContains(searchText)
        }
    }

    init() {
        loadLibraryData()

        NotificationCenter.default.publisher(for: NSNotification.Name("TrackDidNeedNext"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleNextTrackNotification()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSNotification.Name("LibraryNeedsRefresh"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshLibrary()
            }
            .store(in: &cancellables)

        // Bắc cầu cập nhật UI từ Engine
        playerEngine.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        // 🔥 LẮNG NGHE SỰ THAY ĐỔI CỦA PLAYLIST (Kéo thả, Thêm, Xoá) ĐỂ CẬP NHẬT GỐI ĐẦU
        $playlist
            .dropFirst()
            .sink { [weak self] _ in
                // Chờ luồng UI chốt xong vị trí mảng rồi mới tính toán tải gối đầu
                DispatchQueue.main.async { self?.preloadNextTrack() }
            }
            .store(in: &cancellables)
            
        // 🔥 KIỂM TRA TĂNG LƯỢT NGHE SAU KHI NGHE 15%
        playerEngine.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                self?.checkStreamCountIncrement(currentTime: time)
            }
            .store(in: &cancellables)

        // Observe playingTrack changes to update Lock Screen / Control Center
        $playingTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateNowPlayingInfo()
            }
            .store(in: &cancellables)

        // Observe playerEngine.isPlaying changes to update playback rates
        playerEngine.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateNowPlayingInfo()
            }
            .store(in: &cancellables)

        // Observe playerEngine.duration changes to update full track duration
        playerEngine.$duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateNowPlayingInfo()
            }
            .store(in: &cancellables)

        setupRemoteCommandCenter()
    }

    private func checkStreamCountIncrement(currentTime: TimeInterval) {
        guard let track = playingTrack, let id = track.id else { return }
        let duration = playerEngine.duration
        guard duration > 0, !streamCountIncrementedForCurrentTrack else { return }
        
        if currentTime >= duration * 0.15 {
            streamCountIncrementedForCurrentTrack = true
            Task {
                do {
                    try await dbService.incrementStreamCount(trackId: id)
                    
                    // Cập nhật giao diện mượt mà
                    DispatchQueue.main.async {
                        if let index = self.tracks.firstIndex(where: { $0.id == id }) {
                            self.tracks[index].streamCount += 1
                        }
                        if let index = self.topTracks.firstIndex(where: { $0.id == id }) {
                            self.topTracks[index].streamCount += 1
                        }
                        if let index = self.playlist.firstIndex(where: { $0.id == id }) {
                            self.playlist[index].streamCount += 1
                        }
                    }
                } catch {
                    print("❌ Lỗi tăng stream count: \(error)")
                }
            }
        }
    }

    func refreshLibrary() {
        print("🔄 Bắt đầu làm mới Kho nhạc...")
        // Xoá cache vì library data mới vừa được tải về
        albumTracksCache.removeAll()
        playlistTracksCache.removeAll()
        loadLibraryData()
    }

    func loadLibraryData() {
        isLoading = true
        Task {
            do {
                // Chạy song song 3 tác vụ để tiết kiệm thời gian chờ
                async let fetchedTracks = dbService.fetchDashboardTracks()
                async let fetchedAlbums = dbService.fetchDashboardAlbums()
                async let fetchedTop = dbService.fetchTopStreamedTracks(
                    limit: 10
                )
                async let fetchedLiked = dbService.fetchLikedTracks(
                    userId: FirebaseAuthService.shared.currentUID ?? ""
                )
                async let fetchedGenres = dbService.fetchGenres()

                self.tracks = try await fetchedTracks
                self.albums = try await fetchedAlbums
                self.topTracks = try await fetchedTop
                self.availableGenres = try await fetchedGenres
                
                do {
                    self.likedTracks = try await fetchedLiked
                    self.likedTrackIds = Set(self.likedTracks.compactMap { $0.id })
                } catch {
                    print("⚠️ Không thể tải danh sách bài hát đã thích: \(error.localizedDescription)")
                    // Nếu thiếu index trên Firestore, lỗi sẽ văng ra ở đây nhưng không làm sập kho nhạc
                    self.likedTracks = []
                    self.likedTrackIds = []
                }
            } catch {
                print("❌ Lỗi tải kho nhạc: \(error)")
            }
            isLoading = false
        }
    }

    func addToPlaylist(_ track: TrackRecord) {
        if !playlist.contains(where: { $0.id == track.id }) {
            playlist.append(track)
        }
        if playlist.count == 1 { focusedTrack = track }
    }
    
    func addTracksToPlaylist(_ tracks: [TrackRecord]) {
        for track in tracks {
            if !self.playlist.contains(where: { $0.id == track.id }) {
                self.playlist.append(track)
            }
        }
        if self.playlist.count > 0 && self.focusedTrack == nil {
            self.focusedTrack = self.playlist.first
        }
    }
    
    func playTracks(_ tracks: [TrackRecord]) {
        guard let first = tracks.first else { return }
        self.playlist = tracks
        playTrack(first)
    }

    func addAlbumToPlaylist(_ album: AlbumRecord) {
        guard let albumId = album.id else { return }
        Task {
            do {
                // ✅ Tái dụng cache nếu album đã được xem — tránh Firestore read thừa
                let albumTracks = try await fetchAlbumTracks(albumId: albumId)
                var addedCount = 0
                for track in albumTracks {
                    if !self.playlist.contains(where: { $0.id == track.id }) {
                        self.playlist.append(track)
                        addedCount += 1
                    }
                }

                // Nếu Playlist đang trống, tự động focus vào bài đầu tiên của Album
                if self.focusedTrack == nil, let first = albumTracks.first {
                    self.focusedTrack = first
                }
                print(
                    "✅ Đã thêm \(addedCount) bài từ album \(album.title) vào hàng đợi."
                )
            } catch {
                print("❌ Lỗi tải track của Album: \(error)")
            }
        }
    }

    /// Tải danh sách bài hát của một Album — có cache để tránh Firestore read thừa.
    /// Cache tự động bị xoá khi `refreshLibrary()` được gọi.
    func fetchAlbumTracks(albumId: String) async throws -> [TrackRecord] {
        if let cached = albumTracksCache[albumId] {
            print("⚡️ [Cache HIT] albumTracks cho albumId: \(albumId)")
            return cached
        }
        print("🌐 [Cache MISS] Fetching albumTracks từ Firestore cho albumId: \(albumId)")
        let tracks = try await dbService.fetchTracks(forAlbumId: albumId)
        albumTracksCache[albumId] = tracks
        return tracks
    }

    /// Tải danh sách bài hát của một Playlist theo trackIds — có cache.
    /// Cache key là chuỗi ghép từ trackIds, tự động khác đi khi playlist thay đổi.
    func fetchPlaylistTracks(trackIds: [String]) async throws -> [TrackRecord] {
        if trackIds.isEmpty { return [] }
        let cacheKey = trackIds.joined(separator: ",")
        if let cached = playlistTracksCache[cacheKey] {
            print("⚡️ [Cache HIT] playlistTracks (\(trackIds.count) tracks)")
            return cached
        }
        print("🌐 [Cache MISS] Fetching playlistTracks từ Firestore (\(trackIds.count) tracks)")
        let tracks = try await dbService.fetchTracksForPlaylist(trackIds: trackIds)
        playlistTracksCache[cacheKey] = tracks
        return tracks
    }

    func removeFromPlaylist(at offsets: IndexSet) {
        playlist.remove(atOffsets: offsets)
        // Kích hoạt preloadNextTrack nằm ngầm ở publisher $playlist
    }

    func loadPlayerTracks() {
        isLoading = true
        Task {
            do {
                let result = try await dbService.fetchPaginatedTracks(
                    limit: 100,
                    after: nil,
                    sortBy: "albumId",
                    searchText: ""
                )
                self.tracks = result.tracks
            } catch {
                print("❌ Lỗi tải danh sách: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }

    func playTrack(_ track: TrackRecord) {
        if playingTrack?.id == track.id
            && (playerEngine.isPlaying || playerEngine.isBuffering)
        {
            self.isPlayerExpanded = true
            return
        }

        if !playlist.contains(where: { $0.id == track.id }) {
            playlist.append(track)
        }

        self.playingTrack = track
        self.focusedTrack = track
        self.isPlayerExpanded = true
        self.playerEngine.isBuffering = true
        self.streamCountIncrementedForCurrentTrack = false

        guard let fileID = track.googleDriveAACID ?? track.googleDriveALACID,
            !fileID.isEmpty
        else { return }

        Task {
            do {
                let isOwner = track.contributor == FirebaseAuthService.shared.currentUID
                let useWebURL = !isOwner
                let token = isOwner ? try await driveService.getValidAccessToken() : nil
                
                playerEngine.startStream(fileID: fileID, accessToken: token, useWebURL: useWebURL)

                // 🔥 Nạp đạn cho bài tiếp theo ngay sau khi Play bài hiện tại
                preloadNextTrack()
            } catch {
                print("❌ Lỗi Token: \(error.localizedDescription)")
                self.playerEngine.isBuffering = false
            }
        }
    }

    // 🔥 HÀM XỬ LÝ TẢI GỐI ĐẦU
    func preloadNextTrack() {
        guard let current = playingTrack,
            let currentIndex = playlist.firstIndex(where: {
                $0.id == current.id
            })
        else { return }

        var nextIndex = currentIndex + 1
        
        switch playbackMode {
        case .queue:
            if nextIndex >= playlist.count {
                queuedTrack = nil
                return
            }
        case .loopAll:
            if playlist.isEmpty { return }
            if nextIndex >= playlist.count { nextIndex = 0 }
        case .loopOne:
            nextIndex = currentIndex
        case .random:
            if playlist.isEmpty { return }
            if playlist.count == 1 {
                nextIndex = currentIndex
            } else {
                var randomIdx = Int.random(in: 0..<playlist.count)
                while randomIdx == currentIndex {
                    randomIdx = Int.random(in: 0..<playlist.count)
                }
                nextIndex = randomIdx
            }
        }

        let nextTrack = playlist[nextIndex]
        self.queuedTrack = nextTrack

        guard
            let fileID = nextTrack.googleDriveAACID
                ?? nextTrack.googleDriveALACID, !fileID.isEmpty
        else { return }

        Task {
            do {
                let isOwner = nextTrack.contributor == FirebaseAuthService.shared.currentUID
                let useWebURL = !isOwner
                let token = isOwner ? try await driveService.getValidAccessToken() : nil
                
                playerEngine.queueNext(fileID: fileID, accessToken: token, useWebURL: useWebURL)
            } catch {
                print("❌ Lỗi Token Preload: \(error.localizedDescription)")
            }
        }
    }

    func togglePlayPause() {
        if playerEngine.isPlaying {
            playerEngine.pause()
        } else {
            playerEngine.play()
        }
    }

    private func handleNextTrackNotification() {
        if let nextTrack = queuedTrack {
            self.playingTrack = nextTrack
            self.focusedTrack = nextTrack
            self.streamCountIncrementedForCurrentTrack = false
            playerEngine.resetForNewTrack()
            preloadNextTrack()
        } else {
            // Hết nhạc -> Ngừng
            playerEngine.pause()
            playerEngine.resetForNewTrack()
        }
    }

    // Khi người dùng cưỡng ép chuyển bài bằng tay (qua UI nút Next/Prev)
    func nextTrack() {
        guard let current = focusedTrack,
            let currentIndex = playlist.firstIndex(where: {
                $0.id == current.id
            })
        else { return }
        
        var nextIndex = currentIndex + 1
        
        switch playbackMode {
        case .queue:
            if nextIndex >= playlist.count { return }
        case .loopAll, .loopOne:
            if playlist.isEmpty { return }
            if nextIndex >= playlist.count { nextIndex = 0 }
        case .random:
            if playlist.isEmpty { return }
            if playlist.count > 1 {
                var randomIdx = Int.random(in: 0..<playlist.count)
                while randomIdx == currentIndex {
                    randomIdx = Int.random(in: 0..<playlist.count)
                }
                nextIndex = randomIdx
            } else {
                nextIndex = 0
            }
        }
        
        focusedTrack = playlist[nextIndex]
        if playerEngine.isPlaying { playTrack(playlist[nextIndex]) }
    }

    func prevTrack() {
        guard let current = focusedTrack,
            let currentIndex = playlist.firstIndex(where: {
                $0.id == current.id
            })
        else { return }
        
        var prevIndex = currentIndex - 1
        
        switch playbackMode {
        case .queue:
            if prevIndex < 0 { return }
        case .loopAll, .loopOne:
            if playlist.isEmpty { return }
            if prevIndex < 0 { prevIndex = playlist.count - 1 }
        case .random:
            if playlist.isEmpty { return }
            if playlist.count > 1 {
                var randomIdx = Int.random(in: 0..<playlist.count)
                while randomIdx == currentIndex {
                    randomIdx = Int.random(in: 0..<playlist.count)
                }
                prevIndex = randomIdx
            } else {
                prevIndex = 0
            }
        }
        
        focusedTrack = playlist[prevIndex]
        if playerEngine.isPlaying { playTrack(playlist[prevIndex]) }
    }
    
    func collapsePlayer() {
        isPlayerExpanded = false
    }
    
    func closePlayer() {
        playerEngine.pause()
        playerEngine.resetForNewTrack()
        playlist.removeAll()
        playingTrack = nil
        focusedTrack = nil
        queuedTrack = nil
        isPlayerExpanded = false
    }
    
    // MARK: - Likes
    
    func toggleLike(for track: TrackRecord) {
        guard let uid = FirebaseAuthService.shared.currentUID, let trackId = track.id else { return }
        
        let isCurrentlyLiked = likedTrackIds.contains(trackId)
        
        // Cập nhật UI ngay lập tức (Optimistic UI)
        if isCurrentlyLiked {
            likedTrackIds.remove(trackId)
            likedTracks.removeAll { $0.id == trackId }
        } else {
            likedTrackIds.insert(trackId)
            likedTracks.insert(track, at: 0) // Thêm lên đầu (mới nhất)
        }
        
        // Thực thi ngầm trên Server
        Task {
            do {
                let isLikedOnServer = try await dbService.toggleLikeTrack(track: track, currentUserId: uid)
                
                // Đồng bộ lại nếu có sai lệch
                DispatchQueue.main.async {
                    if isLikedOnServer {
                        self.likedTrackIds.insert(trackId)
                        if !self.likedTracks.contains(where: { $0.id == trackId }) {
                            self.likedTracks.insert(track, at: 0)
                        }
                    } else {
                        self.likedTrackIds.remove(trackId)
                        self.likedTracks.removeAll { $0.id == trackId }
                    }
                }
            } catch {
                print("❌ Lỗi toggle like: \(error)")
                // Revert nếu lỗi
                DispatchQueue.main.async {
                    if isCurrentlyLiked {
                        self.likedTrackIds.insert(trackId)
                        self.likedTracks.insert(track, at: 0)
                    } else {
                        self.likedTrackIds.remove(trackId)
                        self.likedTracks.removeAll { $0.id == trackId }
                    }
                }
            }
        }
    }
    
    // MARK: - Media Player Control Center
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            self.playerEngine.play()
            self.updateNowPlayingInfo()
            return .success
        }
        
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            self.playerEngine.pause()
            self.updateNowPlayingInfo()
            return .success
        }
        
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            self.nextTrack()
            if let track = self.focusedTrack {
                self.playTrack(track)
            }
            return .success
        }
        
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            self.prevTrack()
            if let track = self.focusedTrack {
                self.playTrack(track)
            }
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            if let positionEvent = event as? MPChangePlaybackPositionCommandEvent {
                self.playerEngine.seek(to: positionEvent.positionTime)
                self.updateNowPlayingInfo(overrideCurrentTime: positionEvent.positionTime)
                return .success
            }
            return .commandFailed
        }
    }
    
    func updateNowPlayingInfo(overrideCurrentTime: TimeInterval? = nil) {
        #if os(iOS) || os(macOS)
        guard let track = playingTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: overrideCurrentTime ?? playerEngine.currentTime,
            MPMediaItemPropertyPlaybackDuration: playerEngine.duration,
            MPNowPlayingInfoPropertyPlaybackRate: playerEngine.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        
        if let coverDriveID = track.coverDriveID,
           let cachedImage = ImageCache.shared.get(forKey: coverDriveID) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: cachedImage.size) { _ in
                return cachedImage
            }
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        #endif
    }
}
