//
//  AudioPipelineService.swift
//  PersonalMusicHost
//
//  Created by TwentyMikeyOne on 24/6/26.
//

import AVFoundation

// Định nghĩa các lỗi
enum PipelineError: Error {
    case trackLoadFailed
    case exportFailed(String)
    case readerWriterSetupFailed(String)
}

class AudioPipelineService {
    
    // --------------------------------------------------------
    // 1. TRÍCH XUẤT METADATA
    // --------------------------------------------------------
    
    private func isNativelySupported(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["m4a", "mp3", "wav", "alac", "aiff", "caf", "flac", "aac"].contains(ext)
    }
    
    func extractMetadata(from url: URL) async throws -> AudioTrack {
        if !isNativelySupported(url: url) {
            return try await FFmpegService.shared.extractMetadata(from: url)
        }
        
        let asset = AVURLAsset(url: url)
        var track = AudioTrack(sourceURL: url)
        
        do {
            let duration = try await asset.load(.duration)
            track.duration = CMTimeGetSeconds(duration)
        } catch {
            print("⚠️ Không thể đọc thời lượng cho \(url.lastPathComponent)")
        }
        
        do {
            let metadata = try await asset.load(.commonMetadata)
            for item in metadata {
                if let key = item.commonKey?.rawValue {
                    if key == AVMetadataKey.commonKeyTitle.rawValue {
                        track.title = try await item.load(.stringValue) ?? "Unknown Title"
                    } else if key == AVMetadataKey.commonKeyArtist.rawValue {
                        track.artist = try await item.load(.stringValue) ?? "Unknown Artist"
                    } else if key == AVMetadataKey.commonKeyAlbumName.rawValue {
                        track.albumName = try await item.load(.stringValue) ?? ""
                    } else if key == AVMetadataKey.commonKeyCreationDate.rawValue {
                        if let dateString = try? await item.load(.stringValue),
                           let yearString = dateString.components(separatedBy: "-").first,
                           let year = Int(yearString) {
                            track.releaseYear = year
                        }
                    }
                }
                
                // Trích xuất Track Number từ ID3 hoặc iTunes metadata
                let identifier = item.identifier
                if identifier == .iTunesMetadataTrackNumber || identifier == .id3MetadataTrackNumber {
                    if let stringValue = try? await item.load(.stringValue) {
                        // Thường có dạng "1" hoặc "1/10"
                        if let first = stringValue.components(separatedBy: "/").first, let num = Int(first) {
                            track.trackNumber = num
                        }
                    } else if let intValue = try? await item.load(.numberValue) as? Int {
                        track.trackNumber = intValue
                    }
                } else if identifier == .id3MetadataYear || identifier == .iTunesMetadataReleaseDate {
                    if let stringValue = try? await item.load(.stringValue),
                       let yearString = stringValue.components(separatedBy: "-").first,
                       let year = Int(yearString) {
                        track.releaseYear = year
                    } else if let intValue = try? await item.load(.numberValue) as? Int {
                        track.releaseYear = intValue
                    }
                }
            }
        } catch {
            print("⚠️ Không thể đọc metadata cho \(url.lastPathComponent)")
        }
        
        if track.title == "Unknown Title" {
            track.title = url.deletingPathExtension().lastPathComponent
        }
        
        return track
    }
    
    // --------------------------------------------------------
    // 2. ĐIỀU PHỐI LUỒNG CONVERT ĐỒNG NHẤT
    // --------------------------------------------------------
    func convert(track: AudioTrack, format: OutputFormat, outputDir: URL) async throws -> URL {
        let fileName = track.sourceURL.deletingPathExtension().lastPathComponent
        let outputURL = outputDir.appendingPathComponent("\(fileName)_\(format.rawValue).m4a")
        
        LocalFileService().removeFileIfExists(at: outputURL)
        
        var processTrack = track
        var tempWavURL: URL? = nil
        
        // Tiền xử lý (Pre-processing) cho định dạng không hỗ trợ
        if !isNativelySupported(url: track.sourceURL) {
            let wavURL = try await FFmpegService.shared.decodeToWav(sourceURL: track.sourceURL)
            processTrack.sourceURL = wavURL
            tempWavURL = wavURL
        }
        
        do {
            let exporter = AudioExporter()
            let finalURL = try await exporter.export(track: processTrack, outputURL: outputURL, format: format)
            
            // Dọn dẹp file tạm
            if let tempWav = tempWavURL {
                LocalFileService().removeFileIfExists(at: tempWav)
            }
            
            return finalURL
        } catch {
            if let tempWav = tempWavURL { LocalFileService().removeFileIfExists(at: tempWav) }
            throw error
        }
    }
}

