//
//  AudioPlayerEngine.swift
//  PersonalMusicHost
//
//  Created by TwentyMikeyOne on 28/6/26.
//

import Foundation
import AVFoundation
import Combine

@MainActor
class AudioPlayerEngine: ObservableObject {
    @Published var isPlaying = false
    @Published var isBuffering = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var bufferedTime: TimeInterval = 0
    
    // 🔥 NÂNG CẤP LÊN AVQueuePlayer ĐỂ XỬ LÝ HÀNG ĐỢI
    private var player: AVQueuePlayer?
    
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var bufferCancellable: AnyCancellable?
    private var endItemCancellable: AnyCancellable?
    
    init() { setupAudioSession() }
    
    private func setupAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }
    
    func startStream(fileID: String, accessToken: String?, useWebURL: Bool = false) {
        resetForNewTrack()
        self.isBuffering = true
        
        let urlString: String
        var headers: [String: String]? = nil
        
        if useWebURL {
            urlString = "https://drive.google.com/uc?export=download&id=\(fileID)"
        } else {
            urlString = "https://www.googleapis.com/drive/v3/files/\(fileID)?alt=media"
            if let token = accessToken {
                headers = ["Authorization": "Bearer \(token)"]
            }
        }
        
        guard let url = URL(string: urlString) else { return }
        let asset: AVURLAsset
        if let headers = headers {
            asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        } else {
            asset = AVURLAsset(url: url)
        }
        let playerItem = AVPlayerItem(asset: asset)
        
        
        endItemCancellable?.cancel()
        endItemCancellable = NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            .sink { [weak self] _ in
                self?.playerItemDidReachEnd()
            }
        
        if player == nil {
            let newPlayer = AVQueuePlayer(playerItem: playerItem)
            player = newPlayer
            observePlayerStatus(newPlayer)
            observeCurrentItem(newPlayer) // Tự động theo dõi khi bài hát chuyển tiếp
        } else {
            player?.removeAllItems()
            if player?.canInsert(playerItem, after: nil) == true {
                player?.replaceCurrentItem(with: playerItem)
            }
        }
        
        observeTime()
        play()
    }
    
    // 🔥 CHỨC NĂNG TẢI GỐI ĐẦU
    func queueNext(fileID: String, accessToken: String?, useWebURL: Bool = false) {
        guard let player = player else { return }
        
        // Xoá các bài đang chờ cũ (nếu người dùng vừa đổi ý), chừa lại duy nhất bài đang phát
        if player.items().count > 1 {
            for item in player.items().dropFirst() {
                player.remove(item)
                NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)
            }
        }
        
        let urlString: String
        var headers: [String: String]? = nil
        
        if useWebURL {
            urlString = "https://drive.google.com/uc?export=download&id=\(fileID)"
        } else {
            urlString = "https://www.googleapis.com/drive/v3/files/\(fileID)?alt=media"
            if let token = accessToken {
                headers = ["Authorization": "Bearer \(token)"]
            }
        }
        
        guard let url = URL(string: urlString) else { return }
        
        let asset: AVURLAsset
        if let headers = headers {
            asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        } else {
            asset = AVURLAsset(url: url)
        }
        let nextItem = AVPlayerItem(asset: asset)
        
        NotificationCenter.default.addObserver(self, selector: #selector(playerItemDidReachEnd), name: .AVPlayerItemDidPlayToEndTime, object: nextItem)
        
        // Nạp bài mới vào hàng đợi chạy ngầm
        if player.canInsert(nextItem, after: nil) {
            player.insert(nextItem, after: nil)
            print("📦 [Engine] Đã tải gối đầu sẵn sàng track tiếp theo!")
        }
    }
    
    func resetForNewTrack() {
        self.currentTime = 0
        self.duration = 0
        self.bufferedTime = 0
    }
    
    // 🔥 THEO DÕI SỰ CHUYỂN BÀI TỰ NHIÊN CỦA QUEUE
    private func observeCurrentItem(_ player: AVQueuePlayer) {
        player.publisher(for: \.currentItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newItem in
                guard let self = self, let newItem = newItem else { return }
                self.observeBufferProgress(for: newItem) // Nối lại thanh màu xám cho bài mới
            }
            .store(in: &cancellables)
    }
    
    private func observeBufferProgress(for playerItem: AVPlayerItem) {
        bufferCancellable?.cancel()
        bufferCancellable = playerItem.publisher(for: \.loadedTimeRanges)
            .receive(on: RunLoop.main)
            .sink { [weak self] timeRanges in
                guard let self = self else { return }
                if let firstRange = timeRanges.first?.timeRangeValue {
                    let start = firstRange.start.seconds
                    let duration = firstRange.duration.seconds
                    self.bufferedTime = start + duration
                }
            }
    }
    
    private func observePlayerStatus(_ player: AVPlayer) {
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                switch status {
                case .playing:
                    self.isPlaying = true; self.isBuffering = false
                case .paused:
                    self.isPlaying = false; self.isBuffering = false
                case .waitingToPlayAtSpecifiedRate:
                    self.isPlaying = true; self.isBuffering = true
                @unknown default: break
                }
            }
            .store(in: &cancellables)
    }
    
    func play() { player?.rate = 1.0; player?.play(); isPlaying = true }
    func pause() { player?.pause(); isPlaying = false }
    func seek(to time: TimeInterval) { player?.seek(to: CMTime(seconds: time, preferredTimescale: 1000)) }
    
    func setScrubbingRate(speed: Float) {
        guard let player = player, let item = player.currentItem else { return }
        if speed < 0 && item.canPlayFastReverse { player.rate = speed }
        else if speed > 0 && item.canPlayFastForward { player.rate = speed }
        else { player.rate = 0 }
    }
    
    private func observeTime() {
        guard let player = player else { return }
        if let observer = timeObserver { player.removeTimeObserver(observer) }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.02, preferredTimescale: 1000), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self, let currentItem = self.player?.currentItem else { return }
                self.currentTime = time.seconds
                let itemDuration = currentItem.duration.seconds
                self.duration = itemDuration.isNaN ? 0 : itemDuration
            }
        }
    }
    
    @objc private func playerItemDidReachEnd() {
        NotificationCenter.default.post(name: .init("TrackDidNeedNext"), object: nil)
    }
    
    deinit {
        if let observer = timeObserver, let player = player { player.removeTimeObserver(observer) }
        NotificationCenter.default.removeObserver(self)
    }
}
