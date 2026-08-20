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
    private var currentItemCancellables = Set<AnyCancellable>()
    
    /// Kiểm tra xem AVQueuePlayer có bài hát chờ kế tiếp trong hàng đợi hay không
    var hasQueuedItem: Bool {
        return (player?.items().count ?? 0) > 1
    }
    
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
        
        if player == nil {
            let newPlayer = AVQueuePlayer(playerItem: playerItem)
            player = newPlayer
            observePlayerStatus(newPlayer)
            observeCurrentItem(newPlayer)
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
    @discardableResult
    func queueNext(fileID: String, accessToken: String?, useWebURL: Bool = false) -> Bool {
        guard let player = player else { return false }
        
        // Xoá các bài đang chờ cũ (nếu người dùng vừa đổi ý), chừa lại duy nhất bài đang phát
        if player.items().count > 1 {
            for item in player.items().dropFirst() {
                player.remove(item)
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
        
        guard let url = URL(string: urlString) else { return false }
        
        let asset: AVURLAsset
        if let headers = headers {
            asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        } else {
            asset = AVURLAsset(url: url)
        }
        let nextItem = AVPlayerItem(asset: asset)
        
        // Nạp bài mới vào hàng đợi chạy ngầm
        if player.canInsert(nextItem, after: nil) {
            player.insert(nextItem, after: nil)
            print("📦 [Engine] Đã tải gối đầu sẵn sàng track tiếp theo!")
            return true
        } else {
            print("⚠️ [Engine] Không thể nạp track tiếp theo vào AVQueuePlayer.")
            return false
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
                guard let self = self else { return }
                self.currentItemCancellables.removeAll()
                if let newItem = newItem {
                    self.attachObservers(to: newItem)
                } else {
                    self.isBuffering = false
                }
            }
            .store(in: &cancellables)
    }
    
    // 🔥 GẮN BỘ THEO DÕI TOÀN DIỆN CHO TỪNG PLAYER ITEM (STATUS, BUFFER, FINISH, ERROR)
    private func attachObservers(to item: AVPlayerItem) {
        // 1. Theo dõi trạng thái item (readyToPlay / failed)
        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                switch status {
                case .readyToPlay:
                    self.isBuffering = false
                    print("🔊 [AudioPlayerEngine] PlayerItem READY TO PLAY")
                    NotificationCenter.default.post(name: .init("CurrentTrackReadyToPlay"), object: nil)
                    if self.isPlaying {
                        self.play()
                    }
                case .failed:
                    self.isBuffering = false
                    self.isPlaying = false
                    print("❌ [AudioPlayerEngine] PlayerItem FAILED: \(item.error?.localizedDescription ?? "unknown error")")
                    NotificationCenter.default.post(name: .init("TrackPlaybackFailed"), object: item.error)
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
            .store(in: &currentItemCancellables)
        
        // 2. Theo dõi Buffer cạn kiệt (Buffer Empty)
        item.publisher(for: \.isPlaybackBufferEmpty)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEmpty in
                if isEmpty {
                    self?.isBuffering = true
                }
            }
            .store(in: &currentItemCancellables)
        
        // 3. Theo dõi Buffer phục hồi đủ để phát tiếp (Buffer Likely To Keep Up)
        item.publisher(for: \.isPlaybackLikelyToKeepUp)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] likely in
                guard let self = self else { return }
                if likely {
                    self.isBuffering = false
                    if self.isPlaying {
                        self.play()
                    }
                }
            }
            .store(in: &currentItemCancellables)
        
        // 4. Theo dõi tiến trình tải bộ đệm (loadedTimeRanges)
        item.publisher(for: \.loadedTimeRanges)
            .receive(on: RunLoop.main)
            .sink { [weak self] timeRanges in
                guard let self = self else { return }
                if let firstRange = timeRanges.first?.timeRangeValue {
                    let start = firstRange.start.seconds
                    let duration = firstRange.duration.seconds
                    self.bufferedTime = start + duration
                }
            }
            .store(in: &currentItemCancellables)
        
        // 5. Theo dõi kết thúc bài hát
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.playerItemDidReachEnd()
            }
            .store(in: &currentItemCancellables)
    }
    
    private func observePlayerStatus(_ player: AVPlayer) {
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                switch status {
                case .playing:
                    self.isPlaying = true
                    self.isBuffering = false
                case .paused:
                    self.isPlaying = false
                    self.isBuffering = false
                case .waitingToPlayAtSpecifiedRate:
                    if let currentItem = player.currentItem {
                        if currentItem.status == .failed {
                            self.isBuffering = false
                        } else {
                            self.isBuffering = true
                        }
                    } else {
                        self.isBuffering = false
                    }
                @unknown default: break
                }
            }
            .store(in: &cancellables)
    }
    
    func play() {
        player?.rate = 1.0
        player?.play()
        isPlaying = true
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
    }
    
    func seek(to time: TimeInterval) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 1000))
    }
    
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
