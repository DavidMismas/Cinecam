import SwiftUI
import AVFoundation

struct FinalEffectsView: View {
    @ObservedObject var viewModel: CameraViewModel

    @State private var showFullscreenPreview = false
    @State private var statusMessage: String?
    @State private var renderSpin = false

    var body: some View {
        VStack(spacing: 8) {
            EditorStepTitle(
                title: "Step 5 · Final FX",
                subtitle: "Bloom, soft glow and dust/scratches"
            )

            if let player = viewModel.player, let sourceURL = viewModel.recordedVideoURL {
                VideoEditorPreviewPanel(player: player, sourceURL: sourceURL)
            }

            ScrollView {
                VStack(spacing: 12) {
                    AdjustmentSlider(title: "Bloom", value: $viewModel.adjustmentSettings.bloom, range: 0.0...1.0)
                    AdjustmentSlider(title: "Soft Glow", value: $viewModel.adjustmentSettings.softGlow, range: 0.0...1.0)
                    AdjustmentSlider(title: "Dust / Scratches", value: $viewModel.adjustmentSettings.vhsAmount, range: 0.0...1.0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 4)
            }
            .frame(maxHeight: 185)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button(action: { viewModel.navigateToTextureEffects() }) {
                    Text("Back")
                }
                .cineButtonStyle(isPrimary: false, compact: true)

                Button(action: { showFullscreenPreview = true }) {
                    Text("Fullscreen")
                }
                .cineButtonStyle(isPrimary: false, compact: true)
            }
            .padding(.horizontal, 16)

            Button(action: saveEditedVideo) {
                if viewModel.isRenderingFinalVideo {
                    Text("Rendering \(Int((viewModel.renderProgress * 100).rounded()))%")
                } else {
                    Text("Save")
                }
            }
            .cineButtonStyle(isPrimary: true, compact: true)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .disabled(viewModel.isRenderingFinalVideo || viewModel.recordedVideoURL == nil)
            .opacity((viewModel.isRenderingFinalVideo || viewModel.recordedVideoURL == nil) ? 0.65 : 1.0)
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
                RenderProgressOverlay(progress: viewModel.renderProgress, spin: renderSpin)
                    .transition(.opacity)
            }
        }
        .fullScreenCover(isPresented: $showFullscreenPreview) {
            if let player = viewModel.player {
                FullscreenEditedPreview(player: player)
            }
        }
        .onChange(of: viewModel.adjustmentSettings.bloom) { _, _ in viewModel.updatePlayerPreview() }
        .onChange(of: viewModel.adjustmentSettings.softGlow) { _, _ in viewModel.updatePlayerPreview() }
        .onChange(of: viewModel.adjustmentSettings.vhsAmount) { _, _ in viewModel.updatePlayerPreview() }
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
    }

    private func saveEditedVideo() {
        viewModel.renderFinalVideo { result in
            switch result {
            case .success(let renderedURL):
                VideoLibrarySaver.saveVideo(url: renderedURL) { saveResult in
                    DispatchQueue.main.async {
                        switch saveResult {
                        case .success:
                            viewModel.navigateToRenderedPreview(with: renderedURL)
                        case .failure:
                            showStatus("Save failed")
                        }
                    }
                }
            case .failure:
                DispatchQueue.main.async {
                    showStatus("Render failed")
                }
            }
        }
    }

    private func showStatus(_ message: String) {
        statusMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if statusMessage == message {
                statusMessage = nil
            }
        }
    }
}

private struct RenderProgressOverlay: View {
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

private struct FullscreenEditedPreview: View {
    let player: AVPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            CineVideoPlayer(player: player, showsPlaybackControls: false)
                .ignoresSafeArea()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .padding(20)
            }
        }
        .statusBar(hidden: true)
        .onAppear {
            player.pause()
        }
        .onDisappear {
            player.pause()
        }
    }
}
