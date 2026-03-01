import SwiftUI
import AVFoundation
import UIKit

struct RenderedVideoPreviewView: View {
    @ObservedObject var viewModel: CameraViewModel

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                EditorStepTitle(
                    title: "Saved Video",
                    subtitle: "Your edited video has been saved"
                )

                if let player = viewModel.player {
                    CineVideoPlayer(player: player, showsPlaybackControls: true)
                        .frame(maxWidth: .infinity)
                        .frame(height: min(max(geometry.size.height * 0.62, 320), 560))
                        .background(Color.black.opacity(0.55))
                        .cornerRadius(CineTheme.buttonCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: CineTheme.buttonCornerRadius, style: .continuous)
                                .stroke(CineTheme.orange.opacity(0.35), lineWidth: 1)
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Button(action: openGallery) {
                        Text("Open Gallery")
                    }
                    .cineButtonStyle(isPrimary: false, compact: true)

                    Button(action: { viewModel.navigateBackToCamera() }) {
                        Text("New Video")
                    }
                    .cineButtonStyle(isPrimary: true, compact: true)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            viewModel.player?.pause()
            viewModel.player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    private func openGallery() {
        guard let photosURL = URL(string: "photos-redirect://") else { return }
        UIApplication.shared.open(photosURL, options: [:], completionHandler: nil)
    }
}
