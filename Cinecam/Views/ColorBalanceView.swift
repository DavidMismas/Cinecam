import SwiftUI

struct ColorBalanceView: View {
    @ObservedObject var viewModel: CameraViewModel

    var body: some View {
        VStack(spacing: 8) {
            EditorStepTitle(
                title: "Step 2 · Color",
                subtitle: "White balance, tint, saturation, vibrance"
            )

            if let player = viewModel.player, let sourceURL = viewModel.recordedVideoURL {
                VideoEditorPreviewPanel(player: player, sourceURL: sourceURL)
            }

            ScrollView {
                VStack(spacing: 12) {
                    AdjustmentSlider(title: "Red / Blue", value: $viewModel.adjustmentSettings.redBlueBalance, range: -1.0...1.0)
                    AdjustmentSlider(title: "Green / Tint", value: $viewModel.adjustmentSettings.greenTint, range: -1.0...1.0)
                    AdjustmentSlider(title: "Saturation (+/-)", value: $viewModel.adjustmentSettings.saturationAdjustment, range: -1.0...1.0)
                    AdjustmentSlider(title: "Vibrance (+/-)", value: $viewModel.adjustmentSettings.vibrance, range: -1.0...1.0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 4)
            }
            .frame(maxHeight: 190)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button(action: { viewModel.navigateToBasicAdjustments() }) {
                    Text("Back")
                }
                .cineButtonStyle(isPrimary: false, compact: true)

                Button(action: { viewModel.navigateToHueCast() }) {
                    Text("Next")
                }
                .cineButtonStyle(isPrimary: true, compact: true)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: viewModel.adjustmentSettings.redBlueBalance) { _, _ in viewModel.updatePlayerPreview() }
        .onChange(of: viewModel.adjustmentSettings.greenTint) { _, _ in viewModel.updatePlayerPreview() }
        .onChange(of: viewModel.adjustmentSettings.saturationAdjustment) { _, _ in viewModel.updatePlayerPreview() }
        .onChange(of: viewModel.adjustmentSettings.vibrance) { _, _ in viewModel.updatePlayerPreview() }
    }
}
