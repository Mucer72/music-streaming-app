//
//  BackgroundDownloadIndicator.swift
//  PersonalMusicHost
//

import SwiftUI

struct BackgroundDownloadIndicator: View {
    @EnvironmentObject var viewModel: SpotifyImportViewModel
    @State private var isSpinning = false
    @State private var showInfo = false
    
    private var isFailed: Bool {
        if case .failed = viewModel.importState { return true }
        return false
    }
    
    var isVisible: Bool {
        viewModel.importState == .downloading || 
        viewModel.importState == .tagging || 
        viewModel.importState == .uploading ||
        viewModel.importState == .completed ||
        isFailed
    }
    
    var body: some View {
        if isVisible {
            HStack(spacing: 8) {
                // Turntable Circle
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 3)
                        .frame(width: 36, height: 36)
                    
                    if viewModel.importState == .downloading && viewModel.downloadPercentage > 0 {
                        Circle()
                            .trim(from: 0, to: CGFloat(viewModel.downloadPercentage))
                            .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 36, height: 36)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.2), value: viewModel.downloadPercentage)
                    } else if viewModel.importState == .completed {
                        Circle()
                            .stroke(Color.green, lineWidth: 3)
                            .frame(width: 36, height: 36)
                    } else if isFailed {
                        Circle()
                            .stroke(Color.red, lineWidth: 3)
                            .frame(width: 36, height: 36)
                    } else {
                        // Indeterminate spinning for tagging/uploading
                        Circle()
                            .trim(from: 0, to: 0.75)
                            .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 36, height: 36)
                            .rotationEffect(Angle(degrees: isSpinning ? 360 : 0))
                            .animation(Animation.linear(duration: 1).repeatForever(autoreverses: false), value: isSpinning)
                            .onAppear { isSpinning = true }
                    }
                    
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(iconColor)
                }
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showInfo.toggle()
                    }
                }
                .onChange(of: viewModel.importState) { newState in
                    let isNewFailed: Bool
                    if case .failed = newState { isNewFailed = true } else { isNewFailed = false }
                    
                    if newState == .downloading {
                        withAnimation { showInfo = true }
                    } else if newState == .completed || isNewFailed {
                        withAnimation { showInfo = true }
                        // Tự ẩn sau 4 giây khi hoàn tất hoặc có lỗi
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            let currentFailed: Bool
                            if case .failed = viewModel.importState { currentFailed = true } else { currentFailed = false }
                            
                            if viewModel.importState == .completed || currentFailed {
                                viewModel.reset()
                            }
                        }
                    }
                }
                
                // Expanded Info Card (to the right)
                if showInfo {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.fetchedMetadata?.title ?? "Đang tiến hành...")
                                .font(.caption).bold()
                                .lineLimit(1)
                            if let artist = viewModel.fetchedMetadata?.artist {
                                Text(artist)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        
                        Text(statusText)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(iconColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(iconColor.opacity(0.15))
                            .cornerRadius(6)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .onTapGesture {
                        withAnimation { showInfo.toggle() }
                    }
                }
            }
            .padding(.top, 8) // Căn ngang với nút Tải nhạc trên NavigationBar
            .padding(.leading, 16)
        }
    }
    
    private var iconName: String {
        if isFailed { return "xmark" }
        switch viewModel.importState {
        case .downloading: return "opticaldisc"
        case .tagging: return "tag.fill"
        case .uploading: return "icloud.and.arrow.up.fill"
        case .completed: return "checkmark"
        default: return "music.note"
        }
    }
    
    private var iconColor: Color {
        if isFailed { return .red }
        switch viewModel.importState {
        case .downloading, .completed: return .green
        case .tagging, .uploading: return .orange
        default: return .secondary
        }
    }
    
    private var statusText: String {
        if isFailed { return "Lỗi" }
        switch viewModel.importState {
        case .downloading:
            return viewModel.downloadPercentage > 0 ? String(format: "%.0f%%", viewModel.downloadPercentage * 100) : "Đang lấy link..."
        case .tagging: return "Gắn thẻ"
        case .uploading: return "Lưu Cloud"
        case .completed: return "Xong!"
        default: return ""
        }
    }
}