// --------------------------------------------------------
// 3. LÕI MÃ HOÁ (Xử lý chung cho cả AAC & ALAC)
// --------------------------------------------------------
private final class AudioExporter: @unchecked Sendable {
    private var assetWriter: AVAssetWriter?
    private var assetReader: AVAssetReader?
    private var writerInput: AVAssetWriterInput?
    private var readerOutput: AVAssetReaderTrackOutput?
    
    func export(track: AudioTrack, outputURL: URL, format: OutputFormat) async throws -> URL {
        
        // --- FIX 1 & 2: ĐƯA ASSET OPTIONS LÊN TRÊN VÀ DÙNG CHỮ 'PRECISE' ---
        let assetOptions: [String: Any] = [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ]
        let asset = AVURLAsset(url: track.sourceURL, options: assetOptions)
        
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw PipelineError.trackLoadFailed
        }
        
        // --------------------------------------------------------
        // 1. ĐỌC ĐỘNG SAMPLE RATE VÀ BIT DEPTH TỪ FILE GỐC
        // --------------------------------------------------------
        let formatDescriptions = try await audioTrack.load(.formatDescriptions)
        var sourceSampleRate: Double = 44100.0 // Chuẩn CD mặc định
        var sourceBitDepth: Int = 16           // Chuẩn CD mặc định
        
        if let formatDesc = formatDescriptions.first,
           let streamDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
            
            sourceSampleRate = streamDesc.pointee.mSampleRate
            if sourceSampleRate == 0 { sourceSampleRate = 44100.0 }
            
            let bitsPerChannel = streamDesc.pointee.mBitsPerChannel
            if bitsPerChannel > 0 {
                sourceBitDepth = Int(bitsPerChannel)
            }
        }
        
        // --------------------------------------------------------
        // 2. CẤU HÌNH READER BẰNG MỐC THỜI GIAN NANO-GIÂY
        // --------------------------------------------------------
        assetReader = try AVAssetReader(asset: asset)
        
        let timescale: CMTimeScale = 1_000_000_000
        let startCMTime = CMTime(seconds: track.startTime, preferredTimescale: timescale)
        let durationCMTime = CMTime(seconds: track.duration, preferredTimescale: timescale)
        
        assetReader?.timeRange = CMTimeRange(start: startCMTime, duration: durationCMTime)
        
        let readerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: sourceBitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerSettings)
        if let output = readerOutput {
            assetReader?.add(output)
        }
        
        // --------------------------------------------------------
        // 3. CẤU HÌNH WRITER
        // --------------------------------------------------------
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        
        var channelLayout = AudioChannelLayout()
        channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        let layoutData = Data(bytes: &channelLayout, count: MemoryLayout<AudioChannelLayout>.size)
        
        let outputSettings: [String: Any]
        switch format {
        case .aac:
            let targetSampleRate = min(sourceSampleRate, 48000.0)
            outputSettings = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: targetSampleRate,
                AVEncoderBitRateKey: 256000,
                AVChannelLayoutKey: layoutData
            ]
        case .alac:
            outputSettings = [
                AVFormatIDKey: kAudioFormatAppleLossless,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: sourceSampleRate,
                AVEncoderBitDepthHintKey: sourceBitDepth,
                AVChannelLayoutKey: layoutData
            ]
        }
        
        writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        writerInput?.expectsMediaDataInRealTime = false
        
        if let writerInput = writerInput, let writer = assetWriter, writer.canAdd(writerInput) {
            writer.add(writerInput)
        }
        
        assetWriter?.startWriting()
        assetReader?.startReading()
        
        // --- FIX 3: ĐỒNG BỘ THỜI GIAN GHI VỚI THỜI GIAN ĐỌC ---
        assetWriter?.startSession(atSourceTime: startCMTime)
        
        // --------------------------------------------------------
        // 4. LUỒNG BƠM DỮ LIỆU
        // --------------------------------------------------------
        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "com.musicpipeline.export")
            writerInput?.requestMediaDataWhenReady(on: queue) {
                guard let writerInput = self.writerInput,
                      let readerOutput = self.readerOutput,
                      let assetWriter = self.assetWriter else { return }
                
                while writerInput.isReadyForMoreMediaData {
                    if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(sampleBuffer)
                    } else {
                        writerInput.markAsFinished()
                        assetWriter.finishWriting {
                            if assetWriter.status == .completed {
                                continuation.resume(returning: outputURL)
                            } else {
                                let errorMsg = assetWriter.error?.localizedDescription ?? "Unknown error"
                                continuation.resume(throwing: PipelineError.exportFailed(errorMsg))
                            }
                        }
                        break
                    }
                }
            }
        }
    }
}
