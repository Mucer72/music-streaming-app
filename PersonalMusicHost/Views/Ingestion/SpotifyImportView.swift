//
//  SpotifyImportView.swift
//  PersonalMusicHost
//
//  Màn hình nhập link Spotify và thực hiện import pipeline.
//  - macOS:  Truy cập qua nút "Spotify Import" trong IngestionView
//  - iOS:    Màn hình riêng, truy cập qua AppRoute.spotifyImport
//
//  Layout:
//    ┌─────────────────────────────────────────────────────────┐
//    │ URL Input Bar                                           │
//    ├─────────────────────────────────────────────────────────┤
//    │ Left: Metadata + Match Preview      Right: Import Log   │
//    ├─────────────────────────────────────────────────────────┤
//    │ Upload Config (Genre + Public toggle)                   │
//    ├─────────────────────────────────────────────────────────┤
//    │ Action Buttons                                          │
//    └─────────────────────────────────────────────────────────┘
//

import SwiftUI

struct SpotifyImportView: View {
    @EnvironmentObject var viewModel: SpotifyImportViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showLog: Bool = false
    @State private var visibleCandidatesCount: Int = 5

    private var canFetch: Bool {
        !viewModel.spotifyURLText.trimmingCharacters(in: .whitespaces).isEmpty &&
        viewModel.importState == .idle ||
        viewModel.importState == .failed("") // sẽ check actual bên dưới
    }

    private var isFetching: Bool {
        viewModel.importState == .fetchingMetadata ||
        viewModel.importState == .searching ||
        viewModel.importState == .scoring
    }

    private var isConfirmDisabled: Bool {
        viewModel.importState != .readyToUpload ||
        viewModel.selectedGenreId.isEmpty ||
        authViewModel.status != .signedIn
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // ── Header ──────────────────────────────────────────────
                headerSection

                // ── URL Input ───────────────────────────────────────────
                urlInputSection

                // ── Progress Bar ─────────────────────────────────────────
                if viewModel.importState != .idle {
                    progressSection
                }

                // ── Main Content ─────────────────────────────────────────
                #if os(macOS)
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 16) {
                        if let metadata = viewModel.fetchedMetadata {
                            metadataPreviewCard(metadata: metadata)
                        }
                        if !viewModel.candidates.isEmpty {
                            candidateSelectionList
                        }
                        if viewModel.fetchedMetadata != nil {
                            uploadConfigSection
                        }
                        actionButtons
                    }
                    .frame(maxWidth: .infinity)

