import SwiftUI

struct BasicAdjustmentsView: View {
    @ObservedObject var viewModel: CameraViewModel

    @State private var statusMessage: String?
    @State private var isSavingOriginal = false
    @State private var renderSpin = false

    var body: some View {
        VStack(spacing: 8) {
            EditorStepTitle(
                title: "Step 1 · Base",
                subtitle: "Exposure, contrast, shadows, highlights"
            )

            if let player = viewModel.player, let sourceURL = viewModel.recordedVideoURL {
                VideoEditorPreviewPanel(player: player, sourceURL: sourceURL)
            }

            if !viewModel.presets.isEmpty {
                PresetQuickPicker(viewModel: viewModel)
                    .padding(.horizontal, 16)
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
            .frame(maxHeight: 170)

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
        .overlay {
            if viewModel.isRenderingFinalVideo {
                BasicRenderProgressOverlay(progress: viewModel.renderProgress, spin: renderSpin)
                    .transition(.opacity)
            }
        }
        .onChange(of: viewModel.isRenderingFinalVideo) { _, isRendering in
            if isRendering {
                renderSpin = false
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    renderSpin = true
                }
            } else {
                renderSpin = false
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
        // If any adjustments are active (including preset), save rendered output.
        guard !viewModel.adjustmentSettings.isIdentity else {
            saveToLibrary(url: sourceURL, successMessage: "Original saved")
            return
        }

        viewModel.renderFinalVideo { renderResult in
            switch renderResult {
            case .success(let renderedURL):
                saveToLibrary(url: renderedURL, successMessage: "Saved with adjustments")
            case .failure:
                DispatchQueue.main.async {
                    isSavingOriginal = false
                    showStatus("Render failed")
                }
            }
        }
    }

    private func saveToLibrary(url: URL, successMessage: String) {
        VideoLibrarySaver.saveVideo(url: url) { result in
            DispatchQueue.main.async {
                isSavingOriginal = false
                switch result {
                case .success:
                    showStatus(successMessage)
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

private struct BasicRenderProgressOverlay: View {
    let progress: Double
    let spin: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.16), lineWidth: 7)
                        .frame(width: 84, height: 84)

                    Circle()
                        .trim(from: 0, to: max(0.08, min(progress, 1.0)))
                        .stroke(
                            AngularGradient(
                                colors: [CineTheme.orange, .yellow, CineTheme.orange],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .frame(width: 84, height: 84)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                }

                Text("Rendering video...")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                Text("\(Int((max(0.0, min(progress, 1.0)) * 100).rounded()))%")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(CineTheme.darkGray.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(CineTheme.orange.opacity(0.45), lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
        .allowsHitTesting(true)
    }
}

private struct PresetQuickPicker: View {
    @ObservedObject var viewModel: CameraViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Presets")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(CineTheme.orange)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(action: { viewModel.resetAdjustmentsToDefault() }) {
                        Text("None")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(CineTheme.darkGray)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1)
                            )
                    }

                    ForEach(viewModel.presets) { preset in
                        let isActive = preset.settings == viewModel.adjustmentSettings
                        Button(action: { viewModel.applyPreset(preset) }) {
                            Text(preset.name)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(isActive ? CineTheme.darkBackground : .white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(isActive ? CineTheme.orange : CineTheme.darkGray)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(CineTheme.orange.opacity(isActive ? 0.0 : 0.45), lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(CineTheme.darkGray.opacity(0.52))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
