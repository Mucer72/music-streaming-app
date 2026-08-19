//
//  ImportConsoleView.swift
//  PersonalMusicHost
//
//  Terminal-style log console cho Spotify Import Pipeline.
//  Tương tự ConsoleView nhưng bind vào SpotifyImportViewModel.logs.
//

import SwiftUI

struct ImportConsoleView: View {
    @EnvironmentObject var viewModel: SpotifyImportViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // macOS window chrome dots
            HStack {
                Circle().fill(.red).frame(width: 10, height: 10)
                Circle().fill(.yellow).frame(width: 10, height: 10)
                Circle().fill(.green).frame(width: 10, height: 10)
                Spacer()
                Text("Import Log")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.gray)
                Spacer()
            }
            .padding(10)
            .background(Color.black.opacity(0.8))

            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.logs.indices, id: \.self) { index in
                            Text(viewModel.logs[index])
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.green)
                                .id(index)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: viewModel.logs.count) {
                        withAnimation {
                            proxy.scrollTo(viewModel.logs.count - 1, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color.black.opacity(0.9))
        }
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}
