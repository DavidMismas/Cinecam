import SwiftUI

struct TextureEffectsView: View {
    @ObservedObject var viewModel: CameraViewModel

    var body: some View {
        VStack(spacing: 8) {
            EditorStepTitle(
                title: "Step 4 · Texture",
                subtitle: "Texture, clarity (+/-), grain, vignette"
            )

            if let player = viewModel.player, let sourceURL = viewModel.recordedVideoURL {
                VideoEditorPreviewPanel(player: player, sourceURL: sourceURL)
            }

            ScrollView {
                VStack(spacing: 12) {
                    AdjustmentSlider(title: "Texture (+/-)", value: $viewModel.adjustmentSettings.texture, range: -1.0...1.0)
                    AdjustmentSlider(title: "Clarity (+/-)", value: $viewModel.adjustmentSettings.clarity, range: -1.0...1.0)
                    AdjustmentSlider(title: "Grain", value: $viewModel.adjustmentSettings.grain, range: 0.0...1.0)
                    AdjustmentSlider(title: "Vignette", value: $viewModel.adjustmentSettings.vignette, range: 0.0...1.0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 4)
            }
            .frame(maxHeight: 190)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button(action: { viewModel.navigateToHueCast() }) {
                    Text("Back")
                }
                .cineButtonStyle(isPrimary: false, compact: true)

                Button(action: { viewModel.navigateToFinalEffects() }) {
                    Text("Next")
                }
                .cineButtonStyle(isPrimary: true, compact: true)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: viewModel.adjustmentSettings.texture) { _, _ in viewModel.updatePlayerPreview() }
        .onChange(of: viewModel.adjustmentSettings.clarity) { _, _ in viewModel.updatePlayerPreview() }
        .onChange(of: viewModel.adjustmentSettings.grain) { _, _ in viewModel.updatePlayerPreview() }
        .onChange(of: viewModel.adjustmentSettings.vignette) { _, _ in viewModel.updatePlayerPreview() }
    }
}
