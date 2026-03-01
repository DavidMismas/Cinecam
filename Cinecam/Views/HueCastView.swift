import SwiftUI

struct HueCastView: View {
    @ObservedObject var viewModel: CameraViewModel

    @State private var selectedCastTarget: CastTarget = .global

    private enum CastTarget: String, CaseIterable, Identifiable {
        case global = "Global"
        case shadows = "Shadows"
        case highlights = "Highlights"

        var id: String { rawValue }
    }

    private var activeHue: Binding<Double> {
        switch selectedCastTarget {
        case .global:
            return $viewModel.adjustmentSettings.globalCastHue
        case .shadows:
            return $viewModel.adjustmentSettings.shadowsCastHue
        case .highlights:
            return $viewModel.adjustmentSettings.highlightsCastHue
        }
    }

    private var activeCastAmount: Binding<Double> {
        switch selectedCastTarget {
        case .global:
            return $viewModel.adjustmentSettings.globalColorCast
        case .shadows:
            return $viewModel.adjustmentSettings.shadowsColorCast
        case .highlights:
            return $viewModel.adjustmentSettings.highlightsColorCast
        }
    }

    private var activeHueSwatch: Color {
        Color(hue: activeHue.wrappedValue / 360.0, saturation: 0.9, brightness: 0.9)
    }

    private var castLabel: String {
        "\(selectedCastTarget.rawValue) Cast (+/-)"
    }

    var body: some View {
        VStack(spacing: 8) {
            EditorStepTitle(
                title: "Step 3 · Hue Cast",
                subtitle: "Pick a zone, then adjust one color + one cast slider"
            )

            if let player = viewModel.player, let sourceURL = viewModel.recordedVideoURL {
                VideoEditorPreviewPanel(player: player, sourceURL: sourceURL)
            }

            VStack(spacing: 10) {
                Picker("Target", selection: $selectedCastTarget) {
                    ForEach(CastTarget.allCases) { target in
                        Text(target.rawValue).tag(target)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("\(selectedCastTarget.rawValue) Hue")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(Int(activeHue.wrappedValue.rounded()))°")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundColor(CineTheme.orange)
                    }

                    Slider(value: activeHue, in: 0...360)
                        .tint(activeHueSwatch)
                        .scaleEffect(x: 1.0, y: 0.78, anchor: .center)
                        .frame(height: 16)

                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(activeHueSwatch)
                        .frame(height: 6)
                }

                AdjustmentSlider(
                    title: castLabel,
                    value: activeCastAmount,
                    range: -1.0...1.0
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 4)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button(action: { viewModel.navigateToColorBalance() }) {
                    Text("Back")
                }
                .cineButtonStyle(isPrimary: false, compact: true)

                Button(action: { viewModel.navigateToTextureEffects() }) {
                    Text("Next")
                }
                .cineButtonStyle(isPrimary: true, compact: true)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: viewModel.adjustmentSettings.globalCastHue) { _, _ in viewModel.updatePlayerPreview() }
        .onChange(of: viewModel.adjustmentSettings.shadowsCastHue) { _, _ in viewModel.updatePlayerPreview() }
        .onChange(of: viewModel.adjustmentSettings.highlightsCastHue) { _, _ in viewModel.updatePlayerPreview() }
        .onChange(of: viewModel.adjustmentSettings.globalColorCast) { _, _ in viewModel.updatePlayerPreview() }
        .onChange(of: viewModel.adjustmentSettings.shadowsColorCast) { _, _ in viewModel.updatePlayerPreview() }
        .onChange(of: viewModel.adjustmentSettings.highlightsColorCast) { _, _ in viewModel.updatePlayerPreview() }
    }
}