                    if showLog {
                        ImportConsoleView()
                            .frame(width: 320)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut, value: showLog)
                #else
                // iOS: vertical layout
                VStack(spacing: 16) {
                    if let metadata = viewModel.fetchedMetadata {
                        metadataPreviewCard(metadata: metadata)
                    }
                    if !viewModel.candidates.isEmpty {
                        candidateSelectionList
                    }
                    if viewModel.fetchedMetadata != nil {
                        uploadConfigSection
                    }
                    actionButtons
                    if showLog {
                        ImportConsoleView()
                            .frame(minHeight: 200)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut, value: showLog)
                #endif
            }
            .padding(20)
        }
        .navigationTitle("Spotify Import")
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showLog.toggle()
                } label: {
                    Label(showLog ? "Hide Log" : "Show Log", systemImage: "terminal")
                }
                .help("Toggle import log console")
            }
        }
        #endif
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "music.note")
                    .foregroundColor(.green)
                    .font(.title2)
                Text("Import từ Spotify")
                    .font(.title2).bold()
                Spacer()
                
                #if os(iOS)
                Button { showLog.toggle() } label: {
                    Image(systemName: showLog ? "terminal.fill" : "terminal")
                        .foregroundColor(.secondary)
                }
                #endif
            }
            Text("Dán link Spotify, ứng dụng sẽ tự tìm và tải bài hát rồi đẩy lên Drive.")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var urlInputSection: some View {
        HStack(spacing: 12) {
            HStack {
                Image(systemName: "link")
                    .foregroundColor(.secondary)
                    .padding(.leading, 10)
                TextField("https://open.spotify.com/track/...", text: $viewModel.spotifyURLText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                #endif
                if !viewModel.spotifyURLText.isEmpty {
                    Button {
                        viewModel.spotifyURLText = ""
                        viewModel.reset()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                }
            }
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(urlBorderColor, lineWidth: 1.5)
            )

            Button(action: { viewModel.startImport() }) {
                HStack(spacing: 6) {
                    if isFetching {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                    Text(isFetching ? "Đang tìm..." : "Fetch")
                        .fontWeight(.semibold)
                }
                .frame(minWidth: 90)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(isFetching || viewModel.importState == .downloading ||
                      viewModel.importState == .uploading)
        }
    }

    private var progressSection: some View {
        VStack(spacing: 6) {
            ProgressView(value: viewModel.progress)
                .tint(progressTint)
            Text(progressLabel)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func metadataPreviewCard(metadata: SpotifyTrackMetadata) -> some View {
        HStack(spacing: 14) {
            // Cover art
            Group {
                if let data = metadata.coverImageData,
                   let image = platformImage(from: data) {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .overlay(Image(systemName: "music.note").foregroundColor(.secondary))
                }
            }
            .frame(width: 72, height: 72)
            .cornerRadius(10)
            .shadow(radius: 4)

            VStack(alignment: .leading, spacing: 4) {
                Label("Spotify Metadata", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                Text(metadata.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(metadata.artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if !metadata.album.isEmpty && metadata.album != "Spotify" {
                    Text(metadata.album)
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.green.opacity(0.3), lineWidth: 1))
    }

    private var candidateSelectionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Kết quả tìm kiếm", systemImage: "list.dash")
                .font(.caption)
                .foregroundColor(.orange)
            
            ForEach(viewModel.candidates.prefix(visibleCandidatesCount)) { candidate in
                HStack(spacing: 12) {
                    // Radio button
                    Button {
                        viewModel.selectedCandidate = candidate
                    } label: {
                        Image(systemName: viewModel.selectedCandidate?.id == candidate.id ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(.orange)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    
                    // Info
                    VStack(alignment: .leading, spacing: 3) {
                        Text(candidate.title)
                            .font(.subheadline).bold()
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            Text(candidate.uploaderName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            
                            Label(formatDuration(candidate.durationSeconds), systemImage: "clock")
                                .font(.caption2)
                                .foregroundColor(candidate.durationSeconds < 60 ? .red : .secondary)
                                
                            sourceBadge(for: candidate)
                        }
                    }
                    
                    Spacer()
                    
                    // Recommended badge cho bài chuẩn nhất
                    if viewModel.candidates.first?.id == candidate.id {
                        Text("Khớp nhất")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(4)
                            .padding(.trailing, 4)
                    }
                }
                .padding(10)
                .background(viewModel.selectedCandidate?.id == candidate.id ? Color.orange.opacity(0.1) : Color.clear)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(viewModel.selectedCandidate?.id == candidate.id ? Color.orange.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1))
            }
            
            // Nút "Xem thêm"
            if viewModel.candidates.count > visibleCandidatesCount {
                Button(action: {
                    withAnimation {
                        visibleCandidatesCount += 5
                    }
                }) {
                    Text("Xem thêm các kết quả khác...")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }

    private var uploadConfigSection: some View {
        VStack(spacing: 12) {
            // Genre picker
            HStack {
                Label("Thể loại:", systemImage: "tag.fill")
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $viewModel.selectedGenreId) {
                    Text("Chưa chọn").tag("")
                    ForEach(viewModel.availableGenres) { genre in
                        Text(genre.name).tag(genre.id ?? "")
                    }
                }
                .frame(maxWidth: 180)
            }

            // Public toggle
            HStack {
                Label("Công khai trên thư viện:", systemImage: "globe")
                    .foregroundColor(.secondary)
                Spacer()
                Toggle("", isOn: $viewModel.isPublic)
                    .labelsHidden()
            }

            // Auth warning
            if authViewModel.status != .signedIn {
                Label("Cần đăng nhập Google để upload lên Drive.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Confirm & Upload
            Button(action: { viewModel.confirmAndUpload() }) {
                HStack(spacing: 8) {
                    if viewModel.importState == .downloading ||
                       viewModel.importState == .tagging ||
                       viewModel.importState == .uploading {
                        ProgressView().controlSize(.small)
                    } else if viewModel.importState == .completed {
                        Image(systemName: "checkmark.circle.fill")
                    } else {
                        Image(systemName: "icloud.and.arrow.up.fill")
                    }
                    Text(confirmButtonLabel)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.importState == .completed ? .green : .blue)
            .disabled(isConfirmDisabled)

            // Reset
            if viewModel.importState != .idle {
                Button(action: { viewModel.reset() }) {
                    Image(systemName: "arrow.counterclockwise")
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.importState == .downloading ||
                          viewModel.importState == .uploading)
            }
        }
    }

    // MARK: - Helpers

    private var urlBorderColor: Color {
        switch viewModel.importState {
        case .failed: return .red
        case .completed: return .green
        default: return Color.secondary.opacity(0.3)
        }
    }

    private var progressTint: Color {
        switch viewModel.importState {
        case .failed: return .red
        case .completed: return .green
        case .downloading, .uploading: return .blue
        default: return .orange
        }
    }

    private var progressLabel: String {
        switch viewModel.importState {
        case .idle: return ""
        case .fetchingMetadata: return "Đang lấy metadata Spotify..."
        case .searching: return "Đang tìm kiếm audio..."
        case .scoring: return "Đang tính điểm tương đồng..."
        case .readyToUpload: return "Sẵn sàng — kiểm tra thông tin và ấn Import"
        case .downloading: return "Đang tải audio..."
        case .tagging: return "Đang gắn metadata..."
        case .uploading: return "Đang upload lên Drive..."
        case .completed: return "Hoàn tất!"
        case .failed(let msg): return "Lỗi: \(msg)"
        }
    }

    private var confirmButtonLabel: String {
        switch viewModel.importState {
        case .downloading: return "Đang tải..."
        case .tagging: return "Đang gắn tag..."
        case .uploading: return "Đang upload..."
        case .completed: return "Hoàn tất!"
        default: return "Import & Upload lên Drive"
        }
    }

    private func scoreBadgeColor(_ score: Double) -> Color {
        if score >= 0.8 { return .green }
        if score >= 0.7 { return .orange }
        return .red
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    @ViewBuilder
    private func sourceBadge(for candidate: AudioCandidate) -> some View {
        if candidate.isYTMusic {
            Text("YT Music")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.8))
                .cornerRadius(4)
        } else {
            Text("YouTube")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.gray)
                .cornerRadius(4)
        }
    }

    // Cross-platform image từ Data
    private func platformImage(from data: Data) -> Image? {
        #if os(macOS)
        if let nsImage = NSImage(data: data) {
            return Image(nsImage: nsImage)
        }
        #else
        if let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        }
        #endif
        return nil
    }
}
