import SwiftUI

struct BasicAdjustmentsView: View {
    @ObservedObject var viewModel: CameraViewModel

    @State private var statusMessage: String?
    @State private var isSavingOriginal = false

    var body: some View {
        VStack(spacing: 8) {
            EditorStepTitle(
                title: "Step 1 · Base",
                subtitle: "Exposure, contrast, shadows, highlights"
            )

            if let player = viewModel.player, let sourceURL = viewModel.recordedVideoURL {
                VideoEditorPreviewPanel(player: player, sourceURL: sourceURL)
            }

            ScrollView {
                VStack(spacing: 12) {
                    AdjustmentSlider(title: "Exposure", value: $viewModel.adjustmentSettings.exposure, range: -2.0...2.0)
                    AdjustmentSlider(title: "Contrast", value: $viewModel.adjustmentSettings.contrast, range: 0.0...2.0)
                    AdjustmentSlider(title: "Shadows", value: $viewModel.adjustmentSettings.shadows, range: -1.0...1.0)
                    AdjustmentSlider(title: "Highlights", value: $viewModel.adjustmentSettings.highlights, range: -1.0...1.0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 4)
            }
            .frame(maxHeight: 190)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button(action: { viewModel.navigateBackToCamera() }) {
                    Text("Back")
                }
                .cineButtonStyle(isPrimary: false, compact: true)

                Button(action: saveOriginalNow) {
                    Text(isSavingOriginal ? "Saving..." : "Save now")
                }
                .cineButtonStyle(isPrimary: false, compact: true)
                .disabled(isSavingOriginal)
                .opacity(isSavingOriginal ? 0.65 : 1.0)

                Button(action: { viewModel.navigateToColorBalance() }) {
                    Text("Next")
                }
                .cineButtonStyle(isPrimary: true, compact: true)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(CineTheme.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.82))
                    .clipShape(Capsule())
                    .padding(.top, 12)
            }
        }
        .onChange(of: viewModel.adjustmentSettings.exposure) { _, _ in viewModel.updatePlayerPreview() }
        .onChange(of: viewModel.adjustmentSettings.contrast) { _, _ in viewModel.updatePlayerPreview() }
        .onChange(of: viewModel.adjustmentSettings.shadows) { _, _ in viewModel.updatePlayerPreview() }
        .onChange(of: viewModel.adjustmentSettings.highlights) { _, _ in viewModel.updatePlayerPreview() }
    }

    private func saveOriginalNow() {
        guard let sourceURL = viewModel.recordedVideoURL else {
            showStatus("No source video")
            return
        }

        isSavingOriginal = true
        VideoLibrarySaver.saveVideo(url: sourceURL) { result in
            DispatchQueue.main.async {
                isSavingOriginal = false
                switch result {
                case .success:
                    showStatus("Original saved")
                case .failure:
                    showStatus("Save failed")
                }
            }
        }
    }

    private func showStatus(_ message: String) {
        statusMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if statusMessage == message {
                statusMessage = nil
            }
        }
    }
}
