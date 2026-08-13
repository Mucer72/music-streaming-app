//
//  IngestionHeaderView.swift
//  PersonalMusicHost
//
//  Top bar for IngestionView: title, inline progress indicator,
//  log toggle button, and the main pipeline start button.
//

import SwiftUI

struct IngestionHeaderView: View {
    @EnvironmentObject var viewModel: PipelineViewModel
    @Binding var showLogs: Bool
    let isStartDisabled: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("UPLOAD & CONVERT TOOL")
                    .font(.title2).fontWeight(.black).tracking(1.5)

                if viewModel.isProcessing || viewModel.progress > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: viewModel.progress)
                            .progressViewStyle(.linear)
                            .tint(.blue)
                        Text(viewModel.currentTaskName)
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: 400)
                } else {
                    Text("Ready to process")
                        .font(.subheadline).foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(action: { showLogs.toggle() }) {
                Image(systemName: "terminal")
                    .foregroundColor(showLogs ? .blue : .primary)
            }
            .help("Toggle Console")

            Button(action: { viewModel.startPipeline() }) {
                HStack {
                    Image(systemName: viewModel.isProcessing ? "gearshape.fill" : "play.fill")
                        .symbolEffect(.pulse, isActive: viewModel.isProcessing)
                    Text(viewModel.isProcessing
                         ? "\(Int(viewModel.progress * 100))%"
                         : "Start Pipeline")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isStartDisabled)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}
